import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotbext.axi import AxiLiteBus, AxiLiteMaster, AxiResp


CLOCK_PERIOD_NS = 10
TEST_TIMEOUT_US = 100
DATA_BYTES = 8
LINE_BYTES = 64
CACHE_SIZE_BYTES = 16 * 1024
ZERO_WORD = bytes(DATA_BYTES)


class CacheDramTB:
    def __init__(self, dut):
        self.dut = dut
        cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())

        cpu_axil = dut.main_module_inst.upstream_cache_axil_inst
        self.cpu = AxiLiteMaster(
            AxiLiteBus.from_entity(cpu_axil),
            dut.clk_i,
            dut.rst_ni,
            reset_active_level=False,
        )

    async def reset(self):
        self.dut.rxd_i.value = 1
        self.dut.rst_ni.value = 0
        for _ in range(10):
            await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        for _ in range(2):
            await RisingEdge(self.dut.clk_i)

    async def read_word(self, address):
        assert address % DATA_BYTES == 0
        response = await self.cpu.read(address, DATA_BYTES)
        assert response.resp == AxiResp.OKAY
        assert len(response.data) == DATA_BYTES
        return bytes(response.data)

    async def write_word(self, address, data):
        assert address % DATA_BYTES == 0
        assert len(data) == DATA_BYTES
        response = await self.cpu.write(address, data)
        assert response.resp == AxiResp.OKAY


def word(value):
    return value.to_bytes(DATA_BYTES, "little")


def conflicting_address(address, tag_offset=1):
    """Return another address mapping to the same direct-mapped cache row."""
    return address + tag_offset * CACHE_SIZE_BYTES


class SameRowCacheModel:
    """Reference one cache row with the RTL's no-read write-miss policy."""

    def __init__(self):
        self.backing_lines = {}
        self.resident_address = None
        self.resident_data = bytearray(LINE_BYTES)
        self.resident_dirty = False

    @staticmethod
    def line_address(address):
        return address & ~(LINE_BYTES - 1)

    def replace(self, line_address, fetch_from_dram):
        if self.resident_address is not None and self.resident_dirty:
            self.backing_lines[self.resident_address] = bytes(self.resident_data)

        self.resident_address = line_address
        self.resident_data = bytearray(
            self.backing_lines.get(line_address, bytes(LINE_BYTES))
            if fetch_from_dram
            else bytes(LINE_BYTES)
        )
        self.resident_dirty = False

    def read(self, address):
        line_address = self.line_address(address)
        if self.resident_address != line_address:
            self.replace(line_address, fetch_from_dram=True)

        offset = address - line_address
        return bytes(self.resident_data[offset:offset + DATA_BYTES])

    def write(self, address, data):
        line_address = self.line_address(address)
        if self.resident_address != line_address:
            # The RTL write-miss policy allocates zero without reading DRAM.
            self.replace(line_address, fetch_from_dram=False)

        offset = address - line_address
        self.resident_data[offset:offset + DATA_BYTES] = data
        self.resident_dirty = True


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def single_read_returns_zero(dut):
    """A single cold read traverses cache and DRAM and returns zero."""
    tb = CacheDramTB(dut)
    await tb.reset()

    assert await tb.read_word(0x1000) == ZERO_WORD


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def single_write_completes(dut):
    """A lone write-miss receives an AXI OKAY response."""
    tb = CacheDramTB(dut)
    await tb.reset()

    await tb.write_word(0x2000, word(0x0123456789ABCDEF))


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def write_followed_by_read_hits(dut):
    """A write followed by a read of the same word returns cached data."""
    tb = CacheDramTB(dut)
    await tb.reset()
    address = 0x3000
    payload = word(0xDEADBEEFCAFEBABE)

    await tb.write_word(address, payload)
    assert await tb.read_word(address) == payload


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def read_miss_fills_complete_line(dut):
    """A cold read fills a complete zeroed cacheline from DRAM."""
    tb = CacheDramTB(dut)
    await tb.reset()
    line_address = 0x5000

    for word_index in range(LINE_BYTES // DATA_BYTES):
        assert await tb.read_word(
            line_address + word_index * DATA_BYTES
        ) == ZERO_WORD


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def write_miss_allocates_without_dram_read(dut):
    """A write miss allocates a zeroed line and modifies only its target word."""
    tb = CacheDramTB(dut)
    await tb.reset()
    line_address = 0x7000
    target_index = 5
    payload = word(0xA5A55A5AF00D1234)

    await tb.write_word(line_address + target_index * DATA_BYTES, payload)

    for word_index in range(LINE_BYTES // DATA_BYTES):
        expected = payload if word_index == target_index else ZERO_WORD
        assert await tb.read_word(
            line_address + word_index * DATA_BYTES
        ) == expected


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def dirty_write_eviction_round_trips_through_dram(dut):
    """A conflicting write evicts a dirty full line and it can be fetched back."""
    tb = CacheDramTB(dut)
    await tb.reset()
    first_line = 0x9000
    second_line = conflicting_address(first_line)
    first_values = [word(0x1000 + index) for index in range(8)]
    second_value = word(0xFEEDFACE12345678)

    for index, payload in enumerate(first_values):
        await tb.write_word(first_line + index * DATA_BYTES, payload)

    # This write misses in the same row, forcing the first dirty line to DRAM.
    await tb.write_word(second_line + 3 * DATA_BYTES, second_value)
    assert await tb.read_word(second_line + 3 * DATA_BYTES) == second_value

    # Fetching the first line evicts the second line and verifies full-line data.
    for index, payload in enumerate(first_values):
        assert await tb.read_word(first_line + index * DATA_BYTES) == payload

    # The second dirty line was also written back while the first was fetched.
    assert await tb.read_word(second_line + 3 * DATA_BYTES) == second_value


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def randomized_conflicting_evictions_preserve_data(dut):
    """Repeated same-index evictions agree with a software memory model."""
    tb = CacheDramTB(dut)
    await tb.reset()
    rng = random.Random(0xCA4ED24A)
    base_line = 0xB000
    model = SameRowCacheModel()
    touched_addresses = set()

    for _ in range(80):
        tag = rng.randrange(4)
        word_index = rng.randrange(8)
        address = conflicting_address(base_line, tag) + word_index * DATA_BYTES
        touched_addresses.add(address)

        if rng.randrange(3):
            payload = rng.randbytes(DATA_BYTES)
            await tb.write_word(address, payload)
            model.write(address, payload)
        else:
            expected = model.read(address)
            assert await tb.read_word(address) == expected

    for address in sorted(touched_addresses):
        expected = model.read(address)
        assert await tb.read_word(address) == expected
