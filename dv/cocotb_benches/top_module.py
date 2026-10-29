"""Integrated CPU programs using the supplied single-byte serial SPI RAM model."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge, Timer, with_timeout

from dv.cocotb_benches.simp_spi_ram_helper import read_memory, write_memory
from dv.cocotb_benches.programs.dataset import check_memory, initial_regions, load_programs

PROGRAMS = {case["name"]: case for case in load_programs()}


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


async def load_program(dut, program):
    """Clear RAM and apply the dataset's code and memory preconditions."""
    await reset(dut)
    for address, data in initial_regions(program):
        await write_memory(dut.ram.mem, address, list(data))


def check_postcondition(dut, program):
    check_memory(program, lambda address, length: read_memory(dut.ram.mem, address, length))
    pipeline = dut.cpu.main_module_inst.pipeline
    for name, expected in program["simulation"].get("registers", {}).items():
        assert int(getattr(pipeline, name).value) == expected, f"{program['name']}: {name}"


async def check_halted(dut):
    """HALT empties the pipeline and stays asserted without further execution."""
    pipeline = dut.cpu.main_module_inst.pipeline
    source = getattr(dut.cpu.main_module_inst, "sources[0]")
    state = (int(pipeline.pc_q.value), int(pipeline.reg_q.value),
             int(pipeline.reg_addr_q.value))
    for _ in range(64):
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        assert dut.halt_o.value
        assert not pipeline.inst_valid_q.value
        assert not pipeline.reg_dirty_q.value
        assert not pipeline.icache_req_val_o.value and not pipeline.icache_rdy_o.value
        assert not source.req_val.value and not source.rsp_rdy.value
        assert dut.spi_cs_n.value and not dut.spi_sclk.value
        assert (int(pipeline.pc_q.value), int(pipeline.reg_q.value),
                int(pipeline.reg_addr_q.value)) == state
    await Timer(1, unit="ns")


async def prog_exec(dut, program):
    """Execute one dataset, including its simulation-only observations."""
    await load_program(dut, program)
    sim = program["simulation"]
    backward_offsets, transactions = [], []
    monitor = cocotb.start_soon(check_branch_targets(dut, backward_offsets))
    data_monitor = (cocotb.start_soon(check_data_transactions(dut, transactions))
                    if "data_transactions" in sim else None)
    dut.rst_ni.value = 1
    try:
        await with_timeout(RisingEdge(dut.halt_o), sim.get("timeout_ms", 500), "ms")
        await Timer(1, unit="ns")
    finally:
        monitor.cancel()
        if data_monitor is not None:
            data_monitor.cancel()
    await Timer(1, unit="ns")
    assert dut.halt_o.value
    assert dut.spi_cs_n.value, "CPU halted during a serial transaction"
    await check_halted(dut)
    check_postcondition(dut, program)
    assert len(backward_offsets) >= sim.get("min_backward_branches", 0)
    if "backward_offsets" in sim:
        assert set(backward_offsets) == set(sim["backward_offsets"])
    if "data_transactions" in sim:
        assert transactions == [tuple(transfer) for transfer in sim["data_transactions"]]
    if backward_offsets:
        dut._log.info("%s: checked %d backward branches, offsets %s",
                      program["name"], len(backward_offsets), sorted(set(backward_offsets)))


async def reset_last_byte(dut, write):
    await load_program(dut, PROGRAMS["wa_direct_64"])
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
    check_postcondition(dut, PROGRAMS["wa_direct_64"])


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def reset_during_last_load_byte(dut):
    await reset_last_byte(dut, False)


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def reset_during_last_write_byte(dut):
    await reset_last_byte(dut, True)


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def asynchronous_reset_pulse(dut):
    await prog_exec(dut, PROGRAMS["basic_wa"])
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
    check_postcondition(dut, PROGRAMS["basic_wa"])


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


def program_test(program):
    async def run(dut):
        await prog_exec(dut, program)
    run.__name__ = program["name"]
    run.__qualname__ = program["name"]
    return cocotb.test(timeout_time=program["simulation"].get("timeout_ms", 500),
                       timeout_unit="ms")(run)


for _program in PROGRAMS.values():
    if _program["name"] in globals():
        raise ValueError(f"Program name conflicts with a bench helper: {_program['name']}")
    globals()[_program["name"]] = program_test(_program)
