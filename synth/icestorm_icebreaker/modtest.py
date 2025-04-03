import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge

@cocotb.test()
async def modtb_0(dut):
    cocotb.start_soon(Clock(dut.CLK, 4, unit="ns").start())
    dut.BTN_N.value = 0
    for i in range(8):
        await RisingEdge(dut.CLK)
    dut.BTN_N.value = 1
    for i in range(2000):
        await RisingEdge(dut.CLK)
