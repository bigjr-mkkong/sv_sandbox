import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer


CLOCK_PERIOD_NS = 10

# These mirror the DUT's default parameters used by the standalone invocation.
ADDR_WIDTH = 64
DATA_WIDTH = 64
DATA_BYTES = DATA_WIDTH // 8
DATA_PER_LINE = 8
CACHE_SIZE_KIB = 16
LINE_BYTES = DATA_BYTES * DATA_PER_LINE
ROW_COUNT = CACHE_SIZE_KIB * 1024 // LINE_BYTES
OFFSET_BITS = LINE_BYTES.bit_length() - 1
INDEX_BITS = ROW_COUNT.bit_length() - 1

RSP_OK = 0
RSP_MISS = 1


def cache_address(tag, index, word=0):
    """Build a byte address from direct-mapped cache address fields."""
    assert 0 <= index < ROW_COUNT
    assert 0 <= word < DATA_PER_LINE
    return (
        (tag << (INDEX_BITS + OFFSET_BITS))
        | (index << OFFSET_BITS)
        | (word * DATA_BYTES)
    )


async def settle():
    """Move past the edge-triggered region before sampling combinational I/O."""
    await Timer(1, unit="ps")


async def start_and_reset(dut):
    cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())

    dut.rst_ni.value = 0
    dut.req_val_i.value = 0
    dut.req_addr_i.value = 0
    dut.req_data_i.value = 0
    dut.req_rw_flag_i.value = 0
    dut.rsp_rdy_i.value = 0

    for _ in range(10):
        await RisingEdge(dut.clk_i)

    await FallingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    await RisingEdge(dut.clk_i)
    await settle()

    assert int(dut.req_rdy_o.value) == 1
    assert int(dut.rsp_val_o.value) == 0


async def issue_request(dut, address, *, write=False, data=0):
    """Hold a request until the DUT accepts it."""
    await FallingEdge(dut.clk_i)
    await settle()

    dut.req_addr_i.value = address
    dut.req_data_i.value = data
    dut.req_rw_flag_i.value = int(write)
    dut.req_val_i.value = 1

    while True:
        await settle()
        if int(dut.req_rdy_o.value):
            break
        await FallingEdge(dut.clk_i)

    await RisingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    dut.req_val_i.value = 0
    await settle()


async def receive_response(
    dut,
    *,
    expected_state,
    expected_data=0,
    stall_cycles=0,
):
    """Check a response, optionally applying response backpressure."""
    while not int(dut.rsp_val_o.value):
        await FallingEdge(dut.clk_i)
        await settle()

    for _ in range(stall_cycles):
        assert int(dut.req_rdy_o.value) == 0
        assert int(dut.rsp_val_o.value) == 1
        assert int(dut.rsp_state_o.value) == expected_state
        assert int(dut.rsp_data_o.value) == expected_data
        await RisingEdge(dut.clk_i)
        await FallingEdge(dut.clk_i)
        await settle()

    assert int(dut.rsp_state_o.value) == expected_state
    assert int(dut.rsp_data_o.value) == expected_data

    dut.rsp_rdy_i.value = 1
    await RisingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    dut.rsp_rdy_i.value = 0
    await settle()

    assert int(dut.rsp_val_o.value) == 0
    assert int(dut.req_rdy_o.value) == 1


async def transact(
    dut,
    address,
    *,
    write=False,
    data=0,
    expected_state=RSP_OK,
    expected_data=0,
    stall_cycles=0,
):
    await issue_request(dut, address, write=write, data=data)
    await receive_response(
        dut,
        expected_state=expected_state,
        expected_data=expected_data,
        stall_cycles=stall_cycles,
    )


async def drive_request_stream(dut, requests):
    """Keep requests pending continuously and advance on each handshake."""
    for address, is_write, data in requests:
        await FallingEdge(dut.clk_i)
        await settle()
        dut.req_addr_i.value = address
        dut.req_data_i.value = data
        dut.req_rw_flag_i.value = int(is_write)
        dut.req_val_i.value = 1

        while not int(dut.req_rdy_o.value):
            await FallingEdge(dut.clk_i)
            await settle()

        await RisingEdge(dut.clk_i)

    await FallingEdge(dut.clk_i)
    dut.req_val_i.value = 0


async def check_response_stream(dut, expected_responses):
    """Consume and check responses while the request producer keeps running."""
    dut.rsp_rdy_i.value = 1

    for expected_state, expected_data in expected_responses:
        while True:
            await FallingEdge(dut.clk_i)
            await settle()
            if int(dut.rsp_val_o.value):
                break

        assert int(dut.rsp_state_o.value) == expected_state
        assert int(dut.rsp_data_o.value) == expected_data
        await RisingEdge(dut.clk_i)

    await FallingEdge(dut.clk_i)
    dut.rsp_rdy_i.value = 0


@cocotb.test()
async def reset_invalidates_every_cache_line(dut):
    """Every index must report a miss after reset."""
    await start_and_reset(dut)

    for index in range(ROW_COUNT):
        await transact(
            dut,
            cache_address(tag=0, index=index),
            expected_state=RSP_MISS,
        )


@cocotb.test()
async def request_fields_are_ignored_without_valid(dut):
    """Changing a write request while req_val_i is low must do nothing."""
    await start_and_reset(dut)
    address = cache_address(tag=2, index=11, word=3)

    await FallingEdge(dut.clk_i)
    dut.req_addr_i.value = address
    dut.req_data_i.value = 0xDEADBEEF01234567
    dut.req_rw_flag_i.value = 1

    for _ in range(5):
        await RisingEdge(dut.clk_i)
        await settle()
        assert int(dut.req_rdy_o.value) == 1
        assert int(dut.rsp_val_o.value) == 0

    await transact(dut, address, expected_state=RSP_MISS)


@cocotb.test()
async def single_write_then_read_hits(dut):
    """A write allocates the line and a subsequent read returns its data."""
    await start_and_reset(dut)
    address = cache_address(tag=1, index=7, word=5)
    value = 0x0123456789ABCDEF

    await transact(dut, address, write=True, data=value)
    await transact(dut, address, expected_data=value)


@cocotb.test()
async def newer_tag_replaces_same_index(dut):
    """A later write with a different tag evicts the previous cache line."""
    await start_and_reset(dut)
    old_address = cache_address(tag=1, index=19, word=2)
    new_address = cache_address(tag=5, index=19, word=2)
    old_value = 0x1111222233334444
    new_value = 0xAAAABBBBCCCCDDDD

    await transact(dut, old_address, write=True, data=old_value)
    await transact(dut, new_address, write=True, data=new_value)
    await transact(dut, new_address, expected_data=new_value)
    await transact(dut, old_address, expected_state=RSP_MISS)


@cocotb.test()
async def randomized_back_to_back_stress(dut):
    """Compare 100 mixed requests against a direct-mapped software model."""
    await start_and_reset(dut)
    rng = random.Random(0x1CA5E)
    model = {}
    requests = []
    expected_responses = []

    for _ in range(100):
        tag = rng.randrange(8)
        index = rng.randrange(32)
        word = rng.randrange(DATA_PER_LINE)
        address = cache_address(tag, index, word)
        is_write = rng.random() < 0.55

        if is_write:
            value = rng.getrandbits(DATA_WIDTH)
            resident = model.get(index)
            if resident is None or resident[0] != tag:
                line_data = [0] * DATA_PER_LINE
            else:
                line_data = resident[1].copy()
            line_data[word] = value
            model[index] = (tag, line_data)
            requests.append((address, True, value))
            expected_responses.append((RSP_OK, 0))
        else:
            resident = model.get(index)
            if resident is not None and resident[0] == tag:
                expected_state = RSP_OK
                expected_data = resident[1][word]
            else:
                expected_state = RSP_MISS
                expected_data = 0
            requests.append((address, False, 0))
            expected_responses.append((expected_state, expected_data))

    driver = cocotb.start_soon(drive_request_stream(dut, requests))
    await check_response_stream(dut, expected_responses)
    await driver


@cocotb.test()
async def response_backpressure_blocks_new_requests(dut):
    """A pending response remains stable and prevents request acceptance."""
    await start_and_reset(dut)
    resident_address = cache_address(tag=3, index=23, word=1)
    blocked_address = cache_address(tag=6, index=24, word=4)
    resident_value = 0x5A5AA5A55A5AA5A5

    await transact(
        dut,
        resident_address,
        write=True,
        data=resident_value,
    )
    await issue_request(dut, resident_address)

    assert int(dut.rsp_val_o.value) == 1
    assert int(dut.rsp_state_o.value) == RSP_OK
    assert int(dut.rsp_data_o.value) == resident_value

    dut.req_val_i.value = 1
    dut.req_rw_flag_i.value = 1
    dut.req_addr_i.value = blocked_address
    dut.req_data_i.value = 0xBAD0BAD0BAD0BAD0

    for _ in range(6):
        await RisingEdge(dut.clk_i)
        await FallingEdge(dut.clk_i)
        await settle()
        assert int(dut.req_rdy_o.value) == 0
        assert int(dut.rsp_val_o.value) == 1
        assert int(dut.rsp_state_o.value) == RSP_OK
        assert int(dut.rsp_data_o.value) == resident_value

    dut.req_val_i.value = 0
    await receive_response(
        dut,
        expected_state=RSP_OK,
        expected_data=resident_value,
    )

    # The blocked write must not have modified the cache.
    await transact(dut, blocked_address, expected_state=RSP_MISS)
    await transact(dut, resident_address, expected_data=resident_value)
