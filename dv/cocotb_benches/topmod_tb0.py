import cocotb;
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge

@cocotb.test()
async def tb_0(dut):
    cocotb.start_soon(Clock(dut.clk_i, 4, unit="ns").start())

    dut.rst_ni.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_i)

    dut.rst_ni.value = 1


    for _ in range(100):
        await RisingEdge(dut.clk_i)

