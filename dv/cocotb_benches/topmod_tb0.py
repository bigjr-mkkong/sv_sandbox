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

    dut.uart_rsp_rdy_i.value = 1
    data = 0

    await RisingEdge(dut.uart_rsp_val_o)
    data = dut.uart_rsp_data_o.value
    assert(data == 0x31)

    await RisingEdge(dut.clk_i)
    dut.uart_rsp_rdy_i.value = 0

    for _ in range (2):
        await RisingEdge(dut.clk_i)

    dut.uart_rsp_rdy_i.value = 1

    await RisingEdge(dut.uart_rsp_val_o)
    data = dut.uart_rsp_data_o.value
    assert(data == 0x32)

    await RisingEdge(dut.clk_i)
    dut.uart_rsp_rdy_i.value = 0

    for _ in range (2):
        await RisingEdge(dut.clk_i)

    for _ in range(100):
        await RisingEdge(dut.clk_i)

