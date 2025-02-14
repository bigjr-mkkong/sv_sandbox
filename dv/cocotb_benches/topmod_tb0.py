import cocotb;
from cocotb.triggers import Timer, RisingEdge, FallingEdge

sim_clk = 0
async def clk_gen(dut):
    for sim_clk in range(1000):
        dut.clk_i.value = 0
        await Timer(2, units="ns")
        dut.clk_i.value = 1
        await Timer(2, units="ns")

    cocotb.finish()

@cocotb.test()
async def tb_pushpop(dut):
    cocotb.start_soon(clk_gen(dut))

    dut.rst_ni.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    dut.req_val_i.value = 1
    dut.req_typ_i.value = 2
    dut.data_i.value = 4
    await RisingEdge(dut.req_rdy_o)

    dut.rsp_rdy_i.value = 1
    await RisingEdge(dut.rsp_val_o)

    dut.req_val_i.value = 1
    dut.req_typ_i.value = 2
    dut.data_i.value = 5
    await RisingEdge(dut.req_rdy_o)

    dut.rsp_rdy_i.value = 1
    await RisingEdge(dut.rsp_val_o)

    dut.req_val_i.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_i)

    dut.req_val_i.value = 1
    dut.req_typ_i.value = 1
    await RisingEdge(dut.req_rdy_o)

    dut.rsp_rdy_i.value = 1
    await RisingEdge(dut.rsp_val_o)
    rsp_data = dut.data_o.value

    assert rsp_data == 4

    dut.req_val_i.value = 1
    dut.req_typ_i.value = 1
    await RisingEdge(dut.req_rdy_o)

    dut.rsp_rdy_i.value = 1
    await RisingEdge(dut.rsp_val_o)
    dut.req_val_i.value = 0
    rsp_data = dut.data_o.value

    assert rsp_data == 5

    for _ in range(40):
        await RisingEdge(dut.clk_i)


@cocotb.test()
async def tb_push_query(dut):
    cocotb.start_soon(clk_gen(dut))

    dut.rst_ni.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    dut.req_val_i.value = 1
    dut.req_typ_i.value = 2
    dut.data_i.value = 4
    await RisingEdge(dut.req_rdy_o)

    dut.rsp_rdy_i.value = 1
    await RisingEdge(dut.rsp_val_o)

    dut.req_val_i.value = 1
    dut.req_typ_i.value = 2
    dut.data_i.value = 5
    await RisingEdge(dut.req_rdy_o)

    dut.rsp_rdy_i.value = 1
    await RisingEdge(dut.rsp_val_o)

    dut.req_val_i.value = 0

    for _ in range(5):
        await RisingEdge(dut.clk_i)

    dut.req_val_i.value = 1
    dut.req_typ_i.value = 3
    await RisingEdge(dut.req_rdy_o)

    dut.rsp_rdy_i.value = 1
    await RisingEdge(dut.rsp_val_o)
    rsp_data = dut.data_o.value

    assert rsp_data == 2

    for _ in range(40):
        await RisingEdge(dut.clk_i)


