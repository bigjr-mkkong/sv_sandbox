import itertools
import random

import cocotb
from cocotb.clock import Clock
from cocotb.queue import Queue
from cocotb.triggers import FallingEdge, RisingEdge
from cocotbext.axi import AxiLiteBus, AxiLiteMaster, AxiResp

from dv.cocotb_benches.handshake import monitor_handshakes


CLOCK_PERIOD_NS = 10
TEST_TIMEOUT_US = 50
ADDR_WIDTH = 64
DATA_WIDTH = 64
DATA_PER_LINE = 8
DATA_BYTES = DATA_WIDTH // 8
LINE_BYTES = DATA_BYTES * DATA_PER_LINE
ZERO_LINE = bytes(LINE_BYTES)


def cycle_pause(pattern=(1, 1, 1, 0)):
    return itertools.cycle(pattern)


class DramTB:
    def __init__(self, dut):
        self.dut = dut
        cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())
        self.master = AxiLiteMaster(
            AxiLiteBus.from_entity(dut.s_axil),
            dut.clk_i,
            dut.rst_ni,
            reset_active_level=False,
        )

    async def reset(self):
        self.dut.rst_ni.value = 0
        for _ in range(10):
            await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        for _ in range(2):
            await RisingEdge(self.dut.clk_i)

    async def read_line(self, address):
        response = await self.master.read(address, LINE_BYTES)
        assert response.resp == AxiResp.OKAY
        assert len(response.data) == LINE_BYTES
        return bytes(response.data)

    async def write_line(self, address, data):
        assert len(data) == LINE_BYTES
        response = await self.master.write(address, data)
        assert response.resp == AxiResp.OKAY


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def reset_then_read_returns_zero_line(dut):
    # reset()
    # read_line == 0
    """The first transaction after reset must complete normally."""
    tb = DramTB(dut)
    await tb.reset()

    assert await tb.read_line(0) == ZERO_LINE


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def writes_are_stored_by_line_address(dut):
    # write_line(addr, x)
    # assert(read_line(addr) == x)
    """A full-line write must be returned by later reads of that line."""
    tb = DramTB(dut)
    await tb.reset()
    address = 0x4000
    payload = bytes(range(LINE_BYTES))

    await tb.write_line(address, payload)
    assert await tb.read_line(address) == payload

@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def addresses_are_normalized_to_cacheline_boundaries(dut):
    # write_line(addr, data)
    # read_ret = read_line(addr+line_offset)
    # assert(read_ret == data)
    """Low address bits select bytes from one normalized cacheline entry."""
    tb = DramTB(dut)
    await tb.reset()
    address = 0x6000
    payload = bytes(range(LINE_BYTES))

    await tb.write_line(address, payload)
    response = await tb.master.read(address + DATA_BYTES, DATA_BYTES)

    assert response.resp == AxiResp.OKAY
    assert bytes(response.data) == payload[DATA_BYTES:2 * DATA_BYTES]


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def reset_clears_stored_lines(dut):
    # reset()
    # write(addr, data)
    # reset()
    # assert(read(addr) == 0)
    """RTL reset also resets the per-instance C++ memory object."""
    tb = DramTB(dut)
    await tb.reset()
    address = 0x7000
    payload = bytes([0xC3]) * LINE_BYTES

    await tb.write_line(address, payload)
    assert await tb.read_line(address) == payload

    await tb.reset()
    assert await tb.read_line(address) == ZERO_LINE


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def split_write_channels_rendezvous(dut):
    # in cycle 2: send_word(data)
    # in cycle 3: send_addr(addr)
    # assert(read(addr) == word)
    """Independently delayed AW and W channels still form one blocking write."""
    tb = DramTB(dut)
    await tb.reset()

    tb.master.write_if.aw_channel.set_pause_generator(
        cycle_pause((1, 1, 0, 0))
    )
    tb.master.write_if.w_channel.set_pause_generator(
        cycle_pause((0, 1, 1, 0))
    )

    payload = bytes([0xA5]) * LINE_BYTES
    await tb.write_line(0x8000, payload)
    assert await tb.read_line(0x8000) == payload


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def randomized_mixed_transactions(dut):
    # loop 100:
    #   addr = rand()
    #   data = rand()
    #   write_line(addr, data)
    #   assert(read_line(addr) == data)
    """Run deterministic mixed AXI-Lite traffic through the blocking slave."""
    tb = DramTB(dut)
    await tb.reset()
    rng = random.Random(0xD00BD12A)
    expected_lines = {}

    for _ in range(100):
        address = rng.randrange(256) * LINE_BYTES
        if rng.randrange(2):
            payload = rng.randbytes(LINE_BYTES)
            await tb.write_line(address, payload)
            expected_lines[address] = payload
        else:
            assert await tb.read_line(address) == expected_lines.get(
                address, ZERO_LINE
            )


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def response_backpressure_is_supported(dut):
    """Queue requests independently of collecting stalled B/R responses."""
    tb = DramTB(dut)
    await tb.reset()

    channels = {}
    for name, fields in (
        ("aw", ("awaddr", "awprot")), ("w", ("wdata", "wstrb")),
        ("b", ("bresp",)), ("ar", ("araddr", "arprot")),
        ("r", ("rdata", "rresp")),
    ):
        channels[name] = (
            getattr(dut.s_axil, name + "valid"),
            getattr(dut.s_axil, name + "ready"),
            tuple(getattr(dut.s_axil, field) for field in fields),
        )
    transfers, stalls = {}, {}
    monitor = cocotb.start_soon(
        monitor_handshakes(dut.clk_i, channels, transfers, stalls)
    )

    # Writes must finish before dependent reads, but requests within each batch
    # are queued without waiting for responses. The AXI driver owns the pins.
    for is_write in (True, False):
        completions = Queue()
        sink = tb.master.write_if.b_channel if is_write else tb.master.read_if.r_channel
        sink.pause = True
        response_valid = dut.s_axil.bvalid if is_write else dut.s_axil.rvalid
        request_valid = dut.s_axil.awvalid if is_write else dut.s_axil.arvalid

        async def produce():
            for index in range(12):
                address = index * LINE_BYTES
                payload = bytes([index + 1]) * LINE_BYTES
                event = (
                    tb.master.init_write(address, payload) if is_write
                    else tb.master.init_read(address, LINE_BYTES)
                )
                completions.put_nowait((event, payload))
                await RisingEdge(dut.clk_i)

        async def consume():
            while True:
                await FallingEdge(dut.clk_i)
                if response_valid.value and request_valid.value:
                    break
            # A real response is stalled while the next request is pending.
            for _ in range(4):
                await RisingEdge(dut.clk_i)
                assert response_valid.value
                assert request_valid.value
                assert not dut.s_axil.awready.value
                assert not dut.s_axil.wready.value
                assert not dut.s_axil.arready.value
            sink.set_pause_generator(cycle_pause())
            for _ in range(12):
                event, payload = await completions.get()
                await event.wait()
                assert event.data.resp == AxiResp.OKAY
                if not is_write:
                    assert bytes(event.data.data) == payload
            sink.clear_pause_generator()
            sink.pause = False

        producer = cocotb.start_soon(produce())
        consumer = cocotb.start_soon(consume())
        await producer
        await consumer

    for _ in range(3):
        await RisingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    monitor.cancel()
    assert transfers == dict.fromkeys(channels, 12)
    for name in channels:
        assert stalls[name] > 0, f"{name}: no backpressure was exercised"
