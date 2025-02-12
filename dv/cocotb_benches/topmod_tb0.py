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

    dut.rst_ni.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    dut.req_val_i.value = 1
    dut.req_typ_i.value = 1
    dut.data_i.value = 4
    await RisingEdge(dut.req_rdy_o)

    dut.req_val_i.value = 0
    dut.rsp_rdy_i = 1
    rsp_data = dut.data_o.value
    await RisingEdge(dut.rsp_val_o)

    for _ in range(40):
        await RisingEdge(dut.clk_i)


