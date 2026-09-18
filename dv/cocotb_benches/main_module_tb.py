"""Check the default alphabet generator, including wraparound and stalls."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from dv.cocotb_benches.handshake import monitor_handshakes


@cocotb.test(timeout_time=20, timeout_unit="us")
async def alphabet_with_backpressure(dut):
    dut.rst_ni.value = 0
    dut.ready_i.value = 0
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    for _ in range(3):
        await RisingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    dut.rst_ni.value = 1

    transfers, stalls = {}, {}
    monitor = cocotb.start_soon(monitor_handshakes(
        dut.clk_i,
        {"tx": (dut.valid_o, dut.ready_i, (dut.data_o,))},
        transfers,
        stalls,
    ))
    accepted = 0
    for cycle in range(130):
        ready = cycle % 5 >= 2
        dut.ready_i.value = ready
        await RisingEdge(dut.clk_i)
        assert dut.valid_o.value
        assert int(dut.data_o.value) == ord("A") + accepted % 26
        accepted += int(ready)
        await FallingEdge(dut.clk_i)

    assert transfers["tx"] == accepted == 78
    assert stalls["tx"] == 52
    monitor.cancel()
    # Reset is allowed to replace a stalled payload; do not monitor across it.
    dut.ready_i.value = 0
    dut.rst_ni.value = 0
    await RisingEdge(dut.clk_i)
    await Timer(1, unit="ns")
    assert int(dut.data_o.value) == ord("A")
