import cocotb
from cocotb.triggers import Timer


COH_MODIFIED = 0
COH_EXCLUSIVE = 1
COH_SHARED = 2
COH_INVALID = 3

BUS_NOP = 0
BUS_RD = 1
BUS_RDX = 2
BUS_UPGR = 3

MESI_TABLE = {
    (COH_INVALID, False): (BUS_RD, COH_EXCLUSIVE, COH_SHARED),
    (COH_INVALID, True): (BUS_RDX, COH_MODIFIED, COH_MODIFIED),
    (COH_SHARED, False): (BUS_NOP, COH_SHARED, COH_SHARED),
    (COH_SHARED, True): (BUS_UPGR, COH_MODIFIED, COH_MODIFIED),
    (COH_EXCLUSIVE, False): (BUS_NOP, COH_EXCLUSIVE, COH_EXCLUSIVE),
    (COH_EXCLUSIVE, True): (BUS_NOP, COH_MODIFIED, COH_MODIFIED),
    (COH_MODIFIED, False): (BUS_NOP, COH_MODIFIED, COH_MODIFIED),
    (COH_MODIFIED, True): (BUS_NOP, COH_MODIFIED, COH_MODIFIED),
}


@cocotb.test()
async def all_mesi_table_entries_match(dut):
    """Check every state/CPU-operation row and both shared outcomes."""
    dut.begin_judge.value = 0
    dut.req_is_write_i.value = 0
    dut.current_coh_i.value = COH_INVALID
    await Timer(1, unit="ns")

    assert int(dut.coh_bus_op_o.value) == BUS_NOP
    assert int(dut.next_coh_no_shared_o.value) == COH_INVALID
    assert int(dut.next_coh_shared_o.value) == COH_INVALID

    dut.begin_judge.value = 1
    for (state, is_write), expected in MESI_TABLE.items():
        expected_op, expected_no_shared, expected_shared = expected
        dut.current_coh_i.value = state
        dut.req_is_write_i.value = int(is_write)
        await Timer(1, unit="ns")

        assert int(dut.coh_bus_op_o.value) == expected_op
        assert int(dut.next_coh_no_shared_o.value) == expected_no_shared
        assert int(dut.next_coh_shared_o.value) == expected_shared
