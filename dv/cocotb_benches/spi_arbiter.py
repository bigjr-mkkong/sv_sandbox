"""Exercise both arbiter sources against the wrapper's C++ ideal byte memory."""

from types import SimpleNamespace

import cocotb
from cocotb.triggers import Timer

from dv.cocotb_benches.clock import tick


def ports(dut):
    names = ("req_val_i", "req_rdy_o", "req_we_i", "req_addr_i", "req_wdata_i",
             "rsp_val_o", "rsp_rdata_o", "rsp_rdy_i")
    return [SimpleNamespace(**{name: getattr(dut, f"src{i}_{name}") for name in names})
            for i in range(2)]


async def reset(dut, sources):
    dut.clk_i.value = 0
    dut.rst_ni.value = 0
    for source in sources:
        for name in ("req_val_i", "req_we_i", "req_addr_i", "req_wdata_i", "rsp_rdy_i"):
            getattr(source, name).value = 0
    await tick(dut)
    for source in sources:
        assert not source.req_rdy_o.value and not source.rsp_val_o.value
    dut.rst_ni.value = 1
    await Timer(1, unit="ns")


def request(source, address, value=None):
    source.req_addr_i.value = address
    source.req_we_i.value = value is not None
    source.req_wdata_i.value = value if value is not None else 0
    source.req_val_i.value = 1
    source.rsp_rdy_i.value = 0


async def accept(dut, source):
    await Timer(1, unit="ns")
    for _ in range(12):
        accepted = bool(source.req_rdy_o.value)
        await tick(dut)
        if accepted:
            source.req_val_i.value = 0
            # The memory must use the accepted payload, not these later values.
            source.req_addr_i.value = 0xFFFF
            source.req_wdata_i.value = 0xFF
            source.req_we_i.value = 0
            return
    raise AssertionError("Request was not accepted")


async def response(dut, sources, index, expected, hold=0):
    source, other = sources[index], sources[1 - index]
    for _ in range(12):
        if source.rsp_val_o.value:
            break
        assert not other.rsp_val_o.value, "Response routed to the wrong source"
        assert not source.req_rdy_o.value and not other.req_rdy_o.value
        await tick(dut)
    else:
        raise AssertionError("Memory did not respond")
    other.rsp_rdy_i.value = 1
    for _ in range(hold + 1):
        assert source.rsp_val_o.value and int(source.rsp_rdata_o.value) == expected
        assert not other.rsp_val_o.value, "Response routed to the wrong source"
        assert not source.req_rdy_o.value and not other.req_rdy_o.value
        await tick(dut)
    source.rsp_rdy_i.value = 1
    await tick(dut)
    assert not source.rsp_val_o.value, "Duplicate response after acknowledgment"
    source.rsp_rdy_i.value = 0
    other.rsp_rdy_i.value = 0


async def transaction(dut, sources, index, address, value=None, expected=0, hold=0):
    request(sources[index], address, value)
    await accept(dut, sources[index])
    await response(dut, sources, index, expected, hold)


@cocotb.test(timeout_time=100, timeout_unit="us")
async def shared_byte_memory_and_backpressure(dut):
    sources = ports(dut)
    await reset(dut, sources)
    for address in (0, 1, 0xFFFE, 0xFFFF):
        await transaction(dut, sources, 0, address)
    # Adjacent byte addresses must remain independent.
    for address, value in ((0, 0x12), (1, 0xA7), (0xFFFE, 0x35), (0xFFFF, 0xC8)):
        await transaction(dut, sources, address & 1, address, value, hold=3)
    for address, value in ((0, 0x12), (1, 0xA7), (0xFFFE, 0x35), (0xFFFF, 0xC8)):
        await transaction(dut, sources, 1 - (address & 1), address, expected=value, hold=5)
    await transaction(dut, sources, 1, 0, 0xE9)
    await transaction(dut, sources, 0, 1, expected=0xA7)
    await transaction(dut, sources, 0, 0, expected=0xE9)
    for _ in range(4):
        await tick(dut)
        assert not any(source.rsp_val_o.value for source in sources)


@cocotb.test(timeout_time=100, timeout_unit="us")
async def concurrent_requests(dut):
    sources = ports(dut)
    await reset(dut, sources)
    for round_index in range(3):
        # Both remain valid until granted. Source 1 must wait through source 0's response stall.
        request(sources[0], 0x200, 0x40 + round_index)
        request(sources[1], 0x201, 0xA0 + round_index)
        await Timer(1, unit="ns")
        assert sources[0].req_rdy_o.value and not sources[1].req_rdy_o.value
        await accept(dut, sources[0])
        await response(dut, sources, 0, 0, hold=6)
        await accept(dut, sources[1])
        await response(dut, sources, 1, 0, hold=4)
    await transaction(dut, sources, 1, 0x200, expected=0x42)
    await transaction(dut, sources, 0, 0x201, expected=0xA2)


@cocotb.test(timeout_time=100, timeout_unit="us")
async def reset_cancels_pending_work_and_clears_memory(dut):
    sources = ports(dut)
    await reset(dut, sources)
    request(sources[1], 0x300, 0xAB)
    await accept(dut, sources[1])
    await reset(dut, sources)  # Before the ideal RAM commits the write.
    await transaction(dut, sources, 0, 0x300)
    await transaction(dut, sources, 1, 0x301, 0xCD)
    request(sources[0], 0x301)
    await accept(dut, sources[0])
    for _ in range(12):
        if sources[0].rsp_val_o.value:
            break
        await tick(dut)
    else:
        raise AssertionError("No buffered response to reset")
    await reset(dut, sources)
    for _ in range(4):
        await tick(dut)
        assert not any(source.rsp_val_o.value for source in sources)
    await transaction(dut, sources, 1, 0x301)


@cocotb.test(timeout_time=100, timeout_unit="us")
async def reset_only(dut):
    sources = ports(dut)
    await reset(dut, sources)
    dut.rst_ni.value = 0
    for _ in range(4):
        await tick(dut)
        for source in sources:
            assert not source.req_rdy_o.value and not source.rsp_val_o.value
            assert int(source.rsp_rdata_o.value) == 0
    dut.rst_ni.value = 1
    for _ in range(4):
        await tick(dut)
        # The reset memory gates ready low; once released, source 0 is preferred.
        assert sources[0].req_rdy_o.value and not sources[1].req_rdy_o.value
        for source in sources:
            assert not source.rsp_val_o.value and int(source.rsp_rdata_o.value) == 0


@cocotb.test(timeout_time=100, timeout_unit="us")
async def single_request(dut):
    sources = ports(dut)
    for index in range(2):
        await reset(dut, sources)
        await transaction(dut, sources, index, 0x1234, hold=3)
        for _ in range(4):
            await tick(dut)
            assert not any(source.rsp_val_o.value for source in sources)


@cocotb.test(timeout_time=100, timeout_unit="us")
async def overlapping_requests(dut):
    sources = ports(dut)
    for first in range(2):
        await reset(dut, sources)
        request(sources[first], 0x400, 0x12)
        await accept(dut, sources[first])
        request(sources[1 - first], 0x400, 0xA7)
        await response(dut, sources, first, 0, hold=3)
        await accept(dut, sources[1 - first])
        await response(dut, sources, 1 - first, 0)
        await transaction(dut, sources, first, 0x400, expected=0xA7)


@cocotb.test(timeout_time=100, timeout_unit="us")
async def simultaneous_requests(dut):
    sources = ports(dut)
    await reset(dut, sources)
    for index, value in enumerate((0x12, 0xA7)):
        request(sources[index], 0x400, value)
    await Timer(1, unit="ns")
    assert sources[0].req_rdy_o.value and not sources[1].req_rdy_o.value
    await accept(dut, sources[0])
    await response(dut, sources, 0, 0, hold=3)
    await accept(dut, sources[1])
    await response(dut, sources, 1, 0)
    await transaction(dut, sources, 0, 0x400, expected=0xA7)
