import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge
import colorama
from colorama import Fore, Style

def printval(val):
    print(Fore.MAGENTA + str(val))
    print(Style.RESET_ALL)

@cocotb.test()
async def tb_0(dut):
    cocotb.start_soon(Clock(dut.clk_i, 4, unit="ns").start())

    dut.rst_ni.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_i)

    dut.rst_ni.value = 1

# Write
    dut.req_val_i.value = 1
    dut.req_typ_i.value = 1
    dut.req_addr_i.value = 3
    dut.req_data_i.value = 0xA
    await RisingEdge(dut.req_rdy_o)
    await RisingEdge(dut.clk_i)

    dut.req_val_i.value = 0
    dut.rsp_rdy_i.value = 1

    await RisingEdge(dut.rsp_val_o)
    await RisingEdge(dut.clk_i)

#Read

    dut.rsp_rdy_i.value = 0
    dut.req_val_i.value = 1
    dut.req_typ_i.value = 0
    dut.req_addr_i.value = 3
    dut.req_data_i.value = 0xB
    await RisingEdge(dut.req_rdy_o)
    await RisingEdge(dut.clk_i)

    dut.req_val_i.value = 0
    dut.rsp_rdy_i.value = 1
    
    await RisingEdge(dut.rsp_val_o)
    data = dut.rsp_data_o.value
    await RisingEdge(dut.clk_i)
    
    printval(data)

#Read from another place
    dut.rsp_rdy_i.value = 0
    dut.req_val_i.value = 1
    dut.req_typ_i.value = 0
    dut.req_addr_i.value = 4
    dut.req_data_i.value = 0xC
    await RisingEdge(dut.req_rdy_o)
    await RisingEdge(dut.clk_i)

    dut.req_val_i.value = 0
    dut.rsp_rdy_i.value = 1
    
    await RisingEdge(dut.rsp_val_o)
    data = dut.rsp_data_o.value
    await RisingEdge(dut.clk_i)
    
    printval(data)

    for _ in range(100):
        await RisingEdge(dut.clk_i)

