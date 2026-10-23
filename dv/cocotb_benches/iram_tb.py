"""Independent IRAM cases using the shared C++-backed ideal SPI RAM.

The verification plan covers reset, cold fill, a 16-instruction stream, a jump
following five instructions, a 64-instruction stream, and a jump after draining
a window. Additional cases retain boundary, alias, wraparound, backpressure,
redirect, and reset-during-refill coverage.
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from dv.cocotb_benches.clock import tick


WINDOW_WORDS = 16
FETCH_TIMEOUT = 256


def instruction(pc):
    pc &= 0x7FFF
    return (((pc ^ (pc >> 5)) * 0x3151) ^ 0xA65C) & 0xFFFF


def refill_addresses(pc):
    return [(2 * (pc + offset) + byte) & 0xFFFF
            for offset in range(WINDOW_WORDS) for byte in range(2)]


def assert_window(dut, start):
    assert dut.iram.iram_window_valid_q.value, "Instruction window is invalid"
    assert int(dut.iram.iram_window_begin_q.value) == start


async def monitor_reads(dut, reads):
    held_address = None
    pending = False
    while True:
        await RisingEdge(dut.clk_i)
        if not dut.rst_ni.value or not dut.run_i.value:
            held_address = None
            pending = False
            continue
        address = int(dut.iram_new_pc_o.value)
        if dut.iram_val_o.value:
            assert not dut.iram_spi.req_we.value
            assert int(dut.iram_spi.req_wdata.value) == 0
        if pending and dut.spi_val_o.value:
            assert dut.iram_spi.rsp_rdy.value, "IRAM missed the byte response"
            pending = False
        if held_address is not None:
            assert dut.iram_val_o.value and address == held_address
        if dut.iram_val_o.value and dut.spi_rdy_o.value:
            reads.append(address)
            pending = True
        held_address = address if dut.iram_val_o.value and not dut.spi_rdy_o.value else None


async def reset(dut):
    dut.clk_i.value = 0
    dut.rst_ni.value = 0
    dut.run_i.value = 0
    dut.req_val_i.value = 0
    dut.pc_i.value = 0
    dut.rsp_rdy_i.value = 0
    dut.mem_write_i.value = 0
    dut.mem_addr_i.value = 0
    dut.mem_data_i.value = 0
    await tick(dut)
    assert not dut.iram.iram_window_valid_q.value
    assert not dut.req_rdy_o.value and not dut.rsp_val_o.value
    assert not dut.iram_val_o.value and not dut.spi_val_o.value
    dut.rst_ni.value = 1
    await Timer(1, unit="ns")


async def preload(dut, pcs):
    """Load each requested window through the ideal memory's byte-write port."""
    dut.run_i.value = 0
    for address in sorted({address for pc in pcs for address in refill_addresses(pc)}):
        dut.mem_addr_i.value = address
        dut.mem_data_i.value = (instruction(address >> 1) >> (8 * (address & 1))) & 0xFF
        dut.mem_write_i.value = 1
        await Timer(1, unit="ns")
        for _ in range(4):
            accepted = bool(dut.spi_rdy_o.value)
            await tick(dut)
            if accepted:
                break
        else:
            raise AssertionError("Ideal SPI RAM did not accept preload byte")
        dut.mem_write_i.value = 0
        for _ in range(4):
            if dut.spi_val_o.value:
                break
            await tick(dut)
        else:
            raise AssertionError("Ideal SPI RAM did not acknowledge preload byte")
    dut.run_i.value = 1
    await Timer(1, unit="ns")


async def setup(dut, *pcs):
    await reset(dut)
    await preload(dut, pcs)
    reads = []
    # cocotb cancels this passive monitor when its test ends, including failures.
    cocotb.start_soon(monitor_reads(dut, reads))
    return reads


async def select_pc(dut, pc):
    dut.pc_i.value = pc
    dut.req_val_i.value = 1
    dut.rsp_rdy_i.value = 0
    await Timer(1, unit="ns")


async def wait_for_response(dut):
    for _ in range(FETCH_TIMEOUT):
        if dut.rsp_val_o.value:
            return
        accepted = dut.req_val_i.value and dut.req_rdy_o.value
        await tick(dut)
        if accepted:
            dut.req_val_i.value = 0
    raise AssertionError(f"IRAM did not return PC {int(dut.pc_i.value):#x}")


async def receive(dut, reads, pc, *, hold=0):
    await wait_for_response(dut)
    assert int(dut.inst_o.value) == instruction(pc), f"Wrong instruction at PC {pc:#x}"
    completed = len(reads)
    for _ in range(hold):
        await tick(dut)
        assert dut.rsp_val_o.value and int(dut.inst_o.value) == instruction(pc)
        assert len(reads) == completed, "Held response caused another refill"
    # Fetching HALT withdraws request valid before accepting the response.
    dut.req_val_i.value = 0
    await Timer(1, unit="ns")
    assert dut.rsp_val_o.value
    dut.rsp_rdy_i.value = 1
    await tick(dut)
    assert not dut.rsp_val_o.value, "Accepted response was returned twice"


async def fetch(dut, reads, pc, *, hold=0):
    start = len(reads)
    await select_pc(dut, pc)
    await receive(dut, reads, pc, hold=hold)
    return reads[start:]


async def stream(dut, reads, start, count):
    """Check every instruction and require exactly one refill per 16 words."""
    for offset in range(count):
        pc = (start + offset) & 0xFFFF
        expected = refill_addresses(pc) if offset % WINDOW_WORDS == 0 else []
        assert await fetch(dut, reads, pc) == expected
        assert_window(dut, (start + offset // WINDOW_WORDS * WINDOW_WORDS) & 0xFFFF)


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def reset_invalidates_window(dut):
    reads = await setup(dut, 5)
    for _ in range(4):
        await tick(dut)
        assert not dut.iram.iram_window_valid_q.value
        assert not dut.rsp_val_o.value and not dut.iram_val_o.value
    assert reads == []
    assert await fetch(dut, reads, 5) == refill_addresses(5)
    assert_window(dut, 5)
    await reset(dut)


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def reset_and_fill(dut):
    reads = await setup(dut, 5)
    await select_pc(dut, 5)
    assert dut.req_rdy_o.value and not dut.iram.sram_req_val.value
    await tick(dut)
    assert dut.iram_val_o.value and not dut.rsp_val_o.value
    assert not dut.iram.iram_window_valid_q.value
    await receive(dut, reads, 5)
    assert reads == refill_addresses(5)
    assert_window(dut, 5)


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def reset_and_stream_16(dut):
    reads = await setup(dut, 5)
    await stream(dut, reads, 5, 16)
    assert reads == refill_addresses(5)


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def reset_and_jump_after_five(dut):
    reads = await setup(dut, 5, 0x100)
    await stream(dut, reads, 5, 5)
    assert await fetch(dut, reads, 0x100) == refill_addresses(0x100)
    assert_window(dut, 0x100)
    assert reads == refill_addresses(5) + refill_addresses(0x100)


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def drain_and_continue_64(dut):
    starts = (0x40, 0x50, 0x60, 0x70)
    reads = await setup(dut, *starts)
    await stream(dut, reads, starts[0], 64)
    assert reads == [address for pc in starts for address in refill_addresses(pc)]


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def drain_and_jump(dut):
    reads = await setup(dut, 0x10, 0x100)
    await stream(dut, reads, 0x10, 16)
    assert await fetch(dut, reads, 0x100) == refill_addresses(0x100)
    assert_window(dut, 0x100)
    assert reads == refill_addresses(0x10) + refill_addresses(0x100)


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def window_boundaries(dut):
    reads = await setup(dut, 0x20, 0x30, 0x2F)
    assert await fetch(dut, reads, 0x20) == refill_addresses(0x20)
    assert await fetch(dut, reads, 0x2F) == []  # Last word still hits.
    assert await fetch(dut, reads, 0x30) == refill_addresses(0x30)  # End is exclusive.
    assert_window(dut, 0x30)
    assert await fetch(dut, reads, 0x2F) == refill_addresses(0x2F)  # Below the window misses.
    assert_window(dut, 0x2F)


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def high_pc_spi_alias(dut):
    reads = await setup(dut, 5, 0x8005)
    assert await fetch(dut, reads, 5) == refill_addresses(5)
    # Different logical windows use the same physical SPI byte addresses.
    assert await fetch(dut, reads, 0x8005) == refill_addresses(5)
    assert_window(dut, 0x8005)
    assert await fetch(dut, reads, 0x8014) == []


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def spi_byte_address_wraparound(dut):
    reads = await setup(dut, 0x7FF8)
    assert await fetch(dut, reads, 0x7FF8) == refill_addresses(0x7FF8)
    for pc in (0x7FFF, 0x8000, 0x8007):
        assert await fetch(dut, reads, pc) == []
    assert_window(dut, 0x7FF8)


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def word_pc_wraparound(dut):
    reads = await setup(dut, 0xFFF8, 8)
    assert await fetch(dut, reads, 0xFFF8) == refill_addresses(0xFFF8)
    for pc in (0xFFFF, 0, 7):
        assert await fetch(dut, reads, pc) == []
    assert_window(dut, 0xFFF8)
    assert await fetch(dut, reads, 8) == refill_addresses(8)
    assert_window(dut, 8)


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def response_backpressure(dut):
    reads = await setup(dut, 5)
    assert await fetch(dut, reads, 5, hold=8) == refill_addresses(5)
    assert await fetch(dut, reads, 6, hold=5) == []
    assert_window(dut, 5)


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def redirect_held_hit(dut):
    reads = await setup(dut, 0x100, 0x110)
    assert await fetch(dut, reads, 0x100) == refill_addresses(0x100)
    await select_pc(dut, 0x100)
    await wait_for_response(dut)
    dut.pc_i.value = 0x107
    await Timer(1, unit="ns")
    assert not dut.rsp_val_o.value, "Redirect exposed an old-PC response"
    assert await fetch(dut, reads, 0x107) == []
    assert await fetch(dut, reads, 0x110) == refill_addresses(0x110)
    assert_window(dut, 0x110)


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def redirect_during_refill(dut):
    reads = await setup(dut, 0x100, 0x200)
    await select_pc(dut, 0x100)
    for _ in range(FETCH_TIMEOUT):
        await tick(dut)
        if len(reads) >= 5:
            break
    else:
        raise AssertionError("Refill did not start before redirect")
    await fetch(dut, reads, 0x200)
    assert reads == refill_addresses(0x100) + refill_addresses(0x200)
    assert_window(dut, 0x200)


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def reset_during_refill(dut):
    reads = await setup(dut, 0x200, 0x300)
    assert await fetch(dut, reads, 0x200) == refill_addresses(0x200)
    start = len(reads)
    await select_pc(dut, 0x300)
    for _ in range(FETCH_TIMEOUT):
        await tick(dut)
        if len(reads) >= start + 3 and not dut.spi_rdy_o.value:
            break
    else:
        raise AssertionError("No pending memory transaction to reset")
    await reset(dut)
    for _ in range(3):
        await tick(dut)
        assert not dut.spi_val_o.value, "Reset leaked a pending memory response"
        assert not dut.rsp_val_o.value and not dut.iram.iram_window_valid_q.value
    await preload(dut, (0x200,))
    assert await fetch(dut, reads, 0x200) == refill_addresses(0x200)
    assert_window(dut, 0x200)
