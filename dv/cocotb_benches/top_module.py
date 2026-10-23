"""Integrated CPU programs using the supplied single-byte serial SPI RAM model."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer, with_timeout

from dv.cocotb_benches.simp_spi_ram_helper import read_memory, write_memory


async def reset(dut):
    dut.rst_ni.value = 0
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await ClockCycles(dut.clk_i, 3)
    await Timer(1, unit="ns")
    assert not dut.halt_o.value
    await write_memory(dut.ram.mem, 0, [0x00] * len(dut.ram.mem))


async def run_program(dut, words):
    program = [byte for word in words for byte in (word & 0xFF, word >> 8)]
    await write_memory(dut.ram.mem, 0, program)
    dut.rst_ni.value = 1
    await with_timeout(RisingEdge(dut.halt_o), 1, "ms")
    await Timer(1, unit="ns")
    assert dut.spi_cs_n.value, "CPU halted during a serial transaction"
    assert read_memory(dut.ram.mem, 0, len(program)) == program


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def memory_access(dut):
    await reset(dut)
    memory = dut.ram.mem
    await write_memory(memory, 0, [0x12, 0xA7, 0x35])
    await write_memory(memory, len(memory) - 2, [0xFE, 0xCA])
    assert read_memory(memory, 0, 3) == [0x12, 0xA7, 0x35]
    assert read_memory(memory, len(memory) - 2, 2) == [0xFE, 0xCA]
    await write_memory(memory, len(memory), [])
    assert read_memory(memory, len(memory), 0) == []
    for address, length in ((-1, 1), (0, -1), (len(memory), 1)):
        try:
            read_memory(memory, address, length)
        except ValueError:
            pass
        else:
            raise AssertionError("Out-of-range read was accepted")
    for address, data in ((-1, [0x00]), (len(memory) - 1, [0x00, 0x00]), (0, [0x00, 0x100])):
        try:
            await write_memory(memory, address, data)
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid memory write was accepted")
    await Timer(1, unit="ns")
    assert read_memory(memory, 0, 3) == [0x12, 0xA7, 0x35]
    assert read_memory(memory, len(memory) - 2, 2) == [0xFE, 0xCA]


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def executes_program(dut):
    await reset(dut)
    await write_memory(dut.ram.mem, 0x200, [0xFE, 0xCA, 0x34, 0x12])
    # WA 0x200; TOGA bit 15; WA 0x202; TOGA bit 3; HALT.
    await run_program(dut, [0x8100, 0x7800, 0x8101, 0x1800, 0])
    assert read_memory(dut.ram.mem, 0x200, 4) == [0xFE, 0x4A, 0x3C, 0x12]


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def branch_across_instruction_windows(dut):
    await reset(dut)
    await write_memory(dut.ram.mem, 0x300, [0x04, 0x00, 0xA5, 0x5A])
    # Clearing bit 2 jumps from PC 1 to PC 16, past the first IRAM window.
    program = [0x8180, 0x100E, 0x7000] + [0] * 13 + [0x8181, 0x4000, 0]
    await run_program(dut, program)
    assert read_memory(dut.ram.mem, 0x300, 4) == [0x00, 0x00, 0xA5, 0x5B]
