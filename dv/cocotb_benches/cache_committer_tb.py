import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


CLOCK_PERIOD_NS = 10
COH_MODIFIED = 0
COH_EXCLUSIVE = 1
COH_SHARED = 2
COH_INVALID = 3


async def settle():
    await Timer(1, unit="ns")


async def reset(dut):
    for prefix in ("remote", "main"):
        getattr(dut, f"{prefix}_commit_val_i").value = 0
        getattr(dut, f"{prefix}_commit_index_i").value = 0
        getattr(dut, f"{prefix}_commit_coh_i").value = COH_INVALID
        getattr(dut, f"{prefix}_commit_tag_we_i").value = 0
        getattr(dut, f"{prefix}_commit_tag_i").value = 0
        getattr(dut, f"{prefix}_commit_data_we_i").value = 0
        getattr(dut, f"{prefix}_commit_data_i").value = 0

    dut.main_lookup_idx_i.value = 0
    dut.main_lookup_tag_i.value = 0
    dut.snoop_lookup_idx_i.value = 0
    dut.snoop_lookup_tag_i.value = 0
    dut.rst_ni.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    await RisingEdge(dut.clk_i)
    await settle()


def drive_commit(
    dut,
    prefix,
    *,
    index,
    coh,
    tag_we=False,
    tag=0,
    data_we=False,
    data=0,
):
    getattr(dut, f"{prefix}_commit_index_i").value = index
    getattr(dut, f"{prefix}_commit_coh_i").value = coh
    getattr(dut, f"{prefix}_commit_tag_we_i").value = int(tag_we)
    getattr(dut, f"{prefix}_commit_tag_i").value = tag
    getattr(dut, f"{prefix}_commit_data_we_i").value = int(data_we)
    getattr(dut, f"{prefix}_commit_data_i").value = data
    getattr(dut, f"{prefix}_commit_val_i").value = 1


async def accept_main(dut, **payload):
    drive_commit(dut, "main", **payload)
    await settle()
    assert dut.main_commit_rdy_o.value
    await RisingEdge(dut.clk_i)
    dut.main_commit_val_i.value = 0
    await settle()


def select_main(dut, index, tag):
    dut.main_lookup_idx_i.value = index
    dut.main_lookup_tag_i.value = tag


def assert_main_lookup(dut, *, hit, coh, tag, data):
    assert int(dut.main_lookup_result_hit_o.value) == hit
    assert int(dut.main_lookup_result_coh_o.value) == coh
    assert int(dut.main_lookup_result_tag_o.value) == tag
    assert int(dut.main_lookup_result_data_o.value) == data


@cocotb.test()
async def cache_commit_dual_port_contract(dut):
    """Check reset, unconditional readiness, lookups, and dual-row writes."""
    cocotb.start_soon(
        Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start()
    )
    await reset(dut)

    select_main(dut, index=0, tag=0)
    await settle()
    assert not dut.main_lookup_result_hit_o.value
    assert int(dut.main_lookup_result_coh_o.value) == COH_INVALID

    await accept_main(
        dut,
        index=1,
        coh=COH_MODIFIED,
        tag_we=True,
        tag=0xA,
        data_we=True,
        data=0x1234,
    )
    select_main(dut, index=1, tag=0xA)
    await settle()
    assert_main_lookup(
        dut, hit=1, coh=COH_MODIFIED, tag=0xA, data=0x1234
    )

    # Activity on the remote port must not backpressure the independent main
    # port. Do not assert main valid here: equal-row dual writes are illegal at
    # this bank boundary and are checked by an RTL assertion.
    drive_commit(dut, "remote", index=1, coh=COH_INVALID)
    dut.main_commit_index_i.value = 1
    await settle()
    assert dut.remote_commit_rdy_o.value
    assert dut.main_commit_rdy_o.value
    await RisingEdge(dut.clk_i)
    dut.remote_commit_val_i.value = 0
    await settle()
    assert int(dut.main_lookup_result_coh_o.value) == COH_INVALID

    # A remote update to row 1 and a main update to row 2 both commit on the
    # same edge. Exercise the symmetric tag/data payload on both inputs.
    drive_commit(
        dut,
        "remote",
        index=1,
        coh=COH_SHARED,
        tag_we=True,
        tag=0xC,
        data_we=True,
        data=0x9ABC,
    )
    drive_commit(
        dut,
        "main",
        index=2,
        coh=COH_MODIFIED,
        tag_we=True,
        tag=0xD,
        data_we=True,
        data=0xDEF0,
    )
    await settle()
    assert dut.remote_commit_rdy_o.value
    assert dut.main_commit_rdy_o.value
    await RisingEdge(dut.clk_i)
    dut.remote_commit_val_i.value = 0
    dut.main_commit_val_i.value = 0
    await settle()

    select_main(dut, index=1, tag=0xC)
    await settle()
    assert_main_lookup(dut, hit=1, coh=COH_SHARED, tag=0xC, data=0x9ABC)
    select_main(dut, index=2, tag=0xD)
    await settle()
    assert_main_lookup(
        dut, hit=1, coh=COH_MODIFIED, tag=0xD, data=0xDEF0
    )

    dut.snoop_lookup_idx_i.value = 2
    dut.snoop_lookup_tag_i.value = 0xD
    await settle()
    assert dut.snoop_lookup_result_hit_o.value
    assert int(dut.snoop_lookup_result_coh_o.value) == COH_MODIFIED
    assert int(dut.snoop_lookup_result_data_o.value) == 0xDEF0
