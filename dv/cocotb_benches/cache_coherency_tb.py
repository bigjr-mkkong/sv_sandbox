from dataclasses import dataclass

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from dv.cocotb_benches.MESI_protocol_tb import (
    BUS_NOP,
    COH_EXCLUSIVE,
    COH_INVALID,
    COH_MODIFIED,
    MESI_TABLE,
)


CLOCK_PERIOD_NS = 10
TEST_TIMEOUT_US = 100


async def settle():
    await Timer(1, unit="ns")


@dataclass(frozen=True)
class LocalRequest:
    is_hit: bool
    state: int
    is_write: bool
    address: int


class CacheCoherencyTB:
    """Cache-side driver backed by the wrapper's pseudo coherence bus."""

    def __init__(self, dut):
        self.dut = dut
        cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())

    async def reset(self):
        self.dut.req_val_i.value = 0
        self.dut.req_is_write_i.value = 0
        self.dut.req_is_hit_i.value = 0
        self.dut.req_addr_i.value = 0
        self.dut.req_coh_i.value = COH_INVALID
        self.dut.rsp_rdy_i.value = 0
        self.dut.bus_rsp_delay_cycles.value = 0
        self.dut.bus_rsp_shared.value = 0

        self.dut.rst_ni.value = 0
        for _ in range(3):
            await RisingEdge(self.dut.clk_i)
        await FallingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await settle()

    def configure_bus(self, *, delay_cycles, shared):
        assert 0 <= delay_cycles <= 255
        self.dut.bus_rsp_delay_cycles.value = delay_cycles
        self.dut.bus_rsp_shared.value = int(shared)

    async def submit(self, request):
        self.dut.req_is_hit_i.value = int(request.is_hit)
        self.dut.req_coh_i.value = request.state
        self.dut.req_is_write_i.value = int(request.is_write)
        self.dut.req_addr_i.value = request.address
        self.dut.req_val_i.value = 1

        while True:
            await RisingEdge(self.dut.clk_i)
            if int(self.dut.req_rdy_o.value):
                break

        self.dut.req_val_i.value = 0
        self.dut.req_is_hit_i.value = 0
        self.dut.req_coh_i.value = COH_INVALID
        self.dut.req_is_write_i.value = 0
        self.dut.req_addr_i.value = 0
        await settle()

        assert int(self.dut.req_rdy_o.value) == 0

    def assert_bus_request(self, expected_op, expected_address):
        assert int(self.dut.coh_bus_req_val_o.value) == 1
        assert int(self.dut.coh_bus_req_op_o.value) == expected_op
        assert int(self.dut.coh_bus_req_addr_o.value) == expected_address

    async def receive_response(self, expected_state, *, hold_cycles=2):
        while not int(self.dut.rsp_val_o.value):
            await RisingEdge(self.dut.clk_i)
            await settle()

        for _ in range(hold_cycles):
            assert int(self.dut.rsp_val_o.value) == 1
            assert int(self.dut.new_coh_state_o.value) == expected_state
            await RisingEdge(self.dut.clk_i)
            await settle()

        self.dut.rsp_rdy_i.value = 1
        await RisingEdge(self.dut.clk_i)
        self.dut.rsp_rdy_i.value = 0
        await settle()

        assert int(self.dut.rsp_val_o.value) == 0
        assert int(self.dut.req_rdy_o.value) == 1

    async def check_transition(self, request, *, shared, delay_cycles):
        effective_state = request.state if request.is_hit else COH_INVALID
        expected_op, expected_no_shared, expected_shared = MESI_TABLE[
            (effective_state, request.is_write)
        ]
        expected_state = expected_shared if shared else expected_no_shared

        self.configure_bus(delay_cycles=delay_cycles, shared=shared)
        await self.submit(request)

        if expected_op == BUS_NOP:
            assert int(self.dut.coh_bus_req_val_o.value) == 0
        else:
            self.assert_bus_request(expected_op, request.address)

        await self.receive_response(expected_state)


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def upstream_request_holds_valid_until_ready(dut):
    """Hold a second request stable while the blocking controller is busy."""
    tb = CacheCoherencyTB(dut)
    await tb.reset()

    first_request = LocalRequest(
        is_hit=True,
        state=COH_MODIFIED,
        is_write=False,
        address=0x4000,
    )
    second_request = LocalRequest(
        is_hit=True,
        state=COH_EXCLUSIVE,
        is_write=True,
        address=0x4040,
    )

    await tb.submit(first_request)
    assert int(dut.rsp_val_o.value) == 1

    second_submit = cocotb.start_soon(tb.submit(second_request))
    await FallingEdge(dut.clk_i)

    for _ in range(3):
        assert int(dut.req_val_i.value) == 1
        assert int(dut.req_is_hit_i.value) == int(second_request.is_hit)
        assert int(dut.req_coh_i.value) == second_request.state
        assert int(dut.req_is_write_i.value) == int(second_request.is_write)
        assert int(dut.req_addr_i.value) == second_request.address
        assert int(dut.req_rdy_o.value) == 0
        await RisingEdge(dut.clk_i)
        await settle()

    await tb.receive_response(COH_MODIFIED, hold_cycles=0)
    await second_submit
    await tb.receive_response(COH_MODIFIED)


def transition_cases(*, uses_bus):
    """Generate the exhaustive local MESI cases for one datapath class."""
    cases = []
    case_index = 0
    for is_hit in (False, True):
        for state in range(4):
            for is_write in (False, True):
                effective_state = state if is_hit else COH_INVALID
                expected_op = MESI_TABLE[(effective_state, is_write)][0]
                if (expected_op != BUS_NOP) != uses_bus:
                    continue

                shared_values = (False, True) if uses_bus else (False,)
                for shared in shared_values:
                    request = LocalRequest(
                        is_hit=is_hit,
                        state=state,
                        is_write=is_write,
                        address=0x1000 + case_index * 0x40,
                    )
                    cases.append((request, shared))
                    case_index += 1
    return cases


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def no_bus_transitions_match_mesi_table(dut):
    """Verify all MESI transitions that complete without a bus operation."""
    tb = CacheCoherencyTB(dut)
    await tb.reset()

    for case_index, (request, shared) in enumerate(
        transition_cases(uses_bus=False)
    ):
        await tb.check_transition(
            request,
            shared=shared,
            delay_cycles=(case_index % 4) + 1,
        )


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def bus_transitions_match_mesi_table(dut):
    """Verify all bus-dependent MESI transitions for both shared replies."""
    tb = CacheCoherencyTB(dut)
    await tb.reset()

    for case_index, (request, shared) in enumerate(
        transition_cases(uses_bus=True)
    ):
        await tb.check_transition(
            request,
            shared=shared,
            delay_cycles=(case_index % 4) + 1,
        )


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def bus_delay_blocks_cache_response(dut):
    """Do not answer the cache until the configured bus delay has elapsed."""
    tb = CacheCoherencyTB(dut)
    await tb.reset()

    delay_cycles = 5
    request = LocalRequest(
        is_hit=False,
        state=COH_MODIFIED,
        is_write=False,
        address=0x8000,
    )
    expected_op, _, expected_state = MESI_TABLE[(COH_INVALID, False)]

    tb.configure_bus(delay_cycles=delay_cycles, shared=True)
    await tb.submit(request)
    tb.assert_bus_request(expected_op, request.address)

    # Accept the bus request, then observe every configured wait cycle.
    await RisingEdge(dut.clk_i)
    await settle()
    assert int(dut.bus_busy_o.value) == 1

    for _ in range(delay_cycles):
        await FallingEdge(dut.clk_i)
        assert int(dut.rsp_val_o.value) == 0

    await FallingEdge(dut.clk_i)
    assert int(dut.rsp_val_o.value) == 0
    assert int(dut.coh_bus_rsp_rdy_o.value) == 1

    await RisingEdge(dut.clk_i)
    await settle()
    assert int(dut.rsp_val_o.value) == 1
    await tb.receive_response(expected_state)


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def reset_cancels_inflight_bus_request(dut):
    """Reset clears both the local FSM and a pending pseudo-bus response."""
    tb = CacheCoherencyTB(dut)
    await tb.reset()

    request = LocalRequest(
        is_hit=False,
        state=COH_INVALID,
        is_write=False,
        address=0xC000,
    )
    tb.configure_bus(delay_cycles=16, shared=True)
    await tb.submit(request)
    tb.assert_bus_request(MESI_TABLE[(COH_INVALID, False)][0], request.address)

    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    await settle()
    assert int(dut.bus_busy_o.value) == 1
    assert int(dut.rsp_val_o.value) == 0

    await tb.reset()

    assert int(dut.bus_busy_o.value) == 0
    assert int(dut.coh_bus_req_val_o.value) == 0
    assert int(dut.rsp_val_o.value) == 0
    assert int(dut.req_rdy_o.value) == 1
    assert int(dut.new_coh_state_o.value) == COH_INVALID

    recovery_request = LocalRequest(
        is_hit=True,
        state=COH_MODIFIED,
        is_write=False,
        address=0xC040,
    )
    await tb.check_transition(
        recovery_request,
        shared=False,
        delay_cycles=0,
    )
