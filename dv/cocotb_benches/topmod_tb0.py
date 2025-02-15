import cocotb;
from cocotb.triggers import Timer, RisingEdge, FallingEdge

sim_clk = 0
async def clk_gen(dut):
    for sim_clk in range(1000):
        dut.clk_i.value = 0
        await Timer(2, units="ns")
        dut.clk_i.value = 1
        await Timer(2, units="ns")

@cocotb.test()
async def tb_0(dut):
    cocotb.start_soon(clk_gen(dut))

    dut.button_i.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk_i)
    dut.button_i.value = 1
    for _ in range(4):
        await RisingEdge(dut.clk_i)


