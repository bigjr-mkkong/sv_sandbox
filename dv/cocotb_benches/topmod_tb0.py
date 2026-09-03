import random
from dataclasses import dataclass

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from dv.cocotb_benches.upstream_if import UpstreamMaster


CLOCK_PERIOD_NS = 10
TEST_TIMEOUT_US = 100
SWEEP_TIMEOUT_MS = 10
SWEEP_MAX_DELAY_CYCLES = 300
DATA_BYTES = 8
LINE_BYTES = 64
CACHE_SIZE_BYTES = 16 * 1024
CACHE_ROW_COUNT = CACHE_SIZE_BYTES // LINE_BYTES
CACHE_INDEX_WIDTH = (CACHE_ROW_COUNT - 1).bit_length()
CACHE_OFFSET_WIDTH = (LINE_BYTES - 1).bit_length()
CACHE_TAG_WIDTH = 64 - CACHE_INDEX_WIDTH - CACHE_OFFSET_WIDTH
MASTER_ADDRESS_OFFSET = 1024 * 1024
ZERO_WORD = bytes(DATA_BYTES)
ZERO_LINE = bytes(LINE_BYTES)

COH_MODIFIED = 0
COH_EXCLUSIVE = 1
COH_SHARED = 2
COH_INVALID = 3


@dataclass(frozen=True)
class CacheRequest:
    address: int
    is_write: bool
    data: bytes = ZERO_WORD


@dataclass(frozen=True)
class CacheResponse:
    data: bytes
    ok: bool = True


@dataclass(frozen=True)
class CacheLineSnapshot:
    state: int
    tag: int
    data: bytes


class CacheDramTB:
    def __init__(self, dut):
        self.dut = dut
        cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())

        self.cpus = []
        self.cache_instances = []
        for interface_name in (
            "upstream_cache_if_inst0",
            "upstream_cache_if_inst1",
        ):
            upstream = getattr(dut.main_module_inst, interface_name)
            self.cpus.append(UpstreamMaster(upstream, dut.clk_i))
        for instance_name in (
            "simple_cache_1rw_inst0",
            "simple_cache_1rw_inst1",
        ):
            self.cache_instances.append(
                getattr(dut.main_module_inst, instance_name)
            )

        self.pending_requests = [None] * len(self.cpus)

    async def reset(self):
        # self.dut.rxd_i.value = 1
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

    async def submit_req(self, cache_index, request):
        """Assert request valid first and hold it through acceptance."""
        assert self.pending_requests[cache_index] is None
        assert request.address % DATA_BYTES == 0
        assert len(request.data) == DATA_BYTES
        bus = self.cpus[cache_index].bus

        bus.req_addr.value = request.address
        bus.req_data.value = int.from_bytes(request.data, "little")
        bus.req_rw_flag.value = int(request.is_write)
        bus.req_val.value = 1

        while True:
            await RisingEdge(self.dut.clk_i)
            if bus.req_rdy.value:
                break

        bus.req_val.value = 0
        bus.req_addr.value = 0
        bus.req_data.value = 0
        bus.req_rw_flag.value = 0
        self.pending_requests[cache_index] = request

    async def read_rsp(self, cache_index):
        """Assert response ready first, then capture a completed response."""
        bus = self.cpus[cache_index].bus
        bus.rsp_rdy.value = 1

        while True:
            await RisingEdge(self.dut.clk_i)
            if bus.rsp_val.value:
                response = CacheResponse(
                    data=int(bus.rsp_data.value).to_bytes(DATA_BYTES, "little")
                )
                break

        bus.rsp_rdy.value = 0
        return response

    async def wait_rsp(self, cache_index, request):
        """Consume the response belonging to a previously submitted request."""
        assert self.pending_requests[cache_index] == request
        response = await self.read_rsp(cache_index)
        self.pending_requests[cache_index] = None
        assert response.ok
        if request.is_write:
            assert response.data == ZERO_WORD
        return response

    async def run_requests(self, requests):
        """Submit one request per cache concurrently and collect both replies."""
        assert len(requests) == len(self.cpus)
        submitters = [
            cocotb.start_soon(self.submit_req(cache_index, request))
            for cache_index, request in enumerate(requests)
        ]
        for submitter in submitters:
            await submitter

        waiters = [
            cocotb.start_soon(self.wait_rsp(cache_index, request))
            for cache_index, request in enumerate(requests)
        ]
        return [await waiter for waiter in waiters]

    async def run_request(self, cache_index, request):
        await self.submit_req(cache_index, request)
        return await self.wait_rsp(cache_index, request)

    def cache_line(self, cache_index, address):
        """Decode one internal packed cache entry without changing DUT state."""
        row_index = (address >> CACHE_OFFSET_WIDTH) % CACHE_ROW_COUNT
        entry = (
            self.cache_instances[cache_index]
            .cache_committer_inst.cache[row_index]
        )
        raw_entry = int(entry.value)
        line_data_mask = (1 << (LINE_BYTES * 8)) - 1
        tag_mask = (1 << CACHE_TAG_WIDTH) - 1

        return CacheLineSnapshot(
            state=(raw_entry >> (LINE_BYTES * 8 + CACHE_TAG_WIDTH)) & 0b11,
            tag=(raw_entry >> (LINE_BYTES * 8)) & tag_mask,
            data=(raw_entry & line_data_mask).to_bytes(LINE_BYTES, "little"),
        )


def word(value):
    return value.to_bytes(DATA_BYTES, "little")


def line_with_words(*updates):
    data = bytearray(LINE_BYTES)
    for word_index, payload in updates:
        assert 0 <= word_index < LINE_BYTES // DATA_BYTES
        assert len(payload) == DATA_BYTES
        offset = word_index * DATA_BYTES
        data[offset:offset + DATA_BYTES] = payload
    return bytes(data)


def assert_cache_line(tb, cache_index, address, state, data):
    snapshot = tb.cache_line(cache_index, address)
    expected_tag = address >> (CACHE_OFFSET_WIDTH + CACHE_INDEX_WIDTH)
    assert snapshot.state == state, (
        f"cache={cache_index} address={address:#x} "
        f"state={snapshot.state} expected={state}"
    )
    assert snapshot.tag == expected_tag, (
        f"cache={cache_index} address={address:#x} "
        f"tag={snapshot.tag:#x} expected={expected_tag:#x}"
    )
    assert snapshot.data == data, (
        f"cache={cache_index} address={address:#x} "
        f"data={snapshot.data.hex()} expected={data.hex()}"
    )


def conflicting_address(address, tag_offset=1):
    """Return another address mapping to the same direct-mapped cache row."""
    return address + tag_offset * CACHE_SIZE_BYTES


def private_address(cache_index, address):
    """Give repeated per-cache scenarios disjoint DRAM backing addresses."""
    return address + cache_index * MASTER_ADDRESS_OFFSET


class SameRowCacheModel:
    """Reference one row of a write-back, write-allocate cache."""

    def __init__(self):
        self.backing_lines = {}
        self.resident_address = None
        self.resident_data = bytearray(LINE_BYTES)
        self.resident_dirty = False

    @staticmethod
    def line_address(address):
        return address & ~(LINE_BYTES - 1)

    def replace(self, line_address):
        if self.resident_address is not None and self.resident_dirty:
            self.backing_lines[self.resident_address] = bytes(self.resident_data)

        self.resident_address = line_address
        self.resident_data = bytearray(
            self.backing_lines.get(line_address, bytes(LINE_BYTES))
        )
        self.resident_dirty = False

    def read(self, address):
        line_address = self.line_address(address)
        if self.resident_address != line_address:
            self.replace(line_address)

        offset = address - line_address
        return bytes(self.resident_data[offset:offset + DATA_BYTES])

    def write(self, address, data):
        line_address = self.line_address(address)
        if self.resident_address != line_address:
            self.replace(line_address)

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
async def write_miss_merges_with_a_zeroed_dram_line(dut):
    """Each cache write-miss fetches the line and changes its target word."""
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
                actual = await tb.read_word(cache_index, address)
                assert actual == expected, (
                    f"cache={cache_index} address={address:#x} "
                    f"actual={actual.hex()} expected={expected.hex()}"
                )

        for address in sorted(touched_addresses):
            expected = model.read(address)
            actual = await tb.read_word(cache_index, address)
            assert actual == expected, (
                f"cache={cache_index} address={address:#x} "
                f"actual={actual.hex()} expected={expected.hex()}"
            )


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
async def snoops_transfer_the_latest_data_between_caches(dut):
    """Remote reads flush modified data and leave both caches shared."""
    tb = CacheDramTB(dut)
    await tb.reset()
    address = 0x400000
    first_payload = word(0x1C0CA1CA5E000001)
    second_payload = word(0x1C0CA1CA5E000002)

    await tb.write_word(0, address, first_payload)
    assert await tb.read_word(1, address) == first_payload

    await tb.write_word(1, address, second_payload)
    assert await tb.read_word(1, address) == second_payload

    assert await tb.read_word(0, address) == second_payload


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def e2e_simultaneous_read_read(dut):
    """Concurrent cold reads finish with two Shared zero-filled copies."""
    tb = CacheDramTB(dut)
    await tb.reset()
    base = 0x500000
    requests = [
        CacheRequest(base + DATA_BYTES, is_write=False),
        CacheRequest(base + 6 * DATA_BYTES, is_write=False),
    ]

    responses = await tb.run_requests(requests)

    assert responses[0].data == ZERO_WORD
    assert responses[1].data == ZERO_WORD
    assert_cache_line(tb, 0, base, COH_SHARED, ZERO_LINE)
    assert_cache_line(tb, 1, base, COH_SHARED, ZERO_LINE)


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def e2e_simultaneous_read_write(dut):
    """Concurrent read/write accepts either legal serialized final ordering."""
    tb = CacheDramTB(dut)
    await tb.reset()
    base = 0x510000
    write_payload = word(0x5100000000000005)
    expected_line = line_with_words((5, write_payload))
    requests = [
        CacheRequest(base + DATA_BYTES, is_write=False),
        CacheRequest(
            base + 5 * DATA_BYTES,
            is_write=True,
            data=write_payload,
        ),
    ]

    responses = await tb.run_requests(requests)
    snapshots = [tb.cache_line(cache_index, base) for cache_index in range(2)]
    states = tuple(snapshot.state for snapshot in snapshots)

    assert responses[0].data == ZERO_WORD
    if states == (COH_INVALID, COH_MODIFIED):
        assert_cache_line(tb, 0, base, COH_INVALID, ZERO_LINE)
        assert_cache_line(tb, 1, base, COH_MODIFIED, expected_line)
    elif states == (COH_SHARED, COH_SHARED):
        assert_cache_line(tb, 0, base, COH_SHARED, expected_line)
        assert_cache_line(tb, 1, base, COH_SHARED, expected_line)
    else:
        raise AssertionError(
            f"illegal simultaneous read/write final states: {states}"
        )


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def e2e_simultaneous_write_write(dut):
    """Concurrent writes preserve both words in the final Modified owner."""
    tb = CacheDramTB(dut)
    await tb.reset()
    base = 0x520000
    payloads = [word(0x5200000000000002), word(0x5200000000000005)]
    expected_line = line_with_words((2, payloads[0]), (5, payloads[1]))
    requests = [
        CacheRequest(
            base + 2 * DATA_BYTES,
            is_write=True,
            data=payloads[0],
        ),
        CacheRequest(
            base + 5 * DATA_BYTES,
            is_write=True,
            data=payloads[1],
        ),
    ]

    await tb.run_requests(requests)
    snapshots = [tb.cache_line(cache_index, base) for cache_index in range(2)]
    states = tuple(snapshot.state for snapshot in snapshots)

    assert states in {
        (COH_INVALID, COH_MODIFIED),
        (COH_MODIFIED, COH_INVALID),
    }, f"illegal simultaneous write/write final states: {states}"
    owner = states.index(COH_MODIFIED)
    assert_cache_line(tb, owner, base, COH_MODIFIED, expected_line)


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def e2e_read_then_read(dut):
    """A later reader downgrades the first Exclusive copy to Shared."""
    tb = CacheDramTB(dut)
    await tb.reset()
    base = 0x530000
    first = CacheRequest(base + DATA_BYTES, is_write=False)
    second = CacheRequest(base + 6 * DATA_BYTES, is_write=False)

    assert (await tb.run_request(0, first)).data == ZERO_WORD
    assert (await tb.run_request(1, second)).data == ZERO_WORD

    assert_cache_line(tb, 0, base, COH_SHARED, ZERO_LINE)
    assert_cache_line(tb, 1, base, COH_SHARED, ZERO_LINE)


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def e2e_read_then_write(dut):
    """A later writer invalidates the first reader and becomes Modified."""
    tb = CacheDramTB(dut)
    await tb.reset()
    base = 0x540000
    payload = word(0x5400000000000005)
    expected_line = line_with_words((5, payload))
    first = CacheRequest(base + DATA_BYTES, is_write=False)
    second = CacheRequest(
        base + 5 * DATA_BYTES,
        is_write=True,
        data=payload,
    )

    assert (await tb.run_request(0, first)).data == ZERO_WORD
    await tb.run_request(1, second)

    assert_cache_line(tb, 0, base, COH_INVALID, ZERO_LINE)
    assert_cache_line(tb, 1, base, COH_MODIFIED, expected_line)


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def e2e_write_then_read(dut):
    """A later reader receives written data and leaves both copies Shared."""
    tb = CacheDramTB(dut)
    await tb.reset()
    base = 0x550000
    payload = word(0x5500000000000002)
    expected_line = line_with_words((2, payload))
    first = CacheRequest(
        base + 2 * DATA_BYTES,
        is_write=True,
        data=payload,
    )
    second = CacheRequest(base + 6 * DATA_BYTES, is_write=False)

    await tb.run_request(0, first)
    assert (await tb.run_request(1, second)).data == ZERO_WORD

    assert_cache_line(tb, 0, base, COH_SHARED, expected_line)
    assert_cache_line(tb, 1, base, COH_SHARED, expected_line)


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def e2e_write_then_write(dut):
    """A later writer preserves the first word and becomes Modified."""
    tb = CacheDramTB(dut)
    await tb.reset()
    base = 0x560000
    payloads = [word(0x5600000000000002), word(0x5600000000000005)]
    first_line = line_with_words((2, payloads[0]))
    final_line = line_with_words((2, payloads[0]), (5, payloads[1]))
    first = CacheRequest(
        base + 2 * DATA_BYTES,
        is_write=True,
        data=payloads[0],
    )
    second = CacheRequest(
        base + 5 * DATA_BYTES,
        is_write=True,
        data=payloads[1],
    )

    await tb.run_request(0, first)
    await tb.run_request(1, second)

    assert_cache_line(tb, 0, base, COH_INVALID, first_line)
    assert_cache_line(tb, 1, base, COH_MODIFIED, final_line)


@cocotb.test(timeout_time=SWEEP_TIMEOUT_MS, timeout_unit="ms")
async def e2e_request_offset_sweep(dut):
    """Preserve ordered results for request offsets from 1 through 300 cycles."""
    tb = CacheDramTB(dut)
    scenarios = (
        ("read/read", False, False),
        ("read/write", False, True),
        ("write/read", True, False),
        ("write/write", True, True),
    )

    for scenario_index, (name, first_is_write, second_is_write) in enumerate(
        scenarios
    ):
        base = 0x600000 + scenario_index * 0x10000
        first_payload = word(0x6000000000000002 + scenario_index * 0x100)
        second_payload = word(0x6000000000000005 + scenario_index * 0x100)
        first_line = line_with_words((2, first_payload))
        final_line = line_with_words(
            *((2, first_payload),) if first_is_write else (),
            *((5, second_payload),) if second_is_write else (),
        )

        for delay_cycles in range(1, SWEEP_MAX_DELAY_CYCLES + 1):
            await tb.reset()
            requests = (
                CacheRequest(
                    base + (2 if first_is_write else 1) * DATA_BYTES,
                    is_write=first_is_write,
                    data=first_payload if first_is_write else ZERO_WORD,
                ),
                CacheRequest(
                    base + (5 if second_is_write else 6) * DATA_BYTES,
                    is_write=second_is_write,
                    data=second_payload if second_is_write else ZERO_WORD,
                ),
            )

            first_task = cocotb.start_soon(tb.run_request(0, requests[0]))
            for _ in range(delay_cycles):
                await RisingEdge(dut.clk_i)
            second_task = cocotb.start_soon(tb.run_request(1, requests[1]))
            responses = (await first_task, await second_task)

            try:
                for request, response in zip(requests, responses):
                    if not request.is_write:
                        assert response.data == ZERO_WORD

                if name == "read/read":
                    assert_cache_line(tb, 0, base, COH_SHARED, ZERO_LINE)
                    assert_cache_line(tb, 1, base, COH_SHARED, ZERO_LINE)
                elif name == "read/write":
                    assert_cache_line(tb, 0, base, COH_INVALID, ZERO_LINE)
                    assert_cache_line(tb, 1, base, COH_MODIFIED, final_line)
                elif name == "write/read":
                    assert_cache_line(tb, 0, base, COH_SHARED, final_line)
                    assert_cache_line(tb, 1, base, COH_SHARED, final_line)
                else:
                    assert_cache_line(
                        tb, 0, base, COH_INVALID, first_line
                    )
                    assert_cache_line(
                        tb, 1, base, COH_MODIFIED, final_line
                    )
            except AssertionError as error:
                raise AssertionError(
                    f"scenario={name} delay_cycles={delay_cycles}: {error}"
                ) from error
