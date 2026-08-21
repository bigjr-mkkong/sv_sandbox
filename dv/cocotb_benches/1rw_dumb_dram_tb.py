import itertools
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotbext.axi import AxiLiteBus, AxiLiteMaster, AxiResp


CLOCK_PERIOD_NS = 10
TEST_TIMEOUT_US = 50
ADDR_WIDTH = 64
DATA_WIDTH = 64
DATA_PER_LINE = 8
DATA_BYTES = DATA_WIDTH // 8
LINE_BYTES = DATA_BYTES * DATA_PER_LINE
MAGIC = 114514
MAGIC_LINE = MAGIC.to_bytes(DATA_BYTES, "little") * DATA_PER_LINE


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
async def reset_then_read_returns_magic_line(dut):
    """The first transaction after reset must complete normally."""
    tb = DramTB(dut)
    await tb.reset()

    assert await tb.read_line(0) == MAGIC_LINE


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def reads_are_independent_of_line_address(dut):
    """Every aligned line address returns the same replicated MAGIC value."""
    tb = DramTB(dut)
    await tb.reset()

    for address in (0, LINE_BYTES, 0x1000, 0xABC0, 0x123456780):
        address &= ~(LINE_BYTES - 1)
        assert await tb.read_line(address) == MAGIC_LINE


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def writes_are_acknowledged_and_discarded(dut):
    """A full-line write returns OKAY but does not alter later reads."""
    tb = DramTB(dut)
    await tb.reset()
    address = 0x4000
    payload = bytes(range(LINE_BYTES))

    await tb.write_line(address, payload)
    assert await tb.read_line(address) == MAGIC_LINE


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def split_write_channels_rendezvous(dut):
    """Independently delayed AW and W channels still form one blocking write."""
    tb = DramTB(dut)
    await tb.reset()

    tb.master.write_if.aw_channel.set_pause_generator(
        cycle_pause((1, 1, 0, 0))
    )
    tb.master.write_if.w_channel.set_pause_generator(
        cycle_pause((0, 1, 1, 0))
    )

    await tb.write_line(0x8000, bytes([0xA5]) * LINE_BYTES)
    assert await tb.read_line(0x8000) == MAGIC_LINE


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def randomized_mixed_transactions(dut):
    """Run deterministic mixed AXI-Lite traffic through the blocking slave."""
    tb = DramTB(dut)
    await tb.reset()
    rng = random.Random(0xD00BD12A)

    for _ in range(100):
        address = rng.randrange(256) * LINE_BYTES
        if rng.randrange(2):
            await tb.write_line(address, rng.randbytes(LINE_BYTES))
        else:
            assert await tb.read_line(address) == MAGIC_LINE


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def response_backpressure_is_supported(dut):
    """BREADY and RREADY stalls are handled by cocotbext channel backpressure."""
    tb = DramTB(dut)
    await tb.reset()

    tb.master.write_if.b_channel.set_pause_generator(cycle_pause())
    tb.master.read_if.r_channel.set_pause_generator(cycle_pause((1, 1, 0)))

    for index in range(12):
        address = index * LINE_BYTES
        await tb.write_line(address, bytes([index]) * LINE_BYTES)
        assert await tb.read_line(address) == MAGIC_LINE
