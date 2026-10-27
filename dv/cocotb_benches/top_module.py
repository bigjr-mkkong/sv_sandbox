"""Integrated CPU programs using the supplied single-byte serial SPI RAM model."""

from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge, Timer, with_timeout

from dv.cocotb_benches.simp_spi_ram_helper import read_memory, write_memory


async def reset(dut):
    dut.rst_ni.value = 0
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await ClockCycles(dut.clk_i, 3)
    await Timer(1, unit="ns")
    assert not dut.halt_o.value
    await write_memory(dut.ram.mem, 0, [0x00] * len(dut.ram.mem))


async def check_branch_targets(dut, backward_offsets):
    """Check sign extension and the actual registered PC on every taken branch."""
    pipeline = dut.cpu.main_module_inst.pipeline
    while True:
        await RisingEdge(pipeline.flush)
        await ReadOnly()
        raw = int(pipeline.inst_q.value) & 0x1FF
        offset = raw - 0x200 if raw & 0x100 else raw
        base = int(pipeline.pc_q.value)
        target = (base + offset) & 0xFFFF
        assert int(pipeline.branch_pc.value) == target, (
            f"Branch at PC {base - 1:#06x}: offset {offset}, expected {target:#06x}"
        )
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        assert int(pipeline.pc_q.value) == target, f"PC did not reach {target:#06x}"
        if offset < 0:
            backward_offsets.append(offset)


async def check_data_transactions(dut, transactions):
    """Observe data handshakes, held requests, and atomic register commits."""
    cpu = dut.cpu.main_module_inst
    source = getattr(cpu, "sources[0]")
    pipeline = cpu.pipeline
    pending = held = None
    loaded = 0
    while True:
        await FallingEdge(dut.clk_i)
        await ReadOnly()
        if not pipeline.rst_ni.value:
            continue
        payload = (int(source.req_we.value), int(source.req_addr.value),
                   int(source.req_wdata.value))
        if held is not None:
            assert source.req_val.value and payload == held, "Stalled request changed"
        held = payload if source.req_val.value and not source.req_rdy.value else None
        if source.req_val.value and source.req_rdy.value:
            assert pending is None, "Multiple outstanding data requests"
            pending = payload
            transactions.append((payload[0], payload[1], payload[2] if payload[0] else 0))
        response = bool(source.rsp_val.value and source.rsp_rdy.value)
        previous = int(pipeline.reg_q.value)
        previous_address = int(pipeline.reg_addr_q.value)
        byte = int(pipeline.byte_q.value)
        if pending is not None:
            assert not dut.halt_o.value, "HALT before the final byte response"
        if response:
            assert pending is not None, "Unsolicited data response"
            write, address, _ = pending
            assert byte == address % 8
            if not write:
                if byte == 0:
                    loaded = 0
                loaded |= int(source.rsp_rdata.value) << (8 * byte)
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        if pending is not None:
            if response and not write and byte == 7:
                assert int(pipeline.reg_q.value) == loaded
                assert int(pipeline.reg_addr_q.value) == address & ~7
            else:
                assert int(pipeline.reg_q.value) == previous, "Partial load changed the pointer"
                assert int(pipeline.reg_addr_q.value) == previous_address
            if response:
                if write:
                    assert bool(pipeline.reg_dirty_q.value) == (byte != 7)
                assert int(pipeline.byte_q.value) == (byte + 1) % 8
                pending = None


async def load_program(dut, compiled_program):
    """Preload a generated image while the CPU is held in reset."""
    await reset(dut)
    address = 0
    for line in compiled_program.read_text(encoding="ascii").splitlines():
        if line.startswith("@"):
            address = int(line[1:], 16)
        else:
            data = [int(byte, 16) for byte in line.split()]
            await write_memory(dut.ram.mem, address, data)
            address += len(data)


async def prog_exec(dut, compiled_program, data_transactions=None):
    """Execute a generated image and check its postcondition."""
    await load_program(dut, compiled_program)
    backward_offsets = []
    monitor = cocotb.start_soon(check_branch_targets(dut, backward_offsets))
    data_monitor = (cocotb.start_soon(check_data_transactions(dut, data_transactions))
                    if data_transactions is not None else None)
    dut.rst_ni.value = 1
    try:
        await with_timeout(RisingEdge(dut.halt_o), 500, "ms")
        await Timer(1, unit="ns")
    finally:
        monitor.cancel()
        if data_monitor is not None:
            data_monitor.cancel()
    await Timer(1, unit="ns")
    assert dut.halt_o.value
    assert dut.spi_cs_n.value, "CPU halted during a serial transaction"
    globals()[f"{compiled_program.stem}_post_check"](dut)
    name = compiled_program.stem
    if name in ("fibonacci", "fibonacci_overflow", "gcd", "lfsr", "backward_branch_limits"):
        assert backward_offsets, f"{name} never took a backward branch"
        dut._log.info("%s: checked %d backward branches, offsets %s",
                      name, len(backward_offsets), sorted(set(backward_offsets)))
    if name == "backward_branch_limits":
        assert set(backward_offsets) == {-1, -256}


def basic_wa_post_check(dut):
    pipeline = dut.cpu.main_module_inst.pipeline
    # PC has advanced past the HALT at word address 1.
    assert int(pipeline.pc_q.value) == 2
    assert int(pipeline.reg_addr_q.value) == 0x200
    assert int(pipeline.reg_q.value) == 0xBC9A785634125AA4
    assert read_memory(dut.ram.mem, 0x200, 8) == [0xA4, 0x5A, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC]


def basic_toga_no_jump_post_check(dut):
    pipeline = dut.cpu.main_module_inst.pipeline
    assert int(pipeline.pc_q.value) == 3
    assert int(pipeline.reg_addr_q.value) == 0x200
    assert int(pipeline.reg_q.value) == 0xBC9A785634125AA4
    assert read_memory(dut.ram.mem, 0x200, 8) == [0xA4, 0x5A, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC]


def basic_toga_jump_post_check(dut):
    pipeline = dut.cpu.main_module_inst.pipeline
    assert int(pipeline.pc_q.value) == 4
    assert int(pipeline.reg_addr_q.value) == 0x200
    assert int(pipeline.reg_q.value) == 0xBC9A785634125AA0
    assert read_memory(dut.ram.mem, 0x200, 8) == [0xA0, 0x5A, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC]


def check_benchmark_words(dut, expected):
    """Check every variable and unused bit in each affected 64-bit word."""
    for address in sorted({location & ~7 for location in expected}):
        wanted = [byte for offset in range(0, 8, 2)
                  for byte in (expected.get(address + offset, 0), 0x00)]
        actual = read_memory(dut.ram.mem, address, 8)
        assert actual == wanted, f"At {address:#06x}: {actual}, expected {wanted}"


def incrementer_post_check(dut):
    check_benchmark_words(dut, {0x4000: 0x00})


def adder_post_check(dut):
    check_benchmark_words(dut, {0x4000: 0x7F, 0x4002: 0x81, 0x4004: 0x00})


def fibonacci_post_check(dut):
    check_benchmark_words(dut, {
        0x4000: 0x0D, 0x4004: 0xE9, 0x4008: 0xE9,
        0x400A: 0x79, 0x400C: 0x79, 0x400E: 0x00,
    })


def fibonacci_overflow_post_check(dut):
    check_benchmark_words(dut, {
        0x4000: 0x0E, 0x4004: 0x79, 0x4008: 0x79,
        0x400A: 0x62, 0x400C: 0x62, 0x400E: 0x00,
    })


def gcd_post_check(dut):
    check_benchmark_words(dut, {
        0x4000: 0xFF, 0x4002: 0xFB, 0x4004: 0x01, 0x4008: 0x01, 0x400A: 0x01,
    })


def lfsr_post_check(dut):
    check_benchmark_words(dut, {0x4000: 0xFF, 0x4002: 0x00})


def backward_branch_limits_post_check(dut):
    pipeline = dut.cpu.main_module_inst.pipeline
    assert int(pipeline.pc_q.value) == 6
    assert int(pipeline.reg_q.value) == 0
    check_benchmark_words(dut, {0x4000: 0x00})


def wa_direct_64_post_check(dut):
    pipeline = dut.cpu.main_module_inst.pipeline
    assert int(pipeline.pc_q.value) == 259
    assert int(pipeline.reg_addr_q.value) == 0xFFF8
    assert int(pipeline.reg_q.value) == 0x7EDCBA9876553210
    assert read_memory(dut.ram.mem, 0xFFF8, 8) == [0x10, 0x32, 0x55, 0x76, 0x98, 0xBA, 0xDC, 0x7E]


def wa_indirect_post_check(dut):
    pipeline = dut.cpu.main_module_inst.pipeline
    assert int(pipeline.pc_q.value) == 11
    assert int(pipeline.reg_addr_q.value) == 0x5800
    assert int(pipeline.reg_q.value) == 0x80000B00
    for address, value in ((0x4000, 0x8000000000000B01), (0x57F8, 0x0123456789ABCDEF),
                           (0x5800, 0x80000B00), (0x5808, 0xA55A123456781FFF),
                           (0xFFF8, 0xDEF09ABC56781234)):
        assert read_memory(dut.ram.mem, address, 8) == list(value.to_bytes(8, "little"))


def wa_indirect_zero_post_check(dut):
    pipeline = dut.cpu.main_module_inst.pipeline
    assert int(pipeline.pc_q.value) == 3
    assert int(pipeline.reg_addr_q.value) == 0
    assert int(pipeline.reg_q.value) == int.from_bytes(read_memory(dut.ram.mem, 0, 8), "little")
    assert read_memory(dut.ram.mem, 0x4000, 8) == [0x00, 0x20, 0xAB, 0x89, 0x67, 0x45, 0x23, 0xF1]


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def wa_direct_64(dut):
    transactions = []
    await prog_exec(dut, Path(__file__).with_name("example_program") / "wa_direct_64.hex", transactions)
    expected = [(0, address, 0) for address in range(0xFFF8, 0x10000)]
    expected += [(1, 0xFFF8 + byte, value) for byte, value in enumerate(
        [0x10, 0x32, 0x55, 0x76, 0x98, 0xBA, 0xDC, 0x7E])]
    assert transactions == expected


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def wa_indirect(dut):
    transactions = []
    await prog_exec(dut, Path(__file__).with_name("example_program") / "wa_indirect.hex", transactions)
    expected = []
    for write, address, value in ((0, 0x4000, 0), (1, 0x4000, 0x8000000000000B01),
                                  (0, 0x5808, 0), (0, 0xFFF8, 0),
                                  (1, 0xFFF8, 0xDEF09ABC56781234),
                                  (0, 0x5800, 0), (0, 0x5800, 0), (1, 0x5800, 0x80000B00)):
        expected.extend((write, address + byte, (value >> (8 * byte)) & 0xFF) for byte in range(8))
    assert transactions == expected


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def wa_indirect_zero(dut):
    await prog_exec(dut, Path(__file__).with_name("example_program") / "wa_indirect_zero.hex")


async def reset_last_byte(dut, write):
    await load_program(dut, Path(__file__).with_name("example_program") / "wa_direct_64.hex")
    cpu = dut.cpu.main_module_inst
    original = read_memory(dut.ram.mem, 0xFFF8, 8)
    dut.rst_ni.value = 1
    while True:
        await FallingEdge(dut.clk_i)
        if (int(cpu.pipeline.byte_q.value) == 7
                and bool(cpu.pipeline.reg_dirty_q.value) == write
                and int(cpu.arbiter.curr_idx_q.value) == 0
                and not dut.spi_cs_n.value and int(cpu.spi.bit_idx.value) == 8):
            break
    assert not dut.halt_o.value
    partial = read_memory(dut.ram.mem, 0xFFF8, 8)
    if write:
        assert partial == [0x10, 0x32, 0x55, 0x76, 0x98, 0xBA, 0xDC, 0xFE]
    else:
        assert int(cpu.pipeline.reg_q.value) == 0
    dut.rst_ni.value = 0
    await ClockCycles(dut.clk_i, 3)
    await Timer(1, unit="ns")
    assert not cpu.pipeline.reg_q.value
    assert not cpu.pipeline.reg_dirty_q.value
    assert not cpu.pipeline.byte_q.value
    assert not cpu.pipeline.load_low_q.value
    assert not cpu.pipeline.spi_state_q.value
    assert not dut.halt_o.value
    assert dut.spi_cs_n.value
    assert read_memory(dut.ram.mem, 0xFFF8, 8) == partial
    await write_memory(dut.ram.mem, 0xFFF8, original)
    dut.rst_ni.value = 1
    await with_timeout(RisingEdge(dut.halt_o), 2, "ms")
    await Timer(1, unit="ns")
    wa_direct_64_post_check(dut)


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def reset_during_last_load_byte(dut):
    await reset_last_byte(dut, False)


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def reset_during_last_write_byte(dut):
    await reset_last_byte(dut, True)


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def asynchronous_reset_pulse(dut):
    await prog_exec(dut, Path(__file__).with_name("example_program") / "basic_wa.hex")
    cpu = dut.cpu.main_module_inst
    assert cpu.iram.iram_window_valid_q.value

    # A pulse entirely between rising edges must still reset every CPU block.
    await FallingEdge(dut.clk_i)
    await Timer(1, unit="ns")
    dut.rst_ni.value = 0
    await Timer(1, unit="ns")
    assert not dut.cpu.rst_sync_ni.value
    assert not cpu.pipeline.rst_ni.value
    assert not cpu.iram.rst_ni.value
    assert not cpu.iram.sram_blk_inst.rst_ni.value
    assert not cpu.arbiter.rst_ni.value
    assert cpu.spi.rst.value
    dut.rst_ni.value = 1
    await Timer(1, unit="ns")
    assert not dut.clk_i.value
    assert not dut.cpu.rst_sync_ni.value

    await RisingEdge(dut.clk_i)
    await Timer(1, unit="ns")
    assert not dut.cpu.rst_sync_ni.value
    assert not cpu.pipeline.pc_q.value
    assert not cpu.pipeline.reg_q.value
    assert not dut.halt_o.value
    assert not cpu.iram.iram_window_valid_q.value
    assert int(cpu.iram.sram_blk_inst.state_q.value) == 0
    assert int(cpu.arbiter.state_q.value) == 0
    assert int(cpu.spi.state.value) == 0
    assert dut.spi_cs_n.value

    await RisingEdge(dut.clk_i)
    await Timer(1, unit="ns")
    assert dut.cpu.rst_sync_ni.value
    assert not cpu.pipeline.pc_q.value
    assert not dut.halt_o.value
    await with_timeout(RisingEdge(dut.halt_o), 2, "ms")
    await Timer(1, unit="ns")
    assert dut.spi_cs_n.value
    basic_wa_post_check(dut)


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
async def basic_wa(dut):
    await prog_exec(dut, Path(__file__).with_name("example_program") / "basic_wa.hex")


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def basic_toga_no_jump(dut):
    await prog_exec(dut, Path(__file__).with_name("example_program") / "basic_toga_no_jump.hex")


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def basic_toga_jump(dut):
    await prog_exec(dut, Path(__file__).with_name("example_program") / "basic_toga_jump.hex")


@cocotb.test(timeout_time=500, timeout_unit="ms")
async def incrementer(dut):
    await prog_exec(dut, Path(__file__).with_name("example_program") / "incrementer.hex")


@cocotb.test(timeout_time=500, timeout_unit="ms")
async def adder(dut):
    await prog_exec(dut, Path(__file__).with_name("example_program") / "adder.hex")


@cocotb.test(timeout_time=500, timeout_unit="ms")
async def fibonacci(dut):
    await prog_exec(dut, Path(__file__).with_name("example_program") / "fibonacci.hex")


@cocotb.test(timeout_time=500, timeout_unit="ms")
async def fibonacci_overflow(dut):
    await prog_exec(dut, Path(__file__).with_name("example_program") / "fibonacci_overflow.hex")


@cocotb.test(timeout_time=500, timeout_unit="ms")
async def gcd(dut):
    await prog_exec(dut, Path(__file__).with_name("example_program") / "gcd.hex")


@cocotb.test(timeout_time=500, timeout_unit="ms")
async def lfsr(dut):
    await prog_exec(dut, Path(__file__).with_name("example_program") / "lfsr.hex")


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def backward_branch_limits(dut):
    await prog_exec(dut, Path(__file__).with_name("example_program") / "backward_branch_limits.hex")


# Basic integration cases (WA loads one 64-bit word):
# 1. WA addr; HALT: load the word, stop with fetch PC 2.
# 2. WA addr; TOGA bit, new_pc; HALT; new_pc: HALT:
#    a zero bit becomes one, falls through, and stops with fetch PC 3.
# 3. The same code with the selected bit initially one:
#    the bit becomes zero, branches to new_pc, and stops with fetch PC 4.
# HALT is 0x0000; check PC to distinguish the two HALT locations.
