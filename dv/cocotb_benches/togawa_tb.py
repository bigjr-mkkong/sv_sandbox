"""Directed TOGAWA programs running against the wrapper's two ideal SRAMs."""

import cocotb
from cocotb.triggers import Timer


def wa(address):
    assert 0 <= address <= 0xFFFE and address % 2 == 0
    return 0x8000 | (address >> 1)


def toga(bit, skip):
    assert 0 <= bit < 16 and -1024 <= skip <= 1023
    word = (bit << 11) | (skip & 0x7FF)
    assert word != 0, "bit 0 / skip 0 encodes HALT"
    return word


async def tick(dut):
    dut.clk_i.value = 0
    await Timer(5, unit="ns")
    dut.clk_i.value = 1
    await Timer(5, unit="ns")


async def memory_access(dut, *, instruction, address, value=None):
    """Access actual SRAM while the pipeline is stopped or halted."""
    assert 0 <= address <= 0x1FFFE and address % 2 == 0
    dut.mem_icache_i.value = instruction
    dut.mem_addr_i.value = address
    dut.mem_write_i.value = value is not None
    dut.mem_read_i.value = value is None
    dut.mem_data_i.value = value if value is not None else 0
    await tick(dut)
    result = int(dut.mem_read_data_o.value)
    dut.mem_write_i.value = 0
    dut.mem_read_i.value = 0
    return result


async def execute(dut, program, data=None):
    """Load SRAMs, clock to HALT, and record accepted data requests."""
    dut.clk_i.value = 0
    dut.rst_ni.value = 0
    dut.run_i.value = 0
    dut.mem_write_i.value = 0
    dut.mem_read_i.value = 0
    dut.mem_icache_i.value = 0
    dut.mem_addr_i.value = 0
    dut.mem_data_i.value = 0
    dut.icache_req_rdy_i.value = 1
    dut.icache_valid_enable_i.value = 1
    dut.dcache_req_enable_i.value = 1
    dut.dcache_rsp_enable_i.value = 1
    await tick(dut)
    assert int(dut.pc_o.value) == 0 and not dut.halt.value
    dut.rst_ni.value = 1
    for pc, word in program.items():
        await memory_access(dut, instruction=True, address=2 * pc, value=word)
    for address, value in (data or {}).items():
        await memory_access(dut, instruction=False, address=address, value=value)
    dut.run_i.value = 1
    await Timer(1, unit="ns")

    transactions = []
    for _ in range(200):
        if dut.halt.value:
            assert not dut.icache_req_val_o.value
            assert not dut.dcache_req_val_o.value
            return transactions
        if dut.dcache_req_val_o.value and dut.dcache_req_rdy_i.value:
            write = int(dut.dcache_req_w.value)
            transactions.append((write, int(dut.dcache_req_addr_o.value),
                                 int(dut.dcache_req_data_o.value) if write else None))
        await tick(dut)
    raise AssertionError("pipeline did not halt")


@cocotb.test(timeout_time=10, timeout_unit="us")
async def halt(dut):
    assert await execute(dut, {}) == []
    assert int(dut.pipeline.reg_q.value) == 0
    assert await memory_access(dut, instruction=False, address=0) == 0


@cocotb.test(timeout_time=10, timeout_unit="us")
async def wa_load(dut):
    address, magic = 0x20, 0xCAFE
    assert await execute(dut, {0: wa(address)}, {address: magic}) == [
        (0, address, None)]
    assert int(dut.pipeline.reg_q.value) == magic
    assert await memory_access(dut, instruction=False, address=address) == magic


@cocotb.test(timeout_time=10, timeout_unit="us")
async def toga_toggle_and_branch(dut):
    # Fresh zero becomes one: no branch, even with a nonzero skip.
    assert await execute(dut, {0: toga(2, 10)}) == [(1, 0, 4)]
    assert int(dut.pipeline.reg_q.value) == 4
    assert int(dut.pc_o.value) == 2  # HALT fetched at PC 1.
    assert await memory_access(dut, instruction=False, address=0) == 4

    # Load a set bit so TOGA clears it and branches: 1 + 1 + 10 = 12.
    assert await execute(dut, {0: wa(0x20), 1: toga(2, 10)}, {0x20: 0x44}) == [
        (0, 0x20, None), (1, 0x20, 0x40)]
    assert int(dut.pipeline.reg_q.value) == 0x40
    assert int(dut.pc_o.value) == 13  # HALT fetched at PC 12.
    assert await memory_access(dut, instruction=False, address=0x20) == 0x40


@cocotb.test(timeout_time=10, timeout_unit="us")
async def toga_then_wa(dut):
    program = {0: wa(0x20), 1: toga(2, 10), 12: wa(0x22)}
    assert await execute(dut, program, {0x20: 0x44, 0x22: 0xCAFE}) == [
        (0, 0x20, None), (1, 0x20, 0x40), (0, 0x22, None)]
    assert int(dut.pipeline.reg_q.value) == 0xCAFE
    assert int(dut.pc_o.value) == 14
    assert await memory_access(dut, instruction=False, address=0x20) == 0x40
    assert await memory_access(dut, instruction=False, address=0x22) == 0xCAFE


@cocotb.test(timeout_time=10, timeout_unit="us")
async def two_togas(dut):
    program = {0: wa(0x20), 1: toga(2, 10), 12: toga(3, 10)}
    assert await execute(dut, program, {0x20: 0x4C}) == [
        (0, 0x20, None), (1, 0x20, 0x40)]
    assert int(dut.pipeline.reg_q.value) == 0x40
    assert int(dut.pc_o.value) == 24  # Second branch: 12 + 1 + 10 = 23.
    assert await memory_access(dut, instruction=False, address=0x20) == 0x40


@cocotb.test(timeout_time=10, timeout_unit="us")
async def toga_wa_wa_toga_wa(dut):
    program = {0: toga(2, 0), 1: wa(0x20), 2: wa(0x22),
               3: toga(3, 0), 4: wa(0x24)}
    data = {0: 0xFFFF, 0x20: 0x1111, 0x22: 0xAA55, 0x24: 0xCAFE}
    assert await execute(dut, program, data) == [
        (1, 0, 4), (0, 0x20, None), (0, 0x22, None),
        (1, 0x22, 0xAA5D), (0, 0x24, None)]
    assert int(dut.pipeline.reg_q.value) == 0xCAFE
    for address, value in {**data, 0: 4, 0x22: 0xAA5D}.items():
        assert await memory_access(dut, instruction=False, address=address) == value


@cocotb.test(timeout_time=20, timeout_unit="us")
async def increment_memory(dut):
    address = 0x20
    program = {0: wa(address)}
    # A cleared bit carries into the next TOGA, skipping an unwritten HALT.
    # A set bit ends the carry and falls through to HALT, which writes back.
    for bit in range(16):
        program[1 + 2 * bit] = toga(bit, 1)
    for value in [(1 << bits) - 1 for bits in range(17)] + [0x1234, 0xAAAA, 0xFFFE]:
        expected = (value + 1) & 0xFFFF
        assert await execute(dut, program, {address: value}) == [
            (0, address, None), (1, address, expected)]
        assert int(dut.pipeline.reg_q.value) == expected
        assert await memory_access(dut, instruction=False, address=address) == expected
