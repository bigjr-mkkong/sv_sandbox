"""Integrated CPU test skeleton; execution awaits a serial SPI memory model."""

import cocotb


@cocotb.test(skip=True)
async def executes_program(dut):
    """Attach and preload SPI memory, reset the CPU, then check HALT and memory."""
    # TODO: Implement once a serial SPI memory verification model is available.
    pass
