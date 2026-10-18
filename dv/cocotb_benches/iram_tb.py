"""Exercise IRAM through the real SPI master and a byte-addressed SPI slave."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from dv.cocotb_benches.togawa_tb import tick


def instruction(pc):
    pc &= 0x7FFF
    return (((pc ^ (pc >> 5)) * 0x3151) ^ 0xA65C) & 0xFFFF


def refill_addresses(pc):
    return [(2 * (pc + offset) + byte) & 0xFFFF
            for offset in range(16) for byte in range(2)]


async def spi_memory(dut, reads):
    previous_cs, previous_sclk = 1, 0
    bits, frame, address = 0, 0, 0
    held_address = None
    while True:
        await RisingEdge(dut.clk_i)
        await Timer(1, unit="ns")
        cs, sclk = int(dut.spi_cs_n.value), int(dut.spi_sclk.value)
        if not dut.rst_ni.value:
            bits, frame, held_address = 0, 0, None
            dut.spi_miso.value = 0
        else:
            if held_address is not None:
                assert dut.iram_val_o.value
                assert int(dut.iram_new_pc_o.value) == held_address
            held_address = (int(dut.iram_new_pc_o.value)
                            if dut.iram_val_o.value and not dut.spi_rdy_o.value else None)
            if not cs:
                if previous_cs:
                    bits, frame = 0, 0
                if sclk and not previous_sclk:
                    frame = (frame << 1) | int(dut.spi_mosi.value)
                    bits += 1
                    if bits == 24:
                        assert frame >> 16 == 0x03, "expected a SPI read command"
                        address = frame & 0xFFFF
                elif previous_sclk and not sclk and 24 <= bits < 32:
                    byte = (instruction(address >> 1) >> (8 * (address & 1))) & 0xFF
                    dut.spi_miso.value = (byte >> (31 - bits)) & 1
            elif not previous_cs:
                assert bits == 32, "SPI frame must contain command, 16-bit address, and byte"
                assert frame & 0xFF == 0, "read frames must send a zero data byte"
                reads.append(address)
                dut.spi_miso.value = 0
        previous_cs, previous_sclk = cs, sclk


async def fetch(dut, reads, pc, *, hold=0):
    start = len(reads)
    dut.pc_i.value = pc
    dut.req_val_i.value = 1
    dut.rsp_rdy_i.value = 0
    await Timer(1, unit="ns")
    for _ in range(10000):
        accepted = dut.req_val_i.value and dut.req_rdy_o.value
        await tick(dut)
        if accepted:
            dut.req_val_i.value = 0
        if dut.rsp_val_o.value:
            assert int(dut.inst_o.value) == instruction(pc), f"wrong instruction at PC {pc:#x}"
            completed = len(reads)
            for _ in range(hold):
                await tick(dut)
                assert dut.rsp_val_o.value
                assert int(dut.inst_o.value) == instruction(pc)
                assert len(reads) == completed
            # A fetched HALT can withdraw request valid before accepting its response.
            dut.req_val_i.value = 0
            await Timer(1, unit="ns")
            assert dut.rsp_val_o.value
            dut.rsp_rdy_i.value = 1
            await tick(dut)
            return reads[start:]
    raise AssertionError(f"IRAM did not return PC {pc:#x}")


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def refill_hits_redirects_and_reset(dut):
    dut.clk_i.value = 0
    dut.rst_ni.value = 0
    dut.req_val_i.value = 0
    dut.pc_i.value = 0
    dut.rsp_rdy_i.value = 0
    dut.spi_miso.value = 0
    reads = []
    memory = cocotb.start_soon(spi_memory(dut, reads))
    await tick(dut)
    dut.rst_ni.value = 1

    # A cold miss requests SPI on the next cycle without reading SRAM first.
    dut.pc_i.value = 5
    dut.req_val_i.value = 1
    await Timer(1, unit="ns")
    assert dut.req_rdy_o.value and not dut.iram.sram_req_val.value
    await tick(dut)
    assert dut.iram_val_o.value and not dut.rsp_val_o.value

    # Unaligned fill starts at the requested PC; all sixteen words then hit.
    assert await fetch(dut, reads, 5, hold=4) == refill_addresses(5)
    for pc in range(5, 21):
        assert await fetch(dut, reads, pc) == []

    # The window end is exclusive; PCs below the window and far away also miss.
    assert await fetch(dut, reads, 21) == refill_addresses(21)
    assert await fetch(dut, reads, 4) == refill_addresses(4)
    assert await fetch(dut, reads, 0x8005) == refill_addresses(0x8005)

    # SPI byte addresses wrap at 64 KiB while word PCs remain sixteen bits.
    assert await fetch(dut, reads, 0x7FF8) == refill_addresses(0x7FF8)
    for pc in (0x7FFF, 0x8000, 0x8007):
        assert await fetch(dut, reads, pc) == []

    # The logical word PC also wraps at sixteen bits.
    assert await fetch(dut, reads, 0xFFF8) == refill_addresses(0xFFF8)
    for pc in (0xFFFF, 0, 7):
        assert await fetch(dut, reads, pc) == []

    # Redirect a held hit: the old instruction must disappear immediately.
    dut.pc_i.value = 0
    dut.req_val_i.value = 1
    dut.rsp_rdy_i.value = 0
    for _ in range(10):
        await tick(dut)
        if dut.rsp_val_o.value:
            break
    else:
        raise AssertionError("cached instruction did not respond")
    dut.pc_i.value = 7
    await Timer(1, unit="ns")
    assert not dut.rsp_val_o.value, "redirect exposed an old-PC response"
    assert await fetch(dut, reads, 7) == []
    assert await fetch(dut, reads, 8) == refill_addresses(8)

    # A redirect during refill drains that fill and fetches the new PC.
    start = len(reads)
    dut.pc_i.value = 0x100
    dut.req_val_i.value = 1
    dut.rsp_rdy_i.value = 0
    for _ in range(1000):
        await tick(dut)
        if len(reads) >= start + 5:
            break
    else:
        raise AssertionError("SPI refill did not start")
    await fetch(dut, reads, 0x200)
    assert reads[start:] == refill_addresses(0x100) + refill_addresses(0x200)

    # Reset cancels an active SPI frame and invalidates the existing window.
    start = len(reads)
    dut.pc_i.value = 0x300
    dut.req_val_i.value = 1
    for _ in range(1000):
        await tick(dut)
        if len(reads) >= start + 3 and not dut.spi_cs_n.value:
            break
    else:
        raise AssertionError("no active SPI frame to reset")
    dut.rst_ni.value = 0
    dut.req_val_i.value = 0
    await tick(dut)
    assert not dut.rsp_val_o.value and not dut.iram_val_o.value
    assert dut.spi_cs_n.value
    dut.rst_ni.value = 1
    assert await fetch(dut, reads, 0x200) == refill_addresses(0x200)
    memory.cancel()
