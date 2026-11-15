"""Check complete SPI frames, little-endian instruction bursts and reset recovery."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge, Timer

from dv.cocotb_benches.simp_spi_ram_helper import read_memory, write_memory


async def frames(dut, captured):
    previous_cs, previous_clk = 1, 0
    bits = []
    cycle, last_end, last_edge = 0, None, 0
    while True:
        await FallingEdge(dut.clk)
        await ReadOnly()
        cs, clk = int(dut.spi_cs_n.value), int(dut.spi_sclk.value)
        cycle += 1
        if dut.rst.value:
            last_end = None
        if previous_cs and not cs:
            assert not clk, "CS asserted while SCLK was high"
            if last_end is not None:
                assert cycle - last_end >= 32, "CS recovery was shortened"
            bits = []
            last_edge = cycle
        if not cs and clk != previous_clk:
            assert cycle - last_edge == 4, "SCLK divider changed within a frame"
            last_edge = cycle
        if not cs and clk and not previous_clk:
            bits.append(int(dut.spi_mosi.value))
        if not previous_cs and cs:
            assert not clk, "Frame did not finish with SCLK low"
            captured.append(bits)
            if not dut.rst.value:
                last_end = cycle
        previous_cs, previous_clk = cs, clk


def frame_bytes(bits):
    assert len(bits) % 8 == 0
    return [sum(bit << (7 - j) for j, bit in enumerate(bits[i:i + 8]))
            for i in range(0, len(bits), 8)]


async def reset(dut):
    dut.rst.value = 1
    dut.req_val.value = 0
    dut.req_we.value = 0
    dut.req_is_inst.value = 0
    dut.req_addr.value = 0
    dut.req_wdata.value = 0
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    captured = []
    monitor = cocotb.start_soon(frames(dut, captured))
    await ClockCycles(dut.clk, 3)
    await FallingEdge(dut.clk)
    dut.rst.value = 0
    return captured, monitor


async def request(dut, address, *, instruction=False, data=None):
    await FallingEdge(dut.clk)
    dut.req_val.value = 1
    dut.req_addr.value = address
    dut.req_we.value = data is not None
    # Read data phases ignore MOSI; exercise a nonzero transmit payload too.
    dut.req_wdata.value = data if data is not None else 0x1122334455667788
    dut.req_is_inst.value = instruction
    while not dut.req_rdy.value:
        assert not dut.resp_val.value, "Unexpected response while waiting for acceptance"
        await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    # Payload/type must have been captured at acceptance.
    dut.req_val.value = 0
    dut.req_is_inst.value = not instruction
    dut.req_we.value = data is None
    dut.req_addr.value = 0x5555
    dut.req_wdata.value = 0x5A
    await RisingEdge(dut.resp_val)
    await Timer(1, unit="ns")
    result = int((dut.resp_rinst if instruction else dut.resp_rdata).value)
    assert dut.spi_cs_n.value and not dut.spi_sclk.value
    assert not dut.req_rdy.value, "CS recovery was skipped"
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert not dut.resp_val.value, "Response must be a one-cycle pulse"
    return result


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def instruction_bursts_and_data_words(dut):
    captured, monitor = await reset(dut)
    try:
        await write_memory(dut.ram.mem, 0x1F, [0xA7, 0x35])
        await write_memory(dut.ram.mem, 0xFFFF, [0xFE])
        await write_memory(dut.ram.mem, 0, [0xCA])
        assert await request(dut, 0x1F, instruction=True) == 0x35A7
        assert int(dut.ram.mode.value) == 0x40
        assert await request(dut, 0xFFFF, instruction=True) == 0xCAFE
        await request(dut, 0x200, data=0x0123456789ABCDEF)
        assert await request(dut, 0x200) == 0x0123456789ABCDEF
        assert read_memory(dut.ram.mem, 0x1FF, 10) == [0, 0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01, 0]
        read_bytes = [0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11]
        assert [frame_bytes(bits) for bits in captured] == [
            [0x01, 0x40],
            [0x03, 0x00, 0x1F] + read_bytes[:2],
            [0x03, 0xFF, 0xFF] + read_bytes[:2],
            [0x02, 0x02, 0x00, 0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01],
            [0x03, 0x02, 0x00] + read_bytes,
        ]
        await write_memory(dut.ram.mem, 0xFFFC, [0x10, 0x32, 0x54, 0x76])
        await write_memory(dut.ram.mem, 0, [0x98, 0xBA, 0xDC, 0xFE])
        assert await request(dut, 0xFFFC) == 0xFEDCBA9876543210
        assert frame_bytes(captured[-1]) == [0x03, 0xFF, 0xFC] + read_bytes
    finally:
        monitor.cancel()


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def reset_during_instruction_burst(dut):
    captured, monitor = await reset(dut)
    transfer = None
    try:
        await write_memory(dut.ram.mem, 0x200, [0x12, 0xAB])
        transfer = cocotb.start_soon(request(dut, 0x200, instruction=True))
        while dut.spi_cs_n.value or int(dut.master.bit_idx.value) != 34:
            await FallingEdge(dut.clk)
        dut.rst.value = 1
        transfer.cancel()
        await ClockCycles(dut.clk, 3)
        await FallingEdge(dut.clk)
        assert dut.spi_cs_n.value and not dut.spi_sclk.value
        assert not dut.resp_val.value
        assert not dut.resp_rinst.value
        # RAM mode survives CPU reset; recover even if the host changed it.
        dut.ram.mode.value = 0
        dut.rst.value = 0
        assert await request(dut, 0x200, instruction=True) == 0xAB12
        assert [len(bits) for bits in captured] == [16, 34, 16, 40]
        assert frame_bytes(captured[-2]) == [0x01, 0x40]
    finally:
        if transfer is not None:
            transfer.cancel()
        monitor.cancel()


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def reset_restarts_mode_setup(dut):
    captured, monitor = await reset(dut)
    try:
        await write_memory(dut.ram.mem, 0x200, [0x34, 0x12])
        # Model the Pi selecting byte mode before CPU reset release.
        dut.ram.mode.value = 0
        while dut.spi_cs_n.value or int(dut.master.bit_idx.value) != 10:
            await FallingEdge(dut.clk)
        assert not dut.req_rdy.value and not dut.resp_val.value
        dut.rst.value = 1
        await ClockCycles(dut.clk, 3)
        await FallingEdge(dut.clk)
        assert dut.spi_cs_n.value and not dut.spi_sclk.value
        assert not dut.ram.mode.value, "Partial WRMR changed the mode"
        dut.rst.value = 0
        assert await request(dut, 0x200, instruction=True) == 0x1234
        assert int(dut.ram.mode.value) == 0x40
        assert [len(bits) for bits in captured] == [10, 16, 40]
        assert frame_bytes(captured[1]) == [0x01, 0x40]
    finally:
        monitor.cancel()


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def reset_preserves_completed_write_bytes(dut):
    captured, monitor = await reset(dut)
    transfer = None
    try:
        await write_memory(dut.ram.mem, 0x200, [0xA5] * 8)
        transfer = cocotb.start_soon(request(dut, 0x200, data=0x0123456789ABCDEF))
        while dut.spi_cs_n.value or int(dut.master.bit_idx.value) != 82:
            await FallingEdge(dut.clk)
        dut.rst.value = 1
        transfer.cancel()
        await ClockCycles(dut.clk, 3)
        await FallingEdge(dut.clk)
        assert read_memory(dut.ram.mem, 0x200, 8) == [0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0xA5]
        assert dut.spi_cs_n.value and not dut.resp_val.value
        dut.rst.value = 0
        assert await request(dut, 0x200) == 0xA523456789ABCDEF
        assert [len(bits) for bits in captured] == [16, 82, 16, 88]
    finally:
        if transfer is not None:
            transfer.cancel()
        monitor.cancel()
