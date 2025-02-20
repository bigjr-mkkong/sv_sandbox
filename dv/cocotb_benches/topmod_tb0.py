import cocotb;
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge

@cocotb.test()
async def tb_0(dut):
    clock_period = 19.9  # ns
    cocotb.start_soon(Clock(dut.CLK, clock_period, unit="ns").start())

    dut.rst_ni.value = 0
    for _ in range(5):
        await RisingEdge(dut.CLK)

    dut.rst_ni.value = 1

    for _ in range(2000):
        await RisingEdge(dut.CLK)

