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


class CoherenceBusResponder:
    """Single-outstanding responder for the cache-local coherence interface."""

    def __init__(self, dut):
        self.dut = dut
        self.shared = False
        self.requests = []
        dut.coh_bus_req_rdy_i.value = 1
        dut.coh_bus_rsp_val_i.value = 0
        dut.coh_bus_shared_i.value = 0
        cocotb.start_soon(self._run())

    async def _run(self):
        while True:
            await RisingEdge(self.dut.clk_i)

            if not self.dut.rst_ni.value:
                self.dut.coh_bus_req_rdy_i.value = 1
                self.dut.coh_bus_rsp_val_i.value = 0
                self.dut.coh_bus_shared_i.value = 0
                continue

            response_accepted = (
                self.dut.coh_bus_rsp_val_i.value
                and self.dut.coh_bus_rsp_rdy_o.value
            )
            request_accepted = (
                self.dut.coh_bus_req_val_o.value
                and self.dut.coh_bus_req_rdy_i.value
            )

            if response_accepted:
                self.dut.coh_bus_rsp_val_i.value = 0
                self.dut.coh_bus_req_rdy_i.value = 1

            if request_accepted:
                self.requests.append(
                    (
                        int(self.dut.coh_bus_req_op_o.value),
                        int(self.dut.coh_bus_req_addr_o.value),
                    )
                )
                self.dut.coh_bus_req_rdy_i.value = 0
                self.dut.coh_bus_shared_i.value = int(self.shared)
                self.dut.coh_bus_rsp_val_i.value = 1


class CacheTB:
    def __init__(self, dut):
        self.dut = dut
        cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())

        self.master = UpstreamMaster(dut.upstream, dut.clk_i)
        self.coherence = CoherenceBusResponder(dut)
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
    await tb.reset()

    for index in range(ROW_COUNT):
        assert await tb.read_word(cache_address(tag=0, index=index)) == 0


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def read_miss_fills_the_complete_line(dut):
    """One downstream 512-bit read populates every word in the cache line."""
    tb = CacheTB(dut)
    await tb.reset()
    base = line_address(cache_address(tag=2, index=11))
    original = [0x1000 + index for index in range(DATA_PER_LINE)]
    replacement = [0x9000 + index for index in range(DATA_PER_LINE)]
    tb.ram.write(base, pack_line(original))

    assert await tb.read_word(base + 3 * DATA_BYTES) == original[3]
    assert tb.coherence.requests == [(BUS_RD, base)]

    # Alter backing memory after the fill; every subsequent word must still hit.
    tb.ram.write(base, pack_line(replacement))
    for word, expected in enumerate(original):
        assert await tb.read_word(base + word * DATA_BYTES) == expected
    assert tb.coherence.requests == [(BUS_RD, base)]


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def write_miss_allocates_without_downstream_access(dut):
    """A write miss obtains ownership without reading or updating memory."""
    tb = CacheTB(dut)
    await tb.reset()
    base = line_address(cache_address(tag=1, index=7))
    backing = [0xABC000 + index for index in range(DATA_PER_LINE)]
    value = 0x0123456789ABCDEF
    tb.ram.write(base, pack_line(backing))

    await tb.write_word(base + 5 * DATA_BYTES, value)

    assert tb.coherence.requests == [(BUS_RDX, base)]
    assert unpack_line(tb.ram.read(base, LINE_BYTES)) == backing
    assert await tb.read_word(base + 5 * DATA_BYTES) == value
    assert await tb.read_word(base + 2 * DATA_BYTES) == 0


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def shared_read_hit_upgrades_before_write(dut):
    """A write to a Shared line issues BusUpgr before modifying local data."""
    tb = CacheTB(dut)
    await tb.reset()
    base = line_address(cache_address(tag=3, index=13))
    backing = [0x3300 + index for index in range(DATA_PER_LINE)]
    updated = 0xCAFECAFE12345678
    tb.ram.write(base, pack_line(backing))

    tb.coherence.shared = True
    assert await tb.read_word(base + DATA_BYTES) == backing[1]
    await tb.write_word(base + DATA_BYTES, updated)

    assert tb.coherence.requests == [(BUS_RD, base), (BUS_UPGR, base)]
    assert await tb.read_word(base + DATA_BYTES) == updated
    assert unpack_line(tb.ram.read(base, LINE_BYTES)) == backing


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def dirty_victim_is_written_back_as_one_line(dut):
    """Replacing a dirty tag writes all 512 bits before installing the new tag."""
    tb = CacheTB(dut)
    await tb.reset()
    old_base = line_address(cache_address(tag=1, index=19))
    new_base = line_address(cache_address(tag=5, index=19))
    old_backing = [0x1100 + index for index in range(DATA_PER_LINE)]
    new_backing = [0x5500 + index for index in range(DATA_PER_LINE)]
    old_value = 0x1111222233334444
    new_value = 0xAAAABBBBCCCCDDDD
    tb.ram.write(old_base, pack_line(old_backing))
    tb.ram.write(new_base, pack_line(new_backing))

    assert await tb.read_word(old_base + 2 * DATA_BYTES) == old_backing[2]
    await tb.write_word(old_base + 2 * DATA_BYTES, old_value)
    await tb.write_word(new_base + 4 * DATA_BYTES, new_value)

    expected_old = old_backing.copy()
    expected_old[2] = old_value
    assert unpack_line(tb.ram.read(old_base, LINE_BYTES)) == expected_old
    assert unpack_line(tb.ram.read(new_base, LINE_BYTES)) == new_backing
    assert await tb.read_word(new_base + 4 * DATA_BYTES) == new_value

    # Reading the old tag evicts the new dirty line, then reloads the old line.
    assert await tb.read_word(old_base + 2 * DATA_BYTES) == old_value
    expected_new = [0] * DATA_PER_LINE
    expected_new[4] = new_value
    assert unpack_line(tb.ram.read(new_base, LINE_BYTES)) == expected_new


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def randomized_write_back_model(dut):
    """Compare mixed traffic against a direct-mapped write-back software model."""
    tb = CacheTB(dut)
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
            line = resident[1].copy() if hit else [0] * DATA_PER_LINE
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
    """Hold the synchronized response and stall downstream AXI-Lite channels."""
    tb = CacheTB(dut)
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

    assert await tb.read_word(old_base, response_delay_cycles=4) == old_line[0]
    updated = 0xDEADBEEF01234567
    await tb.write_word(
        old_base + DATA_BYTES, updated, response_delay_cycles=3
    )

    # This conflicting read forces an independently handshaken dirty eviction.
    assert await tb.read_word(new_base + 2 * DATA_BYTES) == new_line[2]
    expected_old = old_line.copy()
    expected_old[1] = updated
    assert unpack_line(tb.ram.read(old_base, LINE_BYTES)) == expected_old
