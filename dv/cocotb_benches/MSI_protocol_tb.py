import cocotb
from cocotb.triggers import Timer

from dv.cocotb_benches.MESI_protocol_tb import (
    BUS_NOP,
    BUS_RD,
    BUS_RDX,
    BUS_UPGR,
    COH_EXCLUSIVE,
    COH_INVALID,
    COH_MODIFIED,
    COH_SHARED,
)


MSI_TABLE = {
    (COH_INVALID, False): (BUS_RD, COH_SHARED),
    (COH_INVALID, True): (BUS_RDX, COH_MODIFIED),
    (COH_SHARED, False): (BUS_NOP, COH_SHARED),
    (COH_SHARED, True): (BUS_UPGR, COH_MODIFIED),
    (COH_MODIFIED, False): (BUS_NOP, COH_MODIFIED),
    (COH_MODIFIED, True): (BUS_NOP, COH_MODIFIED),
}


@cocotb.test()
async def all_msi_table_entries_match(dut):
    """Check all six transitions, both candidates, and disabled defaults."""
    for (state, is_write), (expected_op, expected_state) in MSI_TABLE.items():
        # Disable after every decision too, to catch stale combinational outputs.
        for enabled in (True, False):
            dut.begin_judge.value = int(enabled)
            dut.current_coh_i.value = state
            dut.req_is_write_i.value = int(is_write)
            await Timer(1, unit="ns")

            assert int(dut.coh_bus_op_o.value) == (
                expected_op if enabled else BUS_NOP
            )
            for output in (dut.next_coh_no_shared_o, dut.next_coh_shared_o):
                assert int(output.value) == (
                    expected_state if enabled else COH_INVALID
                )

    # E is illegal for an active MSI decision, but ignored while disabled.
    dut.current_coh_i.value = COH_EXCLUSIVE
    for is_write in (False, True):
        dut.req_is_write_i.value = int(is_write)
        await Timer(1, unit="ns")
        assert int(dut.coh_bus_op_o.value) == BUS_NOP
        assert int(dut.next_coh_no_shared_o.value) == COH_INVALID
        assert int(dut.next_coh_shared_o.value) == COH_INVALID
