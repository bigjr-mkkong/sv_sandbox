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

    dut.req_val_i.value = 1
    dut.req_typ_i.value = 1
    dut.req_addr_i.value = 3
    dut.req_data_i.value = 12
    await RisingEdge(dut.req_rdy_o)


    for _ in range(100):
        await RisingEdge(dut.clk_i)

