import itertools
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge
from cocotbext.axi import AxiLiteBus, AxiLiteRam

from dv.cocotb_benches.MESI_protocol_tb import (
    BUS_RD, BUS_RDX, BUS_UPGR, COH_INVALID, COH_MODIFIED, COH_SHARED,
)
from dv.cocotb_benches.handshake import monitor_handshakes
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
TEST_BUS2CACHE = 1

# Data-path tests use automatic bus replies without checking the MESI protocol.
# AxiLiteRam.read/write are synchronous backdoor accesses, not bus transactions;
# preloads finish before returning. All CPU bus operations are awaited.
# Backpressure tests run independent producers/consumers and count actual stalls.


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

    def select_bus2cache(self):
        """Enable only the FSM that originates bus-to-cache snoops."""
        self.mode = TEST_BUS2CACHE
        self.dut.coherence_test_mode.value = TEST_BUS2CACHE

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
        assert self.mode == TEST_BUS2CACHE
        assert not self.dut.snoop_busy_o.value
        self.dut.snoop_req_op.value = bus_op
        self.dut.snoop_req_addr.value = line_address(address)
        self.dut.snoop_rsp_ready_delay_cycles.value = (
            response_ready_delay_cycles
        )
        self.dut.snoop_start.value = 1
        await RisingEdge(self.dut.clk_i)
        self.dut.snoop_start.value = 0

        bus = self.dut.snoop_bus_req
        stalled_cycles = 0
        held_shared = None
        self.dut.snoop_done_rdy.value = 1
        while True:
            await RisingEdge(self.dut.clk_i)
            if held_shared is not None:
                assert bus.rsp_val.value, "snoop response dropped while stalled"
                assert bool(bus.rsp_shared.value) == held_shared
            if bus.rsp_val.value and not bus.rsp_rdy.value:
                stalled_cycles += 1
                held_shared = bool(bus.rsp_shared.value)
            else:
                held_shared = None
            if self.dut.snoop_done_o.value:
                assert stalled_cycles == response_ready_delay_cycles
                shared = bool(self.dut.snoop_rsp_shared_o.value)
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

    async def reset(self, *, wait_for_init=True):
        """Wait for coherence initialization unless testing the reset window."""
        self.dut.rst_ni.value = 0
        for _ in range(10):
            await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        for _ in range(2):
            await RisingEdge(self.dut.clk_i)
        if wait_for_init:
            for _ in range(ROW_COUNT + 1):
                await FallingEdge(self.dut.clk_i)
                if int(self.dut.dut.cache_reset_fin.value):
                    await RisingEdge(self.dut.clk_i)
                    return
            raise AssertionError("cache initialization did not finish")

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
async def reset_initialization_holds_upstream_request(dut):
    # Serialized reset takes time, this one will validate if it really finish
    """A request held valid during the reset sweep is accepted only afterward."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()  # Answer cache-originated requests only.
    await tb.reset(wait_for_init=False)
    target_addr = cache_address(tag=1, index=255)
    pending = cocotb.start_soon(tb.read_word(target_addr))
    blocked_cycles = 0
    for _ in range(ROW_COUNT + 1):
        await FallingEdge(dut.clk_i)
        if dut.dut.cache_reset_fin.value:
            break
        blocked_cycles += 1
        assert dut.upstream.req_val.value
        assert not dut.upstream.req_rdy.value
        assert not dut.dut.responder_idx_avail.value
        assert not dut.upstream.rsp_val.value
        assert int(dut.c2b_req_count_o.value) == 0
    else:
        raise AssertionError("cache initialization never completed")
    assert blocked_cycles > 0
    assert await pending == 0


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def reset_invalidates_every_cache_line(dut):
    """Inspect every hardware MESI entry after cold and populated-cache reset."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()

    coh_array = dut.dut.cache_committer_inst.coh_array
    for index in range(ROW_COUNT):
        assert int(coh_array[index].value) == COH_INVALID, f"cold reset row {index}"

    # Populate every row so a no-op warm reset cannot pass this check.
    for index in range(ROW_COUNT):
        await tb.write_word(cache_address(tag=0, index=index), index + 1)
    await FallingEdge(dut.clk_i)
    for index in range(ROW_COUNT):
        assert int(coh_array[index].value) == COH_MODIFIED

    await tb.reset()
    for index in range(ROW_COUNT):
        assert int(coh_array[index].value) == COH_INVALID, f"warm reset row {index}"


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def read_miss_fills_the_complete_line(dut):
    # reset()
    # write_mem(addr, mem_data)
    # cache_data = read_cache(addr),
    # expect(cache_data == mem_data)
    """One downstream 512-bit read populates every word in the cache line."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    target_addr = line_address(cache_address(tag=2, index=11))
    original = [0x1000 + index for index in range(DATA_PER_LINE)]
    replacement = [0x9000 + index for index in range(DATA_PER_LINE)]
    # Synchronous backdoor preload: the complete line is installed on return.
    tb.ram.write(target_addr, pack_line(original))

    assert await tb.read_word(target_addr + 3 * DATA_BYTES) == original[3]

    # Alter backing memory after the fill; every subsequent word must still hit.
    tb.ram.write(target_addr, pack_line(replacement))
    for word, expected in enumerate(original):
        assert await tb.read_word(target_addr + word * DATA_BYTES) == expected


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def write_miss_fetches_and_merges_the_complete_line(dut):
    """A write miss preserves every untouched word from the LLC line."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    target_addr = line_address(cache_address(tag=1, index=7))
    backing = [0xABC000 + index for index in range(DATA_PER_LINE)]
    value = 0x0123456789ABCDEF
    tb.ram.write(target_addr, pack_line(backing))

    await tb.write_word(target_addr + 5 * DATA_BYTES, value)

    assert unpack_line(tb.ram.read(target_addr, LINE_BYTES)) == backing
    assert await tb.read_word(target_addr + 5 * DATA_BYTES) == value
    assert await tb.read_word(target_addr + 2 * DATA_BYTES) == backing[2]


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def shared_read_hit_upgrades_before_write(dut):
    # assume line_x.coh == S
    # cache0: write_line(line_x, new_data)
    # assert(cache2bus == BusUpgr)
    """A write to a Shared line issues BusUpgr before modifying local data."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    target_addr = line_address(cache_address(tag=3, index=13))
    backing = [0x3300 + index for index in range(DATA_PER_LINE)]
    updated = 0xCAFECAFE12345678
    tb.ram.write(target_addr, pack_line(backing))

    tb.coherence.expect_cache2bus(BUS_RD, target_addr, shared=True)
    assert await tb.read_word(target_addr + DATA_BYTES) == backing[1]
    tb.coherence.expect_cache2bus(BUS_UPGR, target_addr)
    await tb.write_word(target_addr + DATA_BYTES, updated)

    tb.coherence.assert_expectations()
    assert await tb.read_word(target_addr + DATA_BYTES) == updated
    assert unpack_line(tb.ram.read(target_addr, LINE_BYTES)) == backing


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def exclusive_and_modified_hits_do_not_reenter_the_bus(dut):
    # assume cacheline.coh = E/M
    # read_cacheline(addr)
    # assert(snooper does not activate)
    # write_cacheline(addr)
    # assert(snooper does not activate)
    """E/M hits use local BusNOP transitions without a global transaction."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    target_addr = line_address(cache_address(tag=4, index=17))
    backing = [0x4400 + index for index in range(DATA_PER_LINE)]
    first_update = 0x0123456789ABCDEF
    second_update = 0xFEDCBA9876543210
    tb.ram.write(target_addr, pack_line(backing))

    tb.coherence.expect_cache2bus(BUS_RD, target_addr, shared=False)
    assert await tb.read_word(target_addr + DATA_BYTES) == backing[1]
    await tb.write_word(target_addr + DATA_BYTES, first_update)
    assert await tb.read_word(target_addr + DATA_BYTES) == first_update
    await tb.write_word(target_addr + 6 * DATA_BYTES, second_update)
    assert await tb.read_word(target_addr + 6 * DATA_BYTES) == second_update

    tb.coherence.assert_expectations()
    assert unpack_line(tb.ram.read(target_addr, LINE_BYTES)) == backing


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def bus_request_backpressure_and_response_delay_hold_the_transaction(dut):
    # Set snooper into cache2bus mode
    # Set snooper with a high delay
    # check data should not being written to mem/cache before snooper response
    """Hold the bus request, then use the response configuration at acceptance."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    target_addr = line_address(cache_address(tag=6, index=29))
    backing = [0x6600 + index for index in range(DATA_PER_LINE)]
    updated = 0xA5A55A5ADEADBEEF
    tb.ram.write(target_addr, pack_line(backing))

    tb.dut.c2b_accept_enable.value = 0
    tb.coherence.expect_cache2bus(
        BUS_RD, target_addr, shared=True, delay_cycles=12
    )
    read_task = cocotb.start_soon(tb.read_word(target_addr + 3 * DATA_BYTES))

    for _ in range(20):
        await RisingEdge(dut.clk_i)
        if dut.coh_bus_req.req_val.value:
            break
    assert dut.coh_bus_req.req_val.value
    assert int(dut.coh_bus_req.bus_op.value) == BUS_RD
    assert int(dut.coh_bus_req.req_addr.value) == target_addr

    for _ in range(5):
        await RisingEdge(dut.clk_i)
        assert dut.coh_bus_req.req_val.value
        assert int(dut.coh_bus_req.bus_op.value) == BUS_RD
        assert int(dut.coh_bus_req.req_addr.value) == target_addr
        assert int(dut.c2b_req_count_o.value) == 0
        assert not dut.m_axil.arvalid.value
        assert not dut.m_axil.awvalid.value
        assert not dut.upstream.rsp_val.value

    tb.dut.c2b_accept_enable.value = 1
    await RisingEdge(dut.clk_i)
    # Changing the live configuration cannot alter the accepted response.
    tb.coherence.shared = False
    for _ in range(4):
        await RisingEdge(dut.clk_i)
        assert not dut.m_axil.arvalid.value
        assert not dut.m_axil.awvalid.value
        assert not dut.upstream.rsp_val.value
    assert dut.c2b_busy_o.value

    assert await read_task == backing[3]
    tb.coherence.expect_cache2bus(BUS_UPGR, target_addr, delay_cycles=3)
    await tb.write_word(target_addr + 3 * DATA_BYTES, updated)
    assert await tb.read_word(target_addr + 3 * DATA_BYTES) == updated
    tb.coherence.assert_expectations()


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def clean_victim_is_replaced_without_a_writeback(dut):
    # mem.write(cacheline.addr, sentry_value)
    # assume cacheline.coh == S/E
    # read(cacheline.idx , but different tag)
    # assert(mem.read(cacheline.addr) == sentry_value)
    """Replacing an Exclusive line must not overwrite newer LLC contents."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    old_target_addr = line_address(cache_address(tag=2, index=41))
    new_target_addr = line_address(cache_address(tag=7, index=41))
    old_line = [0x2200 + index for index in range(DATA_PER_LINE)]
    newer_llc_line = [0x2F00 + index for index in range(DATA_PER_LINE)]
    new_line = [0x7700 + index for index in range(DATA_PER_LINE)]
    tb.ram.write(old_target_addr, pack_line(old_line))
    tb.ram.write(new_target_addr, pack_line(new_line))

    assert await tb.read_word(old_target_addr + 2 * DATA_BYTES) == old_line[2]
    tb.ram.write(old_target_addr, pack_line(newer_llc_line))

    assert await tb.read_word(new_target_addr + 5 * DATA_BYTES) == new_line[5]
    assert unpack_line(tb.ram.read(old_target_addr, LINE_BYTES)) == newer_llc_line


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def dirty_victim_is_written_back_as_one_line(dut):
    # mem.write(cacheline.addr, sentry_value)
    # assume cacheline.coh == M
    # read(cacheline.idx , but different tag)
    # assert(mem.read(cacheline.addr) != sentry_value)
    # assert(mem.read(cacheline.addr) == cachline.data)
    """Replacing a dirty tag writes all 512 bits before installing the new tag."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    old_target_addr = line_address(cache_address(tag=1, index=19))
    new_target_addr = line_address(cache_address(tag=5, index=19))
    old_backing = [0x1100 + index for index in range(DATA_PER_LINE)]
    new_backing = [0x5500 + index for index in range(DATA_PER_LINE)]
    old_value = 0x1111222233334444
    new_value = 0xAAAABBBBCCCCDDDD
    tb.ram.write(old_target_addr, pack_line(old_backing))
    tb.ram.write(new_target_addr, pack_line(new_backing))

    assert await tb.read_word(old_target_addr + 2 * DATA_BYTES) == old_backing[2]
    await tb.write_word(old_target_addr + 2 * DATA_BYTES, old_value)
    await tb.write_word(new_target_addr + 4 * DATA_BYTES, new_value)

    expected_old = old_backing.copy()
    expected_old[2] = old_value
    assert unpack_line(tb.ram.read(old_target_addr, LINE_BYTES)) == expected_old
    assert unpack_line(tb.ram.read(new_target_addr, LINE_BYTES)) == new_backing
    assert await tb.read_word(new_target_addr + 4 * DATA_BYTES) == new_value

    # Reading the old tag evicts the new dirty line, then reloads the old line.
    assert await tb.read_word(old_target_addr + 2 * DATA_BYTES) == old_value
    expected_new = new_backing.copy()
    expected_new[4] = new_value
    assert unpack_line(tb.ram.read(new_target_addr, LINE_BYTES)) == expected_new


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
        tb.dut.c2b_rsp_delay_cycles.value = rng.randrange(1, 33)
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
            await tb.write_word(address, value)
        else:
            if hit:
                line = resident[1]
            else:
                line = backing[(tag, index)].copy()
                model_cache[index] = (tag, line, False)
            assert await tb.read_word(address) == line[word]

    for (tag, index), expected in backing.items():
        actual = unpack_line(
            tb.ram.read(
                line_address(cache_address(tag, index)),
                LINE_BYTES,
            )
        )
        assert actual == expected


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def upstream_response_and_downstream_axil_backpressure(dut):
    """An eager producer must be blocked by an independent stalled consumer."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    old_target_addr = line_address(cache_address(tag=3, index=23))
    new_target_addr = line_address(cache_address(tag=6, index=23))
    old_line = [0x3000 + index for index in range(DATA_PER_LINE)]
    new_line = [0x6000 + index for index in range(DATA_PER_LINE)]
    tb.ram.write(old_target_addr, pack_line(old_line))
    tb.ram.write(new_target_addr, pack_line(new_line))

    tb.ram.write_if.aw_channel.set_pause_generator(cycle_pause((1,) * 7 + (0,)))
    tb.ram.write_if.w_channel.set_pause_generator(cycle_pause((1,) * 5 + (0,)))
    tb.ram.write_if.b_channel.set_pause_generator(cycle_pause((1, 0)))
    tb.ram.read_if.ar_channel.set_pause_generator(cycle_pause((1,) * 9 + (0,)))
    tb.ram.read_if.r_channel.set_pause_generator(cycle_pause((1, 0, 0)))

    bus = dut.upstream
    channels = {
        "req": (bus.req_val, bus.req_rdy,
                (bus.req_addr, bus.req_data, bus.req_rw_flag)),
        "rsp": (bus.rsp_val, bus.rsp_rdy, (bus.rsp_data,)),
    }
    for name, fields in (
        ("aw", ("awaddr", "awprot")), ("w", ("wdata", "wstrb")),
        ("b", ("bresp",)), ("ar", ("araddr", "arprot")),
        ("r", ("rdata", "rresp")),
    ):
        channels[name] = (
            getattr(dut.m_axil, name + "valid"),
            getattr(dut.m_axil, name + "ready"),
            tuple(getattr(dut.m_axil, field) for field in fields),
        )
    transfers, stalls = {}, {}
    monitor = cocotb.start_soon(
        monitor_handshakes(dut.clk_i, channels, transfers, stalls)
    )
    requests = []
    for iteration in range(6):
        updated = 0xDEADBEEF01234567 + iteration
        # Each conflicting read forces a dirty writeback; the next loop reloads.
        requests.extend((
            (old_target_addr, 0, False, old_line[0]),
            (old_target_addr + DATA_BYTES, updated, True, 0),
            (new_target_addr + 2 * DATA_BYTES, 0, False, new_line[2]),
        ))

    accepted = consumed = 0

    async def produce():
        nonlocal accepted
        for address, data, is_write, _ in requests:
            await tb.master.send_request(address, data, is_write=is_write)
            assert accepted == consumed, "accepted another request before response consumption"
            accepted += 1

    async def consume():
        nonlocal consumed
        for index, (_, _, _, expected) in enumerate(requests):
            # Ready remains low while the producer presents the next request.
            while True:
                await FallingEdge(dut.clk_i)
                if bus.rsp_val.value:
                    break
            if index + 1 < len(requests):
                assert bus.req_val.value, "producer did not present the next request"
                assert not bus.req_rdy.value, "held response must block the next request"
            assert await tb.master.receive_response(response_delay_cycles=4) == expected
            consumed += 1

    producer = cocotb.start_soon(produce())
    consumer = cocotb.start_soon(consume())
    await producer
    await consumer
    for _ in range(3):
        await RisingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    monitor.cancel()
    assert accepted == consumed == len(requests)
    assert transfers == {"req": 18, "rsp": 18, "aw": 6, "w": 6,
                         "b": 6, "ar": 12, "r": 12}
    for channel in ("req", "rsp", "aw", "w", "ar"):
        assert stalls[channel] > 0, f"{channel}: no backpressure was exercised"
    assert stalls["rsp"] == 4 * len(requests)
    expected_old = old_line.copy()
    expected_old[1] = updated
    assert unpack_line(tb.ram.read(old_target_addr, LINE_BYTES)) == expected_old


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def bus_read_snoop_flushes_then_downgrades_a_modified_hit(dut):
    # Fill a line, then modify one word locally so LLC contains stale data.
    # Send remote BusRd and hold its response-ready low for seven cycles.
    # After completion, require the full dirty line in LLC and local state S.
    # A later local read must hit the retained Shared copy without bus traffic.
    """A BusRd hit writes back M data and retains the line in S."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    target_addr = line_address(cache_address(tag=5, index=37))
    backing = [0x5100 + index for index in range(DATA_PER_LINE)]
    updated = 0xA55A0123456789EF
    tb.ram.write(target_addr, pack_line(backing))

    tb.coherence.expect_cache2bus(BUS_RD, target_addr, shared=False)
    assert await tb.read_word(target_addr + 4 * DATA_BYTES) == backing[4]
    await tb.write_word(target_addr + 4 * DATA_BYTES, updated)
    tb.coherence.assert_expectations()

    tb.coherence.select_bus2cache()
    shared = await tb.coherence.send_snoop(
        BUS_RD,
        target_addr,
        response_ready_delay_cycles=7,
    )
    assert shared
    expected = backing.copy()
    expected[4] = updated
    assert unpack_line(tb.ram.read(target_addr, LINE_BYTES)) == expected
    assert int(dut.dut.cache_committer_inst.coh_array[37].value) == COH_SHARED

    # M downgraded to S, so this access must hit without another bus request.
    tb.coherence.select_cache2bus()
    assert await tb.read_word(target_addr + 4 * DATA_BYTES) == updated
    tb.coherence.assert_expectations()


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def bus_upgrade_snoop_invalidates_without_flushing(dut):
    # cacheline.coh = S
    # read_cache(cacheline.data) //hit
    # snooper send in BusUpgr
    # Invalidate without flushing; a later local read refills from LLC (I->E).
    """BusUpgr invalidates a hit without overwriting the LLC line."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    target_addr = line_address(cache_address(tag=7, index=43))
    cached = [0x7100 + index for index in range(DATA_PER_LINE)]
    newer_llc = [0x7F00 + index for index in range(DATA_PER_LINE)]
    tb.ram.write(target_addr, pack_line(cached))

    tb.coherence.expect_cache2bus(BUS_RD, target_addr, shared=True)
    assert await tb.read_word(target_addr + 2 * DATA_BYTES) == cached[2]
    tb.coherence.assert_expectations()
    tb.ram.write(target_addr, pack_line(newer_llc))

    tb.coherence.select_bus2cache()
    assert await tb.coherence.send_snoop(BUS_UPGR, target_addr)
    assert unpack_line(tb.ram.read(target_addr, LINE_BYTES)) == newer_llc

    tb.coherence.select_cache2bus()
    tb.coherence.expect_cache2bus(BUS_RD, target_addr, shared=False)
    assert await tb.read_word(target_addr + 2 * DATA_BYTES) == newer_llc[2]
    tb.coherence.assert_expectations()


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def same_line_snoop_retries_inflight_local_coherence(dut):
    # Start a write to S, then stall its outgoing BusUpgr request.
    # A same-line remote BusUpgr invalidates the resident copy while it waits.
    # Consume/discard the stale local decision and retry from Invalid (BusRdX).
    # Only the re-evaluated decision may complete the write.
    """Discard a local decision invalidated while waiting for the bus."""
    tb = CacheTB(dut)
    tb.coherence.select_cache2bus()
    await tb.reset()
    target_addr = line_address(cache_address(tag=6, index=47))
    backing = [0x6100 + index for index in range(DATA_PER_LINE)]
    updated = 0xC011CA7E5E21A11E
    tb.ram.write(target_addr, pack_line(backing))

    # Install the line in S so the pending local write initially selects
    # BusUpgr, then prevent that request from reaching the pseudo bus.
    tb.coherence.expect_cache2bus(BUS_RD, target_addr, shared=True)
    assert await tb.read_word(target_addr + DATA_BYTES) == backing[1]
    tb.dut.c2b_accept_enable.value = 0
    write_task = cocotb.start_soon(
        tb.write_word(target_addr + DATA_BYTES, updated)
    )

    for _ in range(20):
        await RisingEdge(dut.clk_i)
        if dut.coh_bus_req.req_val.value:
            break
    assert dut.coh_bus_req.req_val.value
    assert int(dut.coh_bus_req.bus_op.value) == BUS_UPGR

    # The hitting snoop invalidates the line while the local decision is in
    # flight. Its response must be consumed later as a stale decision.
    tb.coherence.select_bus2cache()
    assert await tb.coherence.send_snoop(BUS_UPGR, target_addr)

    # Re-evaluation changes BusUpgr to BusRdX. The first result is discarded by
    # the serialization switch; the second result completes the local write.
    tb.coherence.select_cache2bus()
    tb.dut.c2b_accept_enable.value = 1
    tb.coherence.expect_cache2bus(BUS_RDX, target_addr, shared=False)
    tb.coherence.expect_cache2bus(BUS_RDX, target_addr, shared=False)
    await write_task

    assert await tb.read_word(target_addr + DATA_BYTES) == updated
    tb.coherence.assert_expectations()
