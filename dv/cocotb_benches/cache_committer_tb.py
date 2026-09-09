import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer


CLOCK_PERIOD_NS = 10
COH_MODIFIED = 0
COH_EXCLUSIVE = 1
COH_SHARED = 2
COH_INVALID = 3


def cache_line(seed):
    value = 0
    for word in range(8):
        value |= ((seed + word) & ((1 << 64) - 1)) << (word * 64)
    return value


def clear_inputs(dut):
    dut.coh_probe_idx_i.value = 0
    for prefix in ("remote", "main"):
        getattr(dut, f"{prefix}_commit_val_i").value = 0
        getattr(dut, f"{prefix}_commit_index_i").value = 0
        getattr(dut, f"{prefix}_commit_coh_i").value = COH_INVALID
        getattr(dut, f"{prefix}_commit_tag_we_i").value = 0
        getattr(dut, f"{prefix}_commit_tag_i").value = 0
        getattr(dut, f"{prefix}_commit_data_we_i").value = 0
        getattr(dut, f"{prefix}_commit_data_i").value = 0
        getattr(dut, f"{prefix}_snoop_req_val_i").value = 0
        getattr(dut, f"{prefix}_snoop_idx_i").value = 0
        getattr(dut, f"{prefix}_snoop_tag_i").value = 0
        getattr(dut, f"{prefix}_snoop_rsp_rdy_i").value = 0


async def reset(dut):
    clear_inputs(dut)
    dut.rst_ni.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    for _ in range(257):
        await FallingEdge(dut.clk_i)
        if int(dut.reset_fin_o.value):
            await RisingEdge(dut.clk_i)
            return
    raise AssertionError("coherence initialization did not finish")


def drive_commit(dut, prefix, *, index, coh, tag_we=False, tag=0,
                 data_we=False, data=0):
    getattr(dut, f"{prefix}_commit_index_i").value = index
    getattr(dut, f"{prefix}_commit_coh_i").value = coh
    getattr(dut, f"{prefix}_commit_tag_we_i").value = int(tag_we)
    getattr(dut, f"{prefix}_commit_tag_i").value = tag
    getattr(dut, f"{prefix}_commit_data_we_i").value = int(data_we)
    getattr(dut, f"{prefix}_commit_data_i").value = data
    getattr(dut, f"{prefix}_commit_val_i").value = 1


async def send_commit(dut, prefix, **payload):
    """Drive before waiting; sample ready at the edge that executes the write."""
    drive_commit(dut, prefix, **payload)
    ready = getattr(dut, f"{prefix}_commit_rdy_o")
    for _ in range(40):
        await RisingEdge(dut.clk_i)
        if int(ready.value):
            getattr(dut, f"{prefix}_commit_val_i").value = 0
            return
    raise AssertionError(f"{prefix} write was not executed")


def drive_snoop(dut, prefix, *, index, tag):
    getattr(dut, f"{prefix}_snoop_idx_i").value = index
    getattr(dut, f"{prefix}_snoop_tag_i").value = tag
    getattr(dut, f"{prefix}_snoop_req_val_i").value = 1


async def send_snoop(dut, prefix, *, index, tag):
    """Observe the first eligible rising edge, regardless of the caller's phase."""
    drive_snoop(dut, prefix, index=index, tag=tag)
    ready = getattr(dut, f"{prefix}_snoop_req_rdy_o")
    for _ in range(40):
        await RisingEdge(dut.clk_i)
        if int(ready.value):
            getattr(dut, f"{prefix}_snoop_req_val_i").value = 0
            return
    raise AssertionError(f"{prefix} lookup was not accepted")


def read_response(dut, prefix):
    return {
        "tag": int(getattr(dut, f"{prefix}_snoop_rsp_tag_o").value),
        "hit": int(getattr(dut, f"{prefix}_snoop_rsp_hit_o").value),
        "coh": int(getattr(dut, f"{prefix}_snoop_rsp_coh_o").value),
        "data": int(getattr(dut, f"{prefix}_snoop_rsp_data_o").value),
    }


async def wait_response(dut, prefix):
    valid = getattr(dut, f"{prefix}_snoop_rsp_val_o")
    ready = getattr(dut, f"{prefix}_snoop_rsp_rdy_i")
    ready.value = 1
    for _ in range(40):
        await RisingEdge(dut.clk_i)
        if int(valid.value):
            response = read_response(dut, prefix)
            ready.value = 0
            return response
    ready.value = 0
    raise AssertionError(f"{prefix} lookup response timed out")


def assert_response(response, *, tag, hit, coh, data):
    assert response == {"tag": tag, "hit": hit, "coh": coh, "data": data}


def assert_pseudo_cache(dut, row, *, tag, coh, data):
    raw = int(dut.dut.pseudo_cache[row].value)
    assert raw == (coh << (512 + 50)) | (tag << 512) | data


@cocotb.test()
async def helpers_handshake_once_from_any_clock_phase(dut):
    """Neither delayed sampling nor a held response may lose/duplicate transfers."""
    cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())
    await reset(dut)
    counts = {prefix: [0, 0, 0] for prefix in ("remote", "main")}

    async def count_handshakes():
        while True:
            await RisingEdge(dut.clk_i)
            for prefix in counts:
                for channel, (valid, ready) in enumerate((
                    ("commit_val_i", "commit_rdy_o"),
                    ("snoop_req_val_i", "snoop_req_rdy_o"),
                    ("snoop_rsp_val_o", "snoop_rsp_rdy_i"),
                )):
                    if (int(getattr(dut, f"{prefix}_{valid}").value)
                            and int(getattr(dut, f"{prefix}_{ready}").value)):
                        counts[prefix][channel] += 1

    monitor = cocotb.start_soon(count_handshakes())
    for prefix in counts:
        for sequence, offset in enumerate((0, 1, 4, 5, 9), start=1):
            await RisingEdge(dut.clk_i)
            if offset:
                await Timer(offset, unit="ns")
            data = cache_line(sequence * 0x100)
            await send_commit(
                dut, prefix, index=sequence, coh=COH_MODIFIED,
                tag_we=True, tag=sequence, data_we=True, data=data,
            )
            await RisingEdge(dut.clk_i)
            if offset:
                await Timer(offset, unit="ns")
            await send_snoop(dut, prefix, index=sequence, tag=sequence)
            # Let valid arrive while ready is low, then consume at each phase.
            for _ in range(3):
                await RisingEdge(dut.clk_i)
            if offset:
                await Timer(offset, unit="ns")
            assert_response(
                await wait_response(dut, prefix),
                tag=sequence, hit=1, coh=COH_MODIFIED, data=data,
            )
            await Timer(1, unit="ns")
            assert counts[prefix] == [sequence] * 3
    monitor.cancel()


@cocotb.test()
async def reset_sweep_blocks_all_ports_and_restarts(dut):
    """A warm reset clears every row before pending traffic can execute."""
    cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())
    await reset(dut)
    for row in (0, 255):
        await send_commit(dut, "main", index=row, coh=COH_MODIFIED)

    # Interrupt the first sweep, then verify a complete sweep from row zero.
    for cycles in (17, 256):
        await FallingEdge(dut.clk_i)
        dut.rst_ni.value = 0
        for prefix in ("remote", "main"):
            drive_commit(dut, prefix, index=255, coh=COH_MODIFIED)
            drive_snoop(dut, prefix, index=255, tag=0)
        await RisingEdge(dut.clk_i)
        await FallingEdge(dut.clk_i)
        dut.rst_ni.value = 1
        await Timer(1, unit="ns")
        for _ in range(cycles):
            assert not int(dut.reset_fin_o.value)
            assert int(dut.coh_probe_o.value) == COH_INVALID
            for prefix in ("remote", "main"):
                assert not int(getattr(dut, f"{prefix}_commit_rdy_o").value)
                assert not int(getattr(dut, f"{prefix}_snoop_req_rdy_o").value)
                assert not int(getattr(dut, f"{prefix}_snoop_rsp_val_o").value)
            await RisingEdge(dut.clk_i)
            await FallingEdge(dut.clk_i)
        assert bool(dut.reset_fin_o.value) == (cycles == 256)

    # The final reset edge clears row 255; it must not execute a pending write.
    clear_inputs(dut)
    for row in range(256):
        dut.coh_probe_idx_i.value = row
        await Timer(1, unit="ns")
        assert int(dut.coh_probe_o.value) == COH_INVALID


@cocotb.test()
async def banked_storage_live_coherence_and_raw_victim(dut):
    """Exercise both depth banks and coherence-only execution-ready writes."""
    cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())
    await reset(dut)
    await FallingEdge(dut.clk_i)
    for row in range(256):
        assert_pseudo_cache(dut, row, tag=0, coh=COH_INVALID, data=0)

    entries = (
        (0x22, 0x44, COH_MODIFIED, cache_line(0x1000)),
        (0x23, 0x55, COH_EXCLUSIVE, cache_line(0x2000)),
    )
    for row, tag, coh, data in entries:
        await send_commit(
            dut, "main", index=row, coh=coh, tag_we=True, tag=tag,
            data_we=True, data=data,
        )

    for row, tag, coh, data in entries:
        await send_snoop(dut, "main", index=row, tag=tag)
        assert_response(
            await wait_response(dut, "main"),
            tag=tag, hit=1, coh=coh, data=data,
        )
        assert_pseudo_cache(dut, row, tag=tag, coh=coh, data=data)

    row, tag, _, data = entries[0]
    await send_snoop(dut, "main", index=row, tag=tag + 1)
    assert_response(
        await wait_response(dut, "main"),
        tag=tag, hit=0, coh=COH_MODIFIED, data=data,
    )

    await send_commit(dut, "remote", index=row, coh=COH_SHARED)
    dut.coh_probe_idx_i.value = row
    await FallingEdge(dut.clk_i)
    assert int(dut.coh_probe_o.value) == COH_SHARED
    await send_snoop(dut, "remote", index=row, tag=tag)
    assert_response(
        await wait_response(dut, "remote"),
        tag=tag, hit=1, coh=COH_SHARED, data=data,
    )
    assert_pseudo_cache(dut, row, tag=tag, coh=COH_SHARED, data=data)

    # Independently enabled tag/data writes must preserve the other fields.
    for tag_we, data_we in ((True, False), (False, True)):
        tag += int(tag_we)
        if data_we:
            data = cache_line(0x5000)
        await send_commit(
            dut, "main", index=row, coh=COH_MODIFIED,
            tag_we=tag_we, tag=tag, data_we=data_we, data=data,
        )
        await send_snoop(dut, "main", index=row, tag=tag)
        assert_response(
            await wait_response(dut, "main"),
            tag=tag, hit=1, coh=COH_MODIFIED, data=data,
        )
        assert_pseudo_cache(dut, row, tag=tag, coh=COH_MODIFIED, data=data)
        other_row, other_tag, other_coh, other_data = entries[1]
        assert_pseudo_cache(
            dut, other_row, tag=other_tag, coh=other_coh, data=other_data,
        )


@cocotb.test()
async def global_blocking_priority_and_held_response(dut):
    """Only the highest-priority operation executes and reads block the bank."""
    cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())
    await reset(dut)

    row = 0x31
    old_tag = 0x61
    new_tag = 0x72
    old_data = cache_line(0x3000)
    new_data = cache_line(0x4000)
    await send_commit(
        dut, "main", index=row, coh=COH_MODIFIED,
        tag_we=True, tag=old_tag, data_we=True, data=old_data,
    )

    drive_commit(dut, "remote", index=row, coh=COH_SHARED)
    drive_snoop(dut, "remote", index=row, tag=old_tag)
    drive_commit(
        dut, "main", index=row, coh=COH_EXCLUSIVE,
        tag_we=True, tag=new_tag, data_we=True, data=new_data,
    )
    drive_snoop(dut, "main", index=row, tag=old_tag)

    await FallingEdge(dut.clk_i)
    assert int(dut.remote_commit_rdy_o.value)
    assert not int(dut.remote_snoop_req_rdy_o.value)
    assert not int(dut.main_commit_rdy_o.value)
    assert not int(dut.main_snoop_req_rdy_o.value)
    await RisingEdge(dut.clk_i)
    dut.remote_commit_val_i.value = 0

    await FallingEdge(dut.clk_i)
    assert int(dut.remote_snoop_req_rdy_o.value)
    assert not int(dut.main_commit_rdy_o.value)
    assert not int(dut.main_snoop_req_rdy_o.value)
    await RisingEdge(dut.clk_i)
    dut.remote_snoop_req_val_i.value = 0

    while not int(dut.remote_snoop_rsp_val_o.value):
        await FallingEdge(dut.clk_i)
    held = read_response(dut, "remote")
    assert_response(
        held, tag=old_tag, hit=1, coh=COH_SHARED, data=old_data
    )
    for _ in range(3):
        assert not int(dut.main_commit_rdy_o.value)
        assert not int(dut.main_snoop_req_rdy_o.value)
        assert_pseudo_cache(
            dut, row, tag=old_tag, coh=COH_SHARED, data=old_data,
        )
        await RisingEdge(dut.clk_i)
        await FallingEdge(dut.clk_i)
        assert read_response(dut, "remote") == held

    dut.remote_snoop_rsp_rdy_i.value = 1
    await RisingEdge(dut.clk_i)
    dut.remote_snoop_rsp_rdy_i.value = 0

    await FallingEdge(dut.clk_i)
    assert int(dut.main_commit_rdy_o.value)
    assert not int(dut.main_snoop_req_rdy_o.value)
    await RisingEdge(dut.clk_i)
    dut.main_commit_val_i.value = 0

    await FallingEdge(dut.clk_i)
    assert int(dut.main_snoop_req_rdy_o.value)
    await RisingEdge(dut.clk_i)
    dut.main_snoop_req_val_i.value = 0
    assert_response(
        await wait_response(dut, "main"),
        tag=new_tag, hit=0, coh=COH_EXCLUSIVE, data=new_data,
    )
    assert_pseudo_cache(
        dut, row, tag=new_tag, coh=COH_EXCLUSIVE, data=new_data,
    )
