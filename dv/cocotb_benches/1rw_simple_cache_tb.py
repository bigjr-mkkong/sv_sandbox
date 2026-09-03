import itertools
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotbext.axi import AxiLiteBus, AxiLiteRam

from dv.cocotb_benches.MESI_protocol_tb import BUS_RD, BUS_RDX, BUS_UPGR
from dv.cocotb_benches.upstream_if import UpstreamMaster


CLOCK_PERIOD_NS = 10
TEST_TIMEOUT_US = 250
ADDR_WIDTH = 64
DATA_WIDTH = 64
DATA_BYTES = DATA_WIDTH // 8
DATA_PER_LINE = 8
CACHE_SIZE_KIB = 16
LINE_BYTES = DATA_BYTES * DATA_PER_LINE
ROW_COUNT = CACHE_SIZE_KIB * 1024 // LINE_BYTES
OFFSET_BITS = LINE_BYTES.bit_length() - 1
INDEX_BITS = ROW_COUNT.bit_length() - 1
RAM_SIZE = 1 << 20
TEST_CACHE2BUS = 0
TEST_SNOOP = 1


def cycle_pause(pattern=(1, 1, 1, 0)):
    return itertools.cycle(pattern)


def cache_address(tag, index, word=0):
    """Build a byte address from direct-mapped cache address fields."""
    assert 0 <= index < ROW_COUNT
    assert 0 <= word < DATA_PER_LINE
    return (
        (tag << (INDEX_BITS + OFFSET_BITS))
        | (index << OFFSET_BITS)
        | (word * DATA_BYTES)
    )


def line_address(address):
    return address & ~(LINE_BYTES - 1)


def pack_line(words):
    assert len(words) == DATA_PER_LINE
    return b"".join(value.to_bytes(DATA_BYTES, "little") for value in words)


def unpack_line(data):
    assert len(data) == LINE_BYTES
    return [
        int.from_bytes(data[offset : offset + DATA_BYTES], "little")
        for offset in range(0, LINE_BYTES, DATA_BYTES)
    ]


class PseudoCoherenceBus:
    """Control one direction of the wrapper's pseudo coherence bus."""

    def __init__(self, dut):
        self.dut = dut
        self.mode = None
        self.expected_count = 0
        self.rng = random.Random(0xC2B5EED)
        dut.coherence_test_mode.value = TEST_CACHE2BUS
        dut.c2b_accept_enable.value = 1
        dut.c2b_rsp_delay_cycles.value = 1
        dut.c2b_rsp_shared.value = 0
        dut.c2b_check_req.value = 0
        dut.c2b_expected_req_op.value = 0
        dut.c2b_expected_req_addr.value = 0
        dut.snoop_start.value = 0
        dut.snoop_req_op.value = 0
        dut.snoop_req_addr.value = 0
        dut.snoop_rsp_ready_delay_cycles.value = 0
        dut.snoop_done_rdy.value = 0

    def select_cache2bus(self):
        """Enable only the FSM that answers cache-originated bus requests."""
        self.mode = TEST_CACHE2BUS
        self.dut.coherence_test_mode.value = TEST_CACHE2BUS

    def select_snoop(self):
        """Enable only the FSM that originates bus-to-cache snoops."""
        self.mode = TEST_SNOOP
        self.dut.coherence_test_mode.value = TEST_SNOOP

    @property
    def shared(self):
        return bool(self.dut.c2b_rsp_shared.value)

    @shared.setter
    def shared(self, value):
        self.dut.c2b_rsp_shared.value = int(value)

    def expect_cache2bus(
        self, bus_op, address, *, shared=None, delay_cycles=None
    ):
        """Configure one delayed response to a cache-originated request."""
        assert self.mode == TEST_CACHE2BUS
        if shared is not None:
            self.shared = shared
        if delay_cycles is None:
            delay_cycles = self.rng.randrange(1, 33)
        self.dut.c2b_rsp_delay_cycles.value = delay_cycles
        self.dut.c2b_expected_req_op.value = bus_op
        self.dut.c2b_expected_req_addr.value = line_address(address)
        self.dut.c2b_check_req.value = 1
        self.expected_count += 1

    async def send_snoop(
        self, bus_op, address, *, response_ready_delay_cycles=0
    ):
        """Issue one snoop and return the cache's shared response."""
        assert self.mode == TEST_SNOOP
        assert not self.dut.snoop_busy_o.value
        self.dut.snoop_req_op.value = bus_op
        self.dut.snoop_req_addr.value = line_address(address)
        self.dut.snoop_rsp_ready_delay_cycles.value = (
            response_ready_delay_cycles
        )
        self.dut.snoop_start.value = 1
        await RisingEdge(self.dut.clk_i)
        self.dut.snoop_start.value = 0

        while not self.dut.snoop_done_o.value:
            await RisingEdge(self.dut.clk_i)

        shared = bool(self.dut.snoop_rsp_shared_o.value)
        self.dut.snoop_done_rdy.value = 1
        await RisingEdge(self.dut.clk_i)
        self.dut.snoop_done_rdy.value = 0
        return shared

    def assert_expectations(self):
        assert self.mode == TEST_CACHE2BUS
        assert int(self.dut.c2b_req_mismatch_o.value) == 0
        assert int(self.dut.c2b_req_count_o.value) == self.expected_count


class CacheTB:
    def __init__(self, dut):
        self.dut = dut
        cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())

        self.master = UpstreamMaster(dut.upstream, dut.clk_i)
        self.coherence = PseudoCoherenceBus(dut)
        self.ram = AxiLiteRam(
            AxiLiteBus.from_entity(dut.m_axil),
            dut.clk_i,
            dut.rst_ni,
            reset_active_level=False,
            size=RAM_SIZE,
        )

    async def reset(self):
        self.dut.rst_ni.value = 0
        for _ in range(10):
            await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        for _ in range(2):
            await RisingEdge(self.dut.clk_i)

    async def read_word(self, address, *, response_delay_cycles=0):
        return await self.master.read(
            address, response_delay_cycles=response_delay_cycles
        )

    async def write_word(self, address, value, *, response_delay_cycles=0):
        response = await self.master.write(
            address,
            value,
            response_delay_cycles=response_delay_cycles,
        )
        assert response == 0


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def reset_invalidates_every_cache_line(dut):
    """Every index must fetch the zero-initialized backing line after reset."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()

    for index in range(ROW_COUNT):
        address = cache_address(tag=0, index=index)
        tb.coherence.expect_cache2bus(BUS_RD, address)
        assert await tb.read_word(address) == 0
    tb.coherence.assert_expectations()


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def read_miss_fills_the_complete_line(dut):
    """One downstream 512-bit read populates every word in the cache line."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    base = line_address(cache_address(tag=2, index=11))
    original = [0x1000 + index for index in range(DATA_PER_LINE)]
    replacement = [0x9000 + index for index in range(DATA_PER_LINE)]
    tb.ram.write(base, pack_line(original))

    tb.coherence.expect_cache2bus(BUS_RD, base)
    assert await tb.read_word(base + 3 * DATA_BYTES) == original[3]
    tb.coherence.assert_expectations()

    # Alter backing memory after the fill; every subsequent word must still hit.
    tb.ram.write(base, pack_line(replacement))
    for word, expected in enumerate(original):
        assert await tb.read_word(base + word * DATA_BYTES) == expected
    tb.coherence.assert_expectations()


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def write_miss_fetches_and_merges_the_complete_line(dut):
    """A write miss preserves every untouched word from the LLC line."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    base = line_address(cache_address(tag=1, index=7))
    backing = [0xABC000 + index for index in range(DATA_PER_LINE)]
    value = 0x0123456789ABCDEF
    tb.ram.write(base, pack_line(backing))

    tb.coherence.expect_cache2bus(BUS_RDX, base)
    await tb.write_word(base + 5 * DATA_BYTES, value)

    tb.coherence.assert_expectations()
    assert unpack_line(tb.ram.read(base, LINE_BYTES)) == backing
    assert await tb.read_word(base + 5 * DATA_BYTES) == value
    assert await tb.read_word(base + 2 * DATA_BYTES) == backing[2]


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def shared_read_hit_upgrades_before_write(dut):
    """A write to a Shared line issues BusUpgr before modifying local data."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    base = line_address(cache_address(tag=3, index=13))
    backing = [0x3300 + index for index in range(DATA_PER_LINE)]
    updated = 0xCAFECAFE12345678
    tb.ram.write(base, pack_line(backing))

    tb.coherence.expect_cache2bus(BUS_RD, base, shared=True)
    assert await tb.read_word(base + DATA_BYTES) == backing[1]
    tb.coherence.expect_cache2bus(BUS_UPGR, base)
    await tb.write_word(base + DATA_BYTES, updated)

    tb.coherence.assert_expectations()
    assert await tb.read_word(base + DATA_BYTES) == updated
    assert unpack_line(tb.ram.read(base, LINE_BYTES)) == backing


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def exclusive_and_modified_hits_do_not_reenter_the_bus(dut):
    """E/M hits use local BusNOP transitions without a global transaction."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    base = line_address(cache_address(tag=4, index=17))
    backing = [0x4400 + index for index in range(DATA_PER_LINE)]
    first_update = 0x0123456789ABCDEF
    second_update = 0xFEDCBA9876543210
    tb.ram.write(base, pack_line(backing))

    tb.coherence.expect_cache2bus(BUS_RD, base, shared=False)
    assert await tb.read_word(base + DATA_BYTES) == backing[1]
    await tb.write_word(base + DATA_BYTES, first_update)
    assert await tb.read_word(base + DATA_BYTES) == first_update
    await tb.write_word(base + 6 * DATA_BYTES, second_update)
    assert await tb.read_word(base + 6 * DATA_BYTES) == second_update

    tb.coherence.assert_expectations()
    assert unpack_line(tb.ram.read(base, LINE_BYTES)) == backing


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def bus_request_and_response_backpressure_hold_the_transaction(dut):
    """Hold the bus request, then use the response configuration at acceptance."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    base = line_address(cache_address(tag=6, index=29))
    backing = [0x6600 + index for index in range(DATA_PER_LINE)]
    updated = 0xA5A55A5ADEADBEEF
    tb.ram.write(base, pack_line(backing))

    tb.dut.c2b_accept_enable.value = 0
    tb.coherence.expect_cache2bus(
        BUS_RD, base, shared=True, delay_cycles=12
    )
    read_task = cocotb.start_soon(tb.read_word(base + 3 * DATA_BYTES))

    for _ in range(20):
        await RisingEdge(dut.clk_i)
        if dut.coh_bus_req.req_val.value:
            break
    assert dut.coh_bus_req.req_val.value
    assert int(dut.coh_bus_req.bus_op.value) == BUS_RD
    assert int(dut.coh_bus_req.req_addr.value) == base

    for _ in range(5):
        await RisingEdge(dut.clk_i)
        assert dut.coh_bus_req.req_val.value
        assert int(dut.coh_bus_req.bus_op.value) == BUS_RD
        assert int(dut.coh_bus_req.req_addr.value) == base
        assert int(dut.c2b_req_count_o.value) == 0

    tb.dut.c2b_accept_enable.value = 1
    await RisingEdge(dut.clk_i)
    # Changing the live configuration cannot alter the accepted response.
    tb.coherence.shared = False
    for _ in range(4):
        await RisingEdge(dut.clk_i)
    assert dut.c2b_busy_o.value

    assert await read_task == backing[3]
    tb.coherence.expect_cache2bus(BUS_UPGR, base, delay_cycles=3)
    await tb.write_word(base + 3 * DATA_BYTES, updated)
    assert await tb.read_word(base + 3 * DATA_BYTES) == updated
    tb.coherence.assert_expectations()


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def clean_victim_is_replaced_without_a_writeback(dut):
    """Replacing an Exclusive line must not overwrite newer LLC contents."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    old_base = line_address(cache_address(tag=2, index=41))
    new_base = line_address(cache_address(tag=7, index=41))
    old_line = [0x2200 + index for index in range(DATA_PER_LINE)]
    newer_llc_line = [0x2F00 + index for index in range(DATA_PER_LINE)]
    new_line = [0x7700 + index for index in range(DATA_PER_LINE)]
    tb.ram.write(old_base, pack_line(old_line))
    tb.ram.write(new_base, pack_line(new_line))

    tb.coherence.expect_cache2bus(BUS_RD, old_base, shared=False)
    assert await tb.read_word(old_base + 2 * DATA_BYTES) == old_line[2]
    tb.ram.write(old_base, pack_line(newer_llc_line))

    tb.coherence.expect_cache2bus(BUS_RD, new_base)
    assert await tb.read_word(new_base + 5 * DATA_BYTES) == new_line[5]
    assert unpack_line(tb.ram.read(old_base, LINE_BYTES)) == newer_llc_line
    tb.coherence.assert_expectations()


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def dirty_victim_is_written_back_as_one_line(dut):
    """Replacing a dirty tag writes all 512 bits before installing the new tag."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    old_base = line_address(cache_address(tag=1, index=19))
    new_base = line_address(cache_address(tag=5, index=19))
    old_backing = [0x1100 + index for index in range(DATA_PER_LINE)]
    new_backing = [0x5500 + index for index in range(DATA_PER_LINE)]
    old_value = 0x1111222233334444
    new_value = 0xAAAABBBBCCCCDDDD
    tb.ram.write(old_base, pack_line(old_backing))
    tb.ram.write(new_base, pack_line(new_backing))

    tb.coherence.expect_cache2bus(BUS_RD, old_base)
    assert await tb.read_word(old_base + 2 * DATA_BYTES) == old_backing[2]
    await tb.write_word(old_base + 2 * DATA_BYTES, old_value)
    tb.coherence.expect_cache2bus(BUS_RDX, new_base)
    await tb.write_word(new_base + 4 * DATA_BYTES, new_value)

    expected_old = old_backing.copy()
    expected_old[2] = old_value
    assert unpack_line(tb.ram.read(old_base, LINE_BYTES)) == expected_old
    assert unpack_line(tb.ram.read(new_base, LINE_BYTES)) == new_backing
    assert await tb.read_word(new_base + 4 * DATA_BYTES) == new_value

    # Reading the old tag evicts the new dirty line, then reloads the old line.
    tb.coherence.expect_cache2bus(BUS_RD, old_base)
    assert await tb.read_word(old_base + 2 * DATA_BYTES) == old_value
    expected_new = new_backing.copy()
    expected_new[4] = new_value
    assert unpack_line(tb.ram.read(new_base, LINE_BYTES)) == expected_new
    tb.coherence.assert_expectations()


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def randomized_write_back_model(dut):
    """Compare mixed traffic against a direct-mapped write-back software model."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    rng = random.Random(0x1CA5E)
    backing = {}
    model_cache = {}
    requests = []

    for tag in range(8):
        for index in range(32):
            words = [rng.getrandbits(DATA_WIDTH) for _ in range(DATA_PER_LINE)]
            backing[(tag, index)] = words
            tb.ram.write(
                line_address(cache_address(tag, index)),
                pack_line(words),
            )

    for _ in range(100):
        requests.append(
            (
                rng.randrange(8),
                rng.randrange(32),
                rng.randrange(DATA_PER_LINE),
                rng.random() < 0.55,
                rng.getrandbits(DATA_WIDTH),
            )
        )

    for tag, index, word, is_write, value in requests:
        address = cache_address(tag, index, word)
        resident = model_cache.get(index)
        hit = resident is not None and resident[0] == tag

        if not hit and resident is not None and resident[2]:
            backing[(resident[0], index)] = resident[1].copy()

        if is_write:
            line = (
                resident[1].copy()
                if hit
                else backing[(tag, index)].copy()
            )
            line[word] = value
            model_cache[index] = (tag, line, True)
            if not hit:
                tb.coherence.expect_cache2bus(
                    BUS_RDX, address, delay_cycles=rng.randrange(1, 33)
                )
            await tb.write_word(address, value)
        else:
            if hit:
                line = resident[1]
            else:
                line = backing[(tag, index)].copy()
                model_cache[index] = (tag, line, False)
                tb.coherence.expect_cache2bus(
                    BUS_RD, address, delay_cycles=rng.randrange(1, 33)
                )
            assert await tb.read_word(address) == line[word]

    for (tag, index), expected in backing.items():
        actual = unpack_line(
            tb.ram.read(
                line_address(cache_address(tag, index)),
                LINE_BYTES,
            )
        )
        assert actual == expected
    tb.coherence.assert_expectations()


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def upstream_response_and_downstream_axil_backpressure(dut):
    """Hold the synchronized response and stall downstream AXI-Lite channels."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    old_base = line_address(cache_address(tag=3, index=23))
    new_base = line_address(cache_address(tag=6, index=23))
    old_line = [0x3000 + index for index in range(DATA_PER_LINE)]
    new_line = [0x6000 + index for index in range(DATA_PER_LINE)]
    tb.ram.write(old_base, pack_line(old_line))
    tb.ram.write(new_base, pack_line(new_line))

    tb.ram.write_if.aw_channel.set_pause_generator(cycle_pause((1, 0, 0)))
    tb.ram.write_if.w_channel.set_pause_generator(cycle_pause((0, 1, 0)))
    tb.ram.write_if.b_channel.set_pause_generator(cycle_pause((1, 0)))
    tb.ram.read_if.ar_channel.set_pause_generator(cycle_pause((1, 1, 0)))
    tb.ram.read_if.r_channel.set_pause_generator(cycle_pause((1, 0, 0)))

    tb.coherence.expect_cache2bus(BUS_RD, old_base)
    assert await tb.read_word(old_base, response_delay_cycles=4) == old_line[0]
    updated = 0xDEADBEEF01234567
    await tb.write_word(
        old_base + DATA_BYTES, updated, response_delay_cycles=3
    )

    # This conflicting read forces an independently handshaken dirty eviction.
    tb.coherence.expect_cache2bus(BUS_RD, new_base)
    assert await tb.read_word(new_base + 2 * DATA_BYTES) == new_line[2]
    expected_old = old_line.copy()
    expected_old[1] = updated
    assert unpack_line(tb.ram.read(old_base, LINE_BYTES)) == expected_old
    tb.coherence.assert_expectations()


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def bus_read_snoop_flushes_then_downgrades_a_modified_hit(dut):
    """A BusRd hit writes back M data and retains the line in S."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    base = line_address(cache_address(tag=5, index=37))
    backing = [0x5100 + index for index in range(DATA_PER_LINE)]
    updated = 0xA55A0123456789EF
    tb.ram.write(base, pack_line(backing))

    tb.coherence.expect_cache2bus(BUS_RD, base, shared=False)
    assert await tb.read_word(base + 4 * DATA_BYTES) == backing[4]
    await tb.write_word(base + 4 * DATA_BYTES, updated)
    tb.coherence.assert_expectations()

    tb.coherence.select_snoop()
    shared = await tb.coherence.send_snoop(
        BUS_RD,
        base,
        response_ready_delay_cycles=7,
    )
    assert shared
    expected = backing.copy()
    expected[4] = updated
    assert unpack_line(tb.ram.read(base, LINE_BYTES)) == expected

    # M downgraded to S, so this access must hit without another bus request.
    tb.coherence.select_cache2bus()
    assert await tb.read_word(base + 4 * DATA_BYTES) == updated
    tb.coherence.assert_expectations()


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def bus_upgrade_snoop_invalidates_without_flushing(dut):
    """BusUpgr invalidates a hit without overwriting the LLC line."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    base = line_address(cache_address(tag=7, index=43))
    cached = [0x7100 + index for index in range(DATA_PER_LINE)]
    newer_llc = [0x7F00 + index for index in range(DATA_PER_LINE)]
    tb.ram.write(base, pack_line(cached))

    tb.coherence.expect_cache2bus(BUS_RD, base, shared=True)
    assert await tb.read_word(base + 2 * DATA_BYTES) == cached[2]
    tb.coherence.assert_expectations()
    tb.ram.write(base, pack_line(newer_llc))

    tb.coherence.select_snoop()
    assert await tb.coherence.send_snoop(BUS_UPGR, base)
    assert unpack_line(tb.ram.read(base, LINE_BYTES)) == newer_llc

    tb.coherence.select_cache2bus()
    tb.coherence.expect_cache2bus(BUS_RD, base, shared=False)
    assert await tb.read_word(base + 2 * DATA_BYTES) == newer_llc[2]
    tb.coherence.assert_expectations()


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def same_line_snoop_retries_inflight_local_coherence(dut):
    """Discard a local decision invalidated while waiting for the bus."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    base = line_address(cache_address(tag=6, index=47))
    backing = [0x6100 + index for index in range(DATA_PER_LINE)]
    updated = 0xC011CA7E5E21A11E
    tb.ram.write(base, pack_line(backing))

    # Install the line in S so the pending local write initially selects
    # BusUpgr, then prevent that request from reaching the pseudo bus.
    tb.coherence.expect_cache2bus(BUS_RD, base, shared=True)
    assert await tb.read_word(base + DATA_BYTES) == backing[1]
    tb.dut.c2b_accept_enable.value = 0
    write_task = cocotb.start_soon(
        tb.write_word(base + DATA_BYTES, updated)
    )

    for _ in range(20):
        await RisingEdge(dut.clk_i)
        if dut.coh_bus_req.req_val.value:
            break
    assert dut.coh_bus_req.req_val.value
    assert int(dut.coh_bus_req.bus_op.value) == BUS_UPGR

    # The hitting snoop invalidates the line while the local decision is in
    # flight. Its response must be consumed later as a stale decision.
    tb.coherence.select_snoop()
    assert await tb.coherence.send_snoop(BUS_UPGR, base)

    # Re-evaluation changes BusUpgr to BusRdX. The first result is discarded by
    # the serialization switch; the second result completes the local write.
    tb.coherence.select_cache2bus()
    tb.dut.c2b_accept_enable.value = 1
    tb.coherence.expect_cache2bus(BUS_RDX, base, shared=False)
    tb.coherence.expect_cache2bus(BUS_RDX, base, shared=False)
    await write_task

    assert await tb.read_word(base + DATA_BYTES) == updated
    tb.coherence.assert_expectations()
