import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge


CLOCK_PERIOD_PS = 20_834
UART_PRESCALE_CYCLES = 417


async def wait_clock_cycles(clock, count):
    for _ in range(count):
        await RisingEdge(clock)


async def receive_uart_byte(dut):
    txd_o = dut.TX
    await FallingEdge(txd_o)
    await wait_clock_cycles(dut.CLK, UART_PRESCALE_CYCLES // 2)
    assert int(txd_o.value) == 0, "invalid UART start bit"

    value = 0
    for bit_index in range(8):
        await wait_clock_cycles(dut.CLK, UART_PRESCALE_CYCLES)
        value |= int(txd_o.value) << bit_index

    await wait_clock_cycles(dut.CLK, UART_PRESCALE_CYCLES)
    assert int(txd_o.value) == 1, "invalid UART stop bit"
    return value


@cocotb.test()
async def transmits_after_ice40_mapping(dut):
    # The simulation netlist bypasses the hardware PLL, so CLK is driven at 48 MHz.
    cocotb.start_soon(Clock(dut.CLK, CLOCK_PERIOD_PS, unit="ps").start())
    dut.RX.value = 1
    dut.BTN_N.value = 0
    for _ in range(10):
        await RisingEdge(dut.CLK)
    dut.BTN_N.value = 1

    assert await receive_uart_byte(dut) == ord("A")
    assert await receive_uart_byte(dut) == ord("B")
