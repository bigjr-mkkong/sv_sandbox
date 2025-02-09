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

    dut.rst_ni.value = 1
    await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 0

    for _ in range(10):
        await RisingEdge(dut.clk_i)
        print(f"Blinky core out: {dut.led_o.value} at time: {sim_clk}")


