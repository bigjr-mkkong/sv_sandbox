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

    dut.uart_req_val_i.value = 1
    dut.uart_data_i.value = 123
    await RisingEdge(dut.uart_req_rdy_o)

    for _ in range(3):
        await RisingEdge(dut.clk_i)

    dut.uart_req_val_i.value = 0
    dut.uart_rsp_rdy_i.value = 1
    await RisingEdge(dut.uart_rsp_val_o)
    recv_dat = dut.uart_rsp_data_o.value

    assert recv_dat == 123

    for _ in range(40):
        await RisingEdge(dut.clk_i)

