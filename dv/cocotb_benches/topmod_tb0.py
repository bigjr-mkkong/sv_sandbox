import cocotb;
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge

from aes_enc import one_round_aes

@cocotb.test()
async def tb_0(dut):
    cocotb.start_soon(Clock(dut.clk_i, 5, unit="ns").start())

    dut.rst_ni.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_i)

    dut.rst_ni.value = 1

    key = 12345
    for i in range(10):
        dut.ptext_i.value = i
        dut.key_i.value = key
        await RisingEdge(dut.clk_i)
        dut_ans = int(dut.cipher_o.value)
        rel_ans = one_round_aes(i, key)
        print(i,dut_ans,rel_ans)

    for _ in range(10):
        await RisingEdge(dut.clk_i)

