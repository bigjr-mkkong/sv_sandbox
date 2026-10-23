"""Clock helper shared by component tests."""

from cocotb.triggers import Timer


async def tick(dut):
    dut.clk_i.value = 0
    await Timer(5, unit="ns")
    dut.clk_i.value = 1
    await Timer(5, unit="ns")
