import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from dv.cocotb_benches.upstream_if import UpstreamMaster


CLOCK_PERIOD_NS = 10
TEST_TIMEOUT_US = 100
DATA_BYTES = 8
LINE_BYTES = 64
CACHE_SIZE_BYTES = 16 * 1024
MASTER_ADDRESS_OFFSET = 1024 * 1024
ZERO_WORD = bytes(DATA_BYTES)


class CacheDramTB:
    def __init__(self, dut):
        self.dut = dut
        cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())

        self.cpus = []
        for interface_name in (
            "upstream_cache_if_inst0",
            "upstream_cache_if_inst1",
        ):
            upstream = getattr(dut.main_module_inst, interface_name)
            self.cpus.append(UpstreamMaster(upstream, dut.clk_i))

    async def reset(self):
        self.dut.rxd_i.value = 1
        self.dut.rst_ni.value = 0
        for _ in range(10):
            await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        for _ in range(2):
            await RisingEdge(self.dut.clk_i)

    async def read_word(self, cache_index, address):
        assert address % DATA_BYTES == 0
        response = await self.cpus[cache_index].read(address)
        return response.to_bytes(DATA_BYTES, "little")

    async def write_word(self, cache_index, address, data):
        assert address % DATA_BYTES == 0
        assert len(data) == DATA_BYTES
        response = await self.cpus[cache_index].write(
            address, int.from_bytes(data, "little")
        )
        assert response == 0


def word(value):
    return value.to_bytes(DATA_BYTES, "little")


def conflicting_address(address, tag_offset=1):
    """Return another address mapping to the same direct-mapped cache row."""
    return address + tag_offset * CACHE_SIZE_BYTES


def private_address(cache_index, address):
    """Give repeated per-cache scenarios disjoint DRAM backing addresses."""
    return address + cache_index * MASTER_ADDRESS_OFFSET


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
    """A cold read from either cache traverses the interconnect and DRAM."""
    tb = CacheDramTB(dut)
    await tb.reset()

    for cache_index in range(2):
        address = private_address(cache_index, 0x1000)
        assert await tb.read_word(cache_index, address) == ZERO_WORD


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def single_write_completes(dut):
    """A lone write-miss on either cache receives an AXI OKAY response."""
    tb = CacheDramTB(dut)
    await tb.reset()

    for cache_index in range(2):
        address = private_address(cache_index, 0x2000)
        await tb.write_word(cache_index, address, word(0x0123456789ABCDEF))


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def write_followed_by_read_hits(dut):
    """Each cache returns its own data on a write-followed-by-read hit."""
    tb = CacheDramTB(dut)
    await tb.reset()

    for cache_index in range(2):
        address = private_address(cache_index, 0x3000)
        payload = word(0xDEADBEEFCAFEBABE + cache_index)
        await tb.write_word(cache_index, address, payload)
        assert await tb.read_word(cache_index, address) == payload


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def read_miss_fills_complete_line(dut):
    """A cold read fills a complete zeroed line in each cache."""
    tb = CacheDramTB(dut)
    await tb.reset()

    for cache_index in range(2):
        line_address = private_address(cache_index, 0x5000)
        for word_index in range(LINE_BYTES // DATA_BYTES):
            assert await tb.read_word(
                cache_index, line_address + word_index * DATA_BYTES
            ) == ZERO_WORD


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def write_miss_allocates_without_dram_read(dut):
    """Each cache write-miss zero-allocates and changes only its target word."""
    tb = CacheDramTB(dut)
    await tb.reset()
    target_index = 5

    for cache_index in range(2):
        line_address = private_address(cache_index, 0x7000)
        payload = word(0xA5A55A5AF00D1234 + cache_index)
        await tb.write_word(
            cache_index, line_address + target_index * DATA_BYTES, payload
        )

        for word_index in range(LINE_BYTES // DATA_BYTES):
            expected = payload if word_index == target_index else ZERO_WORD
            assert await tb.read_word(
                cache_index, line_address + word_index * DATA_BYTES
            ) == expected


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def dirty_write_eviction_round_trips_through_dram(dut):
    """Both caches can evict a dirty full line and fetch it back through DRAM."""
    tb = CacheDramTB(dut)
    await tb.reset()

    for cache_index in range(2):
        first_line = private_address(cache_index, 0x9000)
        second_line = conflicting_address(first_line)
        first_values = [
            word(0x1000 + cache_index * 0x100 + index) for index in range(8)
        ]
        second_value = word(0xFEEDFACE12345678 + cache_index)

        for index, payload in enumerate(first_values):
            await tb.write_word(
                cache_index, first_line + index * DATA_BYTES, payload
            )

        # This write misses in the same row, forcing the first dirty line to DRAM.
        await tb.write_word(
            cache_index, second_line + 3 * DATA_BYTES, second_value
        )
        assert await tb.read_word(
            cache_index, second_line + 3 * DATA_BYTES
        ) == second_value

        # Fetching the first line evicts the second and verifies full-line data.
        for index, payload in enumerate(first_values):
            assert await tb.read_word(
                cache_index, first_line + index * DATA_BYTES
            ) == payload

        # The second dirty line was also written back while the first was fetched.
        assert await tb.read_word(
            cache_index, second_line + 3 * DATA_BYTES
        ) == second_value


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def randomized_conflicting_evictions_preserve_data(dut):
    """Both caches agree with independent models during same-index evictions."""
    tb = CacheDramTB(dut)
    await tb.reset()
    rng = random.Random(0xCA4ED24A)

    for cache_index in range(2):
        base_line = private_address(cache_index, 0xB000)
        model = SameRowCacheModel()
        touched_addresses = set()

        for _ in range(80):
            tag = rng.randrange(4)
            word_index = rng.randrange(8)
            address = conflicting_address(base_line, tag) + word_index * DATA_BYTES
            touched_addresses.add(address)

            if rng.randrange(3):
                payload = rng.randbytes(DATA_BYTES)
                await tb.write_word(cache_index, address, payload)
                model.write(address, payload)
            else:
                expected = model.read(address)
                assert await tb.read_word(cache_index, address) == expected

        for address in sorted(touched_addresses):
            expected = model.read(address)
            assert await tb.read_word(cache_index, address) == expected


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def simultaneous_evictions_share_the_dram_port(dut):
    """Concurrent dirty evictions from both caches are serialized correctly."""
    tb = CacheDramTB(dut)
    await tb.reset()
    first_lines = [0x200000, 0x300000]
    first_values = [word(0xCACE0000), word(0xCACE0001)]
    second_values = [word(0xE71C7000), word(0xE71C7001)]

    for cache_index in range(2):
        await tb.write_word(
            cache_index, first_lines[cache_index], first_values[cache_index]
        )

    evictions = [
        cocotb.start_soon(
            tb.write_word(
                cache_index,
                conflicting_address(first_lines[cache_index]),
                second_values[cache_index],
            )
        )
        for cache_index in range(2)
    ]
    for eviction in evictions:
        await eviction

    refills = [
        cocotb.start_soon(tb.read_word(cache_index, first_lines[cache_index]))
        for cache_index in range(2)
    ]
    for cache_index, refill in enumerate(refills):
        assert await refill == first_values[cache_index]


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def caches_keep_independent_noncoherent_state(dut):
    """A cache retains stale local data until its own line is replaced."""
    tb = CacheDramTB(dut)
    await tb.reset()
    address = 0x400000
    conflict = conflicting_address(address)
    payload = word(0x1C0CA1CA5E000001)

    await tb.write_word(0, address, payload)
    assert await tb.read_word(1, address) == ZERO_WORD

    # Cache 0 writes its dirty line to DRAM, but cache 1 has no invalidation path.
    await tb.write_word(0, conflict, word(0x1C0CA1CA5E000002))
    assert await tb.read_word(1, address) == ZERO_WORD

    # Once cache 1 replaces the stale line, its next miss observes DRAM.
    assert await tb.read_word(1, conflict) == ZERO_WORD
    assert await tb.read_word(1, address) == payload
