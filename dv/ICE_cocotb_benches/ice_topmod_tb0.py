import cocotb;
from cocotb.triggers import Timer, RisingEdge, FallingEdge

sim_clk = 0
async def clk_gen(dut):
    for sim_clk in range(1000):
        dut.CLK.value = 0
        await Timer(2, units="ns")
        dut.CLK.value = 1
        await Timer(2, units="ns")

@cocotb.test()
async def tb_0(dut):
    cocotb.start_soon(clk_gen(dut))

    dut.BTN_N.value = 0
    await RisingEdge(dut.CLK)
    dut.BTN_N.value = 1

    for _ in range(40):
        await RisingEdge(dut.CLK)


