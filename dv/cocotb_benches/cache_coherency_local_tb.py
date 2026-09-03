from dataclasses import dataclass

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from dv.cocotb_benches.MESI_protocol_tb import (
    BUS_NOP,
    COH_EXCLUSIVE,
    COH_INVALID,
    COH_MODIFIED,
    COH_SHARED,
    MESI_TABLE,
)


CLOCK_PERIOD_NS = 10
TEST_TIMEOUT_US = 100


async def settle():
    await Timer(1, unit="ns")


@dataclass(frozen=True)
class LocalRequest:
    is_hit: bool
    is_write: bool
    address: int


# MESI_expected is the "ground truth" of local state MESI statemachine
class MESI_expected:
    """Stateful MESI reference model indexed by cache-line address."""

    def __init__(self):
        self.reset()

    def reset(self):
        self._states = {}
        self._pending = None

    def state(self, address):
        return self._states.get(address, COH_INVALID)

    def submit_req(self, request, *, shared):
        assert self._pending is None
        effective_state = self.state(request.address) if request.is_hit else COH_INVALID
        bus_op, no_shared_state, shared_state = MESI_TABLE[
            (effective_state, request.is_write)
        ]
        final_state = shared_state if shared else no_shared_state
        self._pending = (
            request.address,
            effective_state,
            final_state,
            bus_op,
        )

    def expected(self):
        assert self._pending is not None
        _, _, final_state, bus_op = self._pending
        if bus_op == BUS_NOP:
            return (final_state,)
        return (final_state, bus_op)

    def commit_rsp(self, actual):
        expected = self.expected()
        assert actual[: len(expected)] == expected
        address, initial_state, final_state, _ = self._pending
        assert actual[2] == (final_state != initial_state)
        self._states[address] = final_state
        self._pending = None


class CacheCoherencyTB:
    """Cache-side driver backed by the wrapper's pseudo coherence bus."""

    def __init__(self, dut):
        self.dut = dut
        self.mesi_expected = MESI_expected()
        self._bus_shared = False
        self._captured_rsp = None
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
        self._bus_shared = False
        self._captured_rsp = None
        self.mesi_expected.reset()

        self.dut.rst_ni.value = 0
        for _ in range(3):
            await RisingEdge(self.dut.clk_i)
        await FallingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await settle()

    def configure_bus(self, *, delay_cycles, shared):
        assert 0 <= delay_cycles <= 255
        self._bus_shared = bool(shared)
        self.dut.bus_rsp_delay_cycles.value = delay_cycles
        self.dut.bus_rsp_shared.value = int(shared)

    async def submit_req(self, request):
        self.dut.req_is_hit_i.value = int(request.is_hit)
        self.dut.req_coh_i.value = self.mesi_expected.state(request.address)
        self.dut.req_is_write_i.value = int(request.is_write)
        self.dut.req_addr_i.value = request.address
        self.dut.req_val_i.value = 1

        while True:
            await settle()
            if int(self.dut.req_rdy_o.value):
                await RisingEdge(self.dut.clk_i)
                break
            await RisingEdge(self.dut.clk_i)

        self.dut.req_val_i.value = 0
        await settle()

        self.mesi_expected.submit_req(request, shared=self._bus_shared)
        assert int(self.dut.req_rdy_o.value) == 0

    async def wait_rsp(self):
        assert self._captured_rsp is None
        self.dut.rsp_rdy_i.value = 1
        while True:
            await settle()
            if int(self.dut.rsp_val_o.value):
                self._captured_rsp = (
                    int(self.dut.new_coh_state_o.value),
                    int(self.dut.bus_op_out_q.value),
                    bool(self.dut.local_coh_commit_o.value),
                )
                await RisingEdge(self.dut.clk_i)
                return
            await RisingEdge(self.dut.clk_i)

    def read_rsp(self):
        assert self._captured_rsp is not None
        response = self._captured_rsp
        self._captured_rsp = None
        self.dut.rsp_rdy_i.value = 0
        return response


async def complete_request(tb, request, *, shared=False, delay_cycles=0):
    tb.configure_bus(delay_cycles=delay_cycles, shared=shared)
    await tb.submit_req(request)
    await tb.wait_rsp()
    response = tb.read_rsp()
    tb.mesi_expected.commit_rsp(response)
    await settle()
    assert int(tb.dut.rsp_val_o.value) == 0
    assert int(tb.dut.req_rdy_o.value) == 1
    return response


async def prepare_state(tb, address, state):
    if state == COH_INVALID:
        return
    if state == COH_SHARED:
        request = LocalRequest(is_hit=False, is_write=False, address=address)
        await complete_request(tb, request, shared=True)
    elif state == COH_EXCLUSIVE:
        request = LocalRequest(is_hit=False, is_write=False, address=address)
        await complete_request(tb, request, shared=False)
    elif state == COH_MODIFIED:
        request = LocalRequest(is_hit=False, is_write=True, address=address)
        await complete_request(tb, request, shared=False)
    else:
        raise AssertionError(f"unsupported MESI state: {state}")
    assert tb.mesi_expected.state(address) == state


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def upstream_request_holds_valid_until_ready(dut):
    """Hold a second request stable while the blocking controller is busy."""
    tb = CacheCoherencyTB(dut)
    await tb.reset()

    first_address = 0x4000
    second_address = 0x4040
    await prepare_state(tb, first_address, COH_MODIFIED)
    await prepare_state(tb, second_address, COH_EXCLUSIVE)

    first_request = LocalRequest(is_hit=True, is_write=False, address=first_address)
    second_request = LocalRequest(is_hit=True, is_write=True, address=second_address)

    await tb.submit_req(first_request)
    assert int(dut.rsp_val_o.value) == 1

    second_submit = cocotb.start_soon(tb.submit_req(second_request))
    await FallingEdge(dut.clk_i)

    for _ in range(3):
        assert int(dut.req_val_i.value) == 1
        assert int(dut.req_is_hit_i.value) == int(second_request.is_hit)
        assert int(dut.req_coh_i.value) == COH_EXCLUSIVE
        assert int(dut.req_is_write_i.value) == int(second_request.is_write)
        assert int(dut.req_addr_i.value) == second_request.address
        assert int(dut.req_rdy_o.value) == 0
        await RisingEdge(dut.clk_i)
        await settle()

    await tb.wait_rsp()
    tb.mesi_expected.commit_rsp(tb.read_rsp())
    await second_submit
    await tb.wait_rsp()
    tb.mesi_expected.commit_rsp(tb.read_rsp())
    await settle()
    assert int(dut.req_rdy_o.value) == 1


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def no_bus_transitions_match_mesi_table(dut):
    """Reach S, E, and M naturally, then verify their BusNOP transitions."""
    tb = CacheCoherencyTB(dut)
    await tb.reset()

    cases = (
        (COH_SHARED, False),
        (COH_EXCLUSIVE, False),
        (COH_EXCLUSIVE, True),
        (COH_MODIFIED, False),
        (COH_MODIFIED, True),
    )
    for case_index, (initial_state, is_write) in enumerate(cases):
        address = 0x1000 + case_index * 0x40
        await prepare_state(tb, address, initial_state)
        request = LocalRequest(is_hit=True, is_write=is_write, address=address)
        await complete_request(tb, request, delay_cycles=(case_index % 4) + 1)


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def bus_transitions_match_mesi_table(dut):
    """Verify all bus-dependent transitions from naturally reached states."""
    tb = CacheCoherencyTB(dut)
    await tb.reset()

    cases = (
        (COH_INVALID, False, False),
        (COH_INVALID, False, True),
        (COH_INVALID, True, False),
        (COH_SHARED, True, False),
    )
    for case_index, (initial_state, is_write, shared) in enumerate(cases):
        address = 0x2000 + case_index * 0x40
        await prepare_state(tb, address, initial_state)
        request = LocalRequest(
            is_hit=initial_state != COH_INVALID,
            is_write=is_write,
            address=address,
        )
        await complete_request(
            tb,
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
        is_write=False,
        address=0x8000,
    )

    tb.configure_bus(delay_cycles=delay_cycles, shared=True)
    await tb.submit_req(request)

    # Accept the bus request, then observe every configured wait cycle.
    await RisingEdge(dut.clk_i)
    await settle()
    assert int(dut.bus_busy_o.value) == 1

    for _ in range(delay_cycles):
        await FallingEdge(dut.clk_i)
        assert int(dut.rsp_val_o.value) == 0
        assert int(dut.local_coh_commit_o.value) == 0

    await FallingEdge(dut.clk_i)
    assert int(dut.rsp_val_o.value) == 0
    assert int(dut.local_coh_commit_o.value) == 0
    assert int(dut.coh_bus_rsp_rdy_o.value) == 1

    await RisingEdge(dut.clk_i)
    await settle()
    assert int(dut.rsp_val_o.value) == 1
    await tb.wait_rsp()
    tb.mesi_expected.commit_rsp(tb.read_rsp())


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def reset_cancels_inflight_bus_request(dut):
    """Reset clears both the local FSM and a pending pseudo-bus response."""
    tb = CacheCoherencyTB(dut)
    await tb.reset()

    request = LocalRequest(
        is_hit=False,
        is_write=False,
        address=0xC000,
    )
    tb.configure_bus(delay_cycles=16, shared=True)
    await tb.submit_req(request)

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
        is_hit=False,
        is_write=True,
        address=0xC040,
    )
    await complete_request(tb, recovery_request)

@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def all_mesi_state_transitions_in_sequence(dut):
    """Exercise every MESI CPU transition through stateful request sequences."""
    tb = CacheCoherencyTB(dut)
    await tb.reset()

    shared_address = 0xD000
    await complete_request(
        tb,
        LocalRequest(is_hit=False, is_write=False, address=shared_address),
        shared=True,
    )
    assert tb.mesi_expected.state(shared_address) == COH_SHARED

    await complete_request(
        tb,
        LocalRequest(is_hit=True, is_write=False, address=shared_address),
    )
    assert tb.mesi_expected.state(shared_address) == COH_SHARED

    await complete_request(
        tb,
        LocalRequest(is_hit=True, is_write=True, address=shared_address),
    )
    assert tb.mesi_expected.state(shared_address) == COH_MODIFIED

    await complete_request(
        tb,
        LocalRequest(is_hit=True, is_write=False, address=shared_address),
    )
    assert tb.mesi_expected.state(shared_address) == COH_MODIFIED

    await complete_request(
        tb,
        LocalRequest(is_hit=True, is_write=True, address=shared_address),
    )
    assert tb.mesi_expected.state(shared_address) == COH_MODIFIED

    exclusive_address = 0xD040
    await complete_request(
        tb,
        LocalRequest(is_hit=False, is_write=False, address=exclusive_address),
        shared=False,
    )
    assert tb.mesi_expected.state(exclusive_address) == COH_EXCLUSIVE

    await complete_request(
        tb,
        LocalRequest(is_hit=True, is_write=False, address=exclusive_address),
    )
    assert tb.mesi_expected.state(exclusive_address) == COH_EXCLUSIVE

    await complete_request(
        tb,
        LocalRequest(is_hit=True, is_write=True, address=exclusive_address),
    )
    assert tb.mesi_expected.state(exclusive_address) == COH_MODIFIED

    modified_address = 0xD080
    await complete_request(
        tb,
        LocalRequest(is_hit=False, is_write=True, address=modified_address),
    )
    assert tb.mesi_expected.state(modified_address) == COH_MODIFIED
