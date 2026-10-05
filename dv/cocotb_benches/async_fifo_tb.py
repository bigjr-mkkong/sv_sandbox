"""Basic transfer across two skewed clocks."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer


@cocotb.test(timeout_time=2, timeout_unit="us")
async def transfers(dut):
    dut.rst_ni.value = 0
    dut.w_val_i.value = 0
    dut.w_data_i.value = 0
    dut.r_val_i.value = 0
    cocotb.start_soon(Clock(dut.w_clk_i, 10, unit="ns").start())
    await Timer(3, unit="ns")
    cocotb.start_soon(Clock(dut.r_clk_i, 16, unit="ns").start())
    await Timer(60, unit="ns")
    dut.rst_ni.value = 1
    await Timer(80, unit="ns")
    assert int(dut.w_rdy_o.value) == 1
    assert int(dut.r_rdy_o.value) == 0

    for value in range(16):
        await FallingEdge(dut.w_clk_i)
        dut.w_data_i.value = value
        dut.w_val_i.value = 1
        await RisingEdge(dut.w_clk_i)
        await FallingEdge(dut.w_clk_i)
        dut.w_val_i.value = 0
    assert int(dut.w_rdy_o.value) == 0

    await Timer(80, unit="ns")
    for value in range(16):
        await FallingEdge(dut.r_clk_i)
        dut.r_val_i.value = 1
        await RisingEdge(dut.r_clk_i)
        await Timer(1, unit="ns")
        assert int(dut.r_rdy_o.value) == 1
        assert int(dut.r_data_o.value) == value
        dut.r_val_i.value = 0

    await FallingEdge(dut.r_clk_i)
    dut.r_val_i.value = 1
    await RisingEdge(dut.r_clk_i)
    await Timer(1, unit="ns")
    assert int(dut.r_rdy_o.value) == 0
