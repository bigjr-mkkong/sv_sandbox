import cocotb;
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge
from colorama import Fore

from present import enc

@cocotb.test()
async def tb_0(dut):
    cocotb.start_soon(Clock(dut.clk_i, 5, unit="ns").start())

    dut.rst_ni.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_i)

    dut.rst_ni.value = 1

    key = 1234
    ptext = 1234
    dut.ptext_i.value = ptext
    dut.key_i.value = key
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    cip2 = dut.cipher_o.value
    cip1 = enc(ptext, key)
    print(hex(cip1))

    # for p in range(65536):
    #     dut.ptext_i.value = p
    #     dut.key_i.value = key
    #     await RisingEdge(dut.clk_i)
    #     await RisingEdge(dut.clk_i)
    #     cip2 = dut.cipher_o.value
    #     cip1 = enc(p, key)

    #     assert cip2 == cip1

    for _ in range(10):
        await RisingEdge(dut.clk_i)

