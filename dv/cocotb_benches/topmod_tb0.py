import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge


CLOCK_PERIOD_PS = 20_834
UART_PRESCALE_CYCLES = 417


async def wait_clock_cycles(clock, count):
    for _ in range(count):
        await RisingEdge(clock)


async def receive_uart_byte(dut):
    txd_o = dut.txd_o
    await FallingEdge(txd_o)
    await wait_clock_cycles(dut.clk_i, UART_PRESCALE_CYCLES // 2)
    assert int(txd_o.value) == 0, "invalid UART start bit"

    value = 0
    for bit_index in range(8):
        await wait_clock_cycles(dut.clk_i, UART_PRESCALE_CYCLES)
        value |= int(txd_o.value) << bit_index

    await wait_clock_cycles(dut.clk_i, UART_PRESCALE_CYCLES)
    assert int(txd_o.value) == 1, "invalid UART stop bit"
    return value


@cocotb.test()
async def transmits_alphabet(dut):
    cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_PS, unit="ps").start())
    dut.rxd_i.value = 1
    dut.rst_ni.value = 0
    for _ in range(10):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1

    assert await receive_uart_byte(dut) == ord("A")
    assert await receive_uart_byte(dut) == ord("B")
