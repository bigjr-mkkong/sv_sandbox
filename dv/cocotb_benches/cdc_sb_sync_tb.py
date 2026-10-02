"""Check that a bit crosses between skewed writer and reader clocks."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

@cocotb.test(timeout_time=20, timeout_unit="us")
async def faster_reader(dut):
    dut.rst_ni.value = 0
    dut.data_i.value = 0
    cocotb.start_soon(Clock(dut.w_clk_i, 7, unit="ns").start())
    await Timer(3, unit="ns")
    cocotb.start_soon(Clock(dut.r_clk_i, 5, unit="ns").start())

    for _ in range(3):
        await RisingEdge(dut.w_clk_i)
    for _ in range(3):
        await RisingEdge(dut.r_clk_i)
    await Timer(1, unit="ns")
    assert int(dut.data_o.value) == 0

    await FallingEdge(dut.w_clk_i)
    dut.rst_ni.value = 1
    for _ in range(3):
        await RisingEdge(dut.w_clk_i)
    for _ in range(3):
        await RisingEdge(dut.r_clk_i)

    assert int(dut.out_0.value) == 0
    assert int(dut.out_1.value) == 0
    assert int(dut.in_0.value) == 0

    for value in (1, 0):
        await FallingEdge(dut.w_clk_i)
        dut.data_i.value = value
        for _ in range(5):
            await RisingEdge(dut.r_clk_i)
            await Timer(1, unit="ns")
        assert int(dut.data_o.value) == value


@cocotb.test(timeout_time=20, timeout_unit="us")
async def slower_reader(dut):
    dut.rst_ni.value = 0
    dut.data_i.value = 0
    cocotb.start_soon(Clock(dut.w_clk_i, 4, unit="ns").start())
    await Timer(3, unit="ns")
    cocotb.start_soon(Clock(dut.r_clk_i, 6, unit="ns").start())

    for _ in range(3):
        await RisingEdge(dut.w_clk_i)
    for _ in range(3):
        await RisingEdge(dut.r_clk_i)
    await Timer(1, unit="ns")
    assert int(dut.data_o.value) == 0

    await FallingEdge(dut.w_clk_i)
    dut.rst_ni.value = 1
    for _ in range(3):
        await RisingEdge(dut.w_clk_i)
    for _ in range(3):
        await RisingEdge(dut.r_clk_i)

    for value in (1, 0):
        await FallingEdge(dut.w_clk_i)
        dut.data_i.value = value
        for _ in range(5):
            await RisingEdge(dut.r_clk_i)
            await Timer(1, unit="ns")
        assert int(dut.data_o.value) == value
