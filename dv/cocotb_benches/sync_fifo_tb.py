"""Check FIFO ordering, limits, pointer wraparound, and direct bypass."""

from collections import deque
import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer


@cocotb.test(timeout_time=50, timeout_unit="us")
async def fifo_requests(dut):
    depth = int(os.environ.get("FIFO_DEPTH", "16"))
    mask = (1 << len(dut.push_req_data_i)) - 1
    queue = deque()
    output = 0
    dut.rst_ni.value = 0
    dut.push_req_val_i.value = 0
    dut.pop_req_val_i.value = 0
    dut.push_req_data_i.value = 0
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())

    async def reset():
        nonlocal output
        await FallingEdge(dut.clk_i)
        dut.rst_ni.value = 0
        dut.push_req_val_i.value = 0
        dut.pop_req_val_i.value = 0
        await Timer(1, unit="ns")
        assert int(dut.pop_req_data_o.value) == 0
        await FallingEdge(dut.clk_i)
        dut.rst_ni.value = 1
        queue.clear()
        output = 0

    async def cycle(push=False, pop=False, data=0):
        nonlocal output
        await FallingEdge(dut.clk_i)
        dut.push_req_val_i.value = push
        dut.pop_req_val_i.value = pop
        dut.push_req_data_i.value = data & mask
        await Timer(1, unit="ns")
        assert dut.push_req_rdy_o.value == 1
        assert dut.pop_req_rdy_o.value == 1
        assert int(dut.push_erm_o.value) == (push and not pop and len(queue) == depth)
        assert int(dut.pop_erm_o.value) == (pop and not push and not queue)
        if push and pop:
            output = data & mask
        elif push and len(queue) < depth:
            queue.append(data & mask)
        elif pop and queue:
            output = queue.popleft()
        await RisingEdge(dut.clk_i)
        await Timer(1, unit="ns")
        assert int(dut.pop_req_data_o.value) == output

    await reset()
    await cycle(push=True, data=0xDEADBEEF)
    await cycle()  # Idle must not repeat the preceding request.
    await cycle(pop=True)
    await cycle(pop=True)  # Underflow.
    await cycle()
    await cycle(push=True, pop=True, data=0x87654321)  # Empty bypass.
    await cycle(pop=True)  # Bypass must not enqueue anything.

    for _ in range(3):
        for index in range(depth):
            await cycle(push=True, data=0xA5000000 + index)
        await cycle(push=True, data=mask)  # Overflow must preserve contents.
        await cycle()
        await cycle(push=True, pop=True, data=0x12345678)  # Full bypass.
        await cycle(push=True)  # Still full.
        for _ in range(depth):
            await cycle(pop=True)
        await cycle(pop=True)

    await cycle(push=True, data=0xCAFEBABE)
    await cycle(push=True, pop=True, data=0x76543210)
    await cycle(pop=True)  # Queued data survives bypass.
    rng = random.Random(42)
    for _ in range(400):
        await cycle(bool(rng.getrandbits(1)), bool(rng.getrandbits(1)), rng.getrandbits(len(dut.push_req_data_i)))
    for _ in range(depth):
        await cycle(push=True, data=mask)
    await reset()  # Reset a full FIFO.
    await cycle(pop=True)
    await cycle(push=True, data=mask)
    await cycle(pop=True)
