import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from dv.cocotb_benches.MESI_protocol_tb import (
    BUS_NOP,
    COH_INVALID,
    MESI_TABLE,
)


CLOCK_PERIOD_NS = 10
TEST_TIMEOUT_US = 100


async def settle():
    await Timer(1, unit="ns")


async def reset(dut):
    dut.req_val_i.value = 0
    dut.req_is_write_i.value = 0
    dut.req_is_hit_i.value = 0
    dut.req_addr_i.value = 0
    dut.req_coh_i.value = COH_INVALID
    dut.rsp_rdy_i.value = 0
    dut.coh_bus_req_rdy_i.value = 0
    dut.coh_bus_rsp_val_i.value = 0
    dut.coh_bus_shared_i.value = 0

    dut.rst_ni.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    await RisingEdge(dut.clk_i)
    await settle()


async def run_scenario(dut, *, is_hit, state, is_write, shared, address):
    effective_state = state if is_hit else COH_INVALID
    expected_op, expected_no_shared, expected_shared = MESI_TABLE[
        (effective_state, is_write)
    ]
    expected_state = expected_shared if shared else expected_no_shared

    assert dut.req_rdy_o.value == 1
    dut.req_is_hit_i.value = int(is_hit)
    dut.req_coh_i.value = state
    dut.req_is_write_i.value = int(is_write)
    dut.req_addr_i.value = address
    dut.req_val_i.value = 1

    await RisingEdge(dut.clk_i)
    dut.req_val_i.value = 0
    dut.req_is_hit_i.value = 0
    dut.req_coh_i.value = COH_INVALID
    dut.req_is_write_i.value = 0
    dut.req_addr_i.value = 0
    await settle()

    assert dut.req_rdy_o.value == 0

    if expected_op == BUS_NOP:
        assert dut.coh_bus_req_val_o.value == 0
    else:
        # Backpressure must not change or drop the bus request.
        for _ in range(2):
            assert dut.coh_bus_req_val_o.value == 1
            assert int(dut.coh_bus_req_op_o.value) == expected_op
            assert int(dut.coh_bus_req_addr_o.value) == address
            await RisingEdge(dut.clk_i)
            await settle()

        dut.coh_bus_req_rdy_i.value = 1
        await RisingEdge(dut.clk_i)
        dut.coh_bus_req_rdy_i.value = 0
        await settle()

        assert dut.coh_bus_req_val_o.value == 0
        assert dut.coh_bus_rsp_rdy_o.value == 1

        dut.coh_bus_shared_i.value = shared
        dut.coh_bus_rsp_val_i.value = 1
        await RisingEdge(dut.clk_i)
        dut.coh_bus_rsp_val_i.value = 0
        await settle()

    # Backpressure must hold the cache-side response and resulting MESI state.
    for _ in range(2):
        assert dut.rsp_val_o.value == 1
        assert int(dut.new_coh_state_o.value) == expected_state
        await RisingEdge(dut.clk_i)
        await settle()

    dut.rsp_rdy_i.value = 1
    await RisingEdge(dut.clk_i)
    dut.rsp_rdy_i.value = 0
    await settle()

    assert dut.rsp_val_o.value == 0
    assert dut.req_rdy_o.value == 1


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def local_controller_matches_mesi_table(dut):
    """Exercise reads/writes, hits/misses, every state, and snoop outcomes."""
    cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    scenario_index = 0
    for is_hit in (False, True):
        for state in range(4):
            for is_write in (False, True):
                effective_state = state if is_hit else COH_INVALID
                expected_op = MESI_TABLE[(effective_state, is_write)][0]
                shared_values = (False,) if expected_op == BUS_NOP else (False, True)

                for shared in shared_values:
                    await run_scenario(
                        dut,
                        is_hit=is_hit,
                        state=state,
                        is_write=is_write,
                        shared=shared,
                        address=0x1000 + scenario_index * 0x40,
                    )
                    scenario_index += 1
