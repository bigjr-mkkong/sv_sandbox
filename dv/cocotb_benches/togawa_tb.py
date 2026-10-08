"""Check TOGAWA against an interpreter with stalled, delayed cache ports."""

import random

import cocotb
from cocotb.triggers import Timer


def wa(address):
    assert 0 <= address <= 0xFFFE and address % 2 == 0
    return 0x8000 | (address >> 1)


def toga(bit, skip):
    assert 0 <= bit < 16 and -1024 <= skip <= 1023
    word = (bit << 11) | (skip & 0x7FF)
    assert word != 0, "bit 0 / skip 0 encodes HALT"
    return word


def interpret(program, initial_memory):
    memory = dict(initial_memory)
    transactions = []
    pc, address, value = 0, 0, 0
    dirty = False
    for _ in range(1000):
        word = program.get(pc, 0)
        if word == 0:
            if dirty:
                transactions.append((1, address, value))
                memory[address] = value
            return transactions, memory
        if word & 0x8000:
            if dirty:
                transactions.append((1, address, value))
                memory[address] = value
            address = (word & 0x7FFF) << 1
            transactions.append((0, address, None))
            value = memory.get(address, 0)
            dirty = False
            pc = (pc + 1) & 0xFFFF
        else:
            mask = 1 << (word >> 11)
            value ^= mask
            dirty = True
            skip = word & 0x7FF
            if skip & 0x400:
                skip -= 0x800
            pc = (pc + 1 + (0 if value & mask else skip)) & 0xFFFF
    raise AssertionError("reference program did not halt")


async def reset(dut):
    dut.clk_i.value = 0
    dut.rst_ni.value = 0
    dut.icache_req_rdy_i.value = 0
    dut.icache_val_i.value = 0
    dut.icache_inst_i.value = 0
    dut.dcache_req_rdy_i.value = 0
    dut.dcache_rsp_val_i.value = 0
    dut.dcache_rsp_data_i.value = 0
    for _ in range(2):
        await Timer(5, unit="ns")
        assert not dut.icache_req_val_o.value
        assert not dut.dcache_req_val_o.value
        dut.clk_i.value = 1
        await Timer(5, unit="ns")
        dut.clk_i.value = 0
    assert not dut.halt.value
    assert int(dut.pc_o.value) == 0
    dut.rst_ni.value = 1


async def run_program(dut, words, initial_memory, *, seed=0, fast=False,
                      abort_after=None):
    program = dict(enumerate(words)) if isinstance(words, list) else words
    expected_transactions, expected_memory = interpret(program, initial_memory)
    await reset(dut)
    rng = random.Random(seed)
    memory = dict(initial_memory)
    transactions, requests, responses = [], [], []
    pending_data = None
    lookup_pc, lookup_due = None, 0
    held_data = None
    instruction_stalls = data_stalls = 0

    for cycle in range(2000):
        dut.clk_i.value = 0
        current_pc = int(dut.pc_o.value)
        if current_pc != lookup_pc:
            lookup_pc = current_pc
            lookup_due = cycle + (0 if fast else rng.randrange(7))
        dut.icache_req_rdy_i.value = not fast and rng.randrange(4) != 0
        dut.dcache_req_rdy_i.value = fast or rng.randrange(3) == 0
        # Cache lookup results always belong to the selected PC. A redirect
        # selects a fresh lookup, even if the previous address was a miss.
        if_valid = cycle >= lookup_due
        fetched_word = program.get(current_pc, 0)
        data_valid = pending_data is not None and pending_data[1] <= cycle
        dut.icache_val_i.value = if_valid
        dut.icache_inst_i.value = fetched_word if if_valid else 0
        dut.dcache_rsp_val_i.value = data_valid
        dut.dcache_rsp_data_i.value = pending_data[2] if data_valid else 0
        await Timer(5, unit="ns")

        if_request = bool(dut.icache_req_val_o.value)
        data_request = bool(dut.dcache_req_val_o.value)
        data_ready = bool(dut.dcache_req_rdy_i.value)
        payload = (int(dut.dcache_req_w.value),
                   int(dut.dcache_req_addr_o.value),
                   int(dut.dcache_req_data_o.value))
        if held_data is not None:
            assert data_request and payload == held_data, "stalled data changed"
        held_data = payload if data_request and not data_ready else None
        instruction_stalls += if_valid and not dut.icache_rdy_o.value
        data_stalls += data_request and not data_ready
        fetched_halt = (if_valid and dut.icache_rdy_o.value
                        and not dut.flush.value and fetched_word == 0)
        if fetched_halt:
            assert not if_request, "fetched HALT must disable requests immediately"

        # Data transactions retain their request/response handshake contract.
        if data_valid and dut.dcache_rsp_rdy_o.value:
            write, address, data = pending_data[0]
            if write:
                memory[address] = data
            responses.append(cycle)
            pending_data = None
        if data_request and data_ready:
            assert pending_data is None, "multiple outstanding data requests"
            assert payload[1] % 2 == 0, "unaligned data request"
            write, address, data = payload
            transactions.append((write, address, data if write else None))
            requests.append(cycle)
            delay = 1 if fast else rng.randrange(2, 10)
            pending_data = (payload, cycle + delay, memory.get(address, 0))
        if dut.halt.value:
            assert not data_request and pending_data is None
            if not if_request:
                assert transactions == expected_transactions
                assert memory == expected_memory
                for _ in range(3):
                    dut.clk_i.value = 1
                    await Timer(5, unit="ns")
                    dut.clk_i.value = 0
                    await Timer(5, unit="ns")
                    assert dut.halt.value
                    assert not dut.icache_req_val_o.value
                    assert not dut.dcache_req_val_o.value
                return requests, responses, instruction_stalls, data_stalls

        dut.clk_i.value = 1
        await Timer(5, unit="ns")
        if fetched_halt:
            assert not dut.inst_valid_q.value, "HALT must not enter IDEXMEM as valid"
        if abort_after is not None and cycle >= abort_after and pending_data is not None:
            return
    raise AssertionError("pipeline did not halt")


@cocotb.test(timeout_time=200, timeout_unit="us")
async def pipeline_with_cache_delays(dut):
    cases = [
        # The gem5 example, including an unreachable WA and dirty reload.
        ([wa(0), toga(0, 1), toga(0, 1), wa(24), toga(1, 0),
          wa(8), wa(16), wa(0), 0], {}),
        # Taken backward branch, then fall through on the second iteration.
        ([wa(0), toga(1, 0), toga(0, -2), 0], {0: 1}),
        # Same-address write-back must finish before reloading that word.
        ([wa(0xFFFE), toga(15, 0), wa(0xFFFE), toga(14, 0), 0],
         {0xFFFE: 0x8000}),
        # A wrong-path HALT must not prevent target execution.
        ([wa(2), toga(0, 1), 0, toga(5, 0), 0], {2: 1}),
        # Both extremes of the signed skip encoding.
        ({0: wa(0), 1: toga(3, 1023), 1025: toga(4, -1024), 2: 0},
         {0: 0x18}),
        # The RTL PC wraps at sixteen bits.
        ({0: wa(0), 1: toga(0, -3), 0xFFFF: toga(1, 1), 2: 0},
         {0: 3}),
        ([wa(4), wa(6), 0], {4: 7, 6: 0xABCD}),
        # Fresh TOGA starts from zero and writes back to default address 0.
        ([toga(1, 0), 0], {0: 0xFFFF}),
        # The first WA writes the fresh dirty word before loading its address.
        ([toga(2, 0), wa(6), toga(5, 0), 0], {0: 0xFFFF, 6: 0x30}),
        # Reloading default address 0 must observe its fresh write-back.
        ([toga(15, 0), wa(0), toga(14, 0), 0], {0: 0xFFFF}),
        # Fresh TOGAs can branch over the first WA.
        ([toga(0, 1), toga(0, 1), wa(24), toga(1, 0), 0], {0: 0xFFFF}),
        # Returning to zero remains dirty and overwrites the old memory word.
        ([toga(2, 0), toga(2, 0), 0], {0: 7}),
        ([0], {}),
    ]
    for seed in range(8):
        for words, memory in cases:
            await run_program(dut, words, memory, seed=seed)

    # Available lookups retire every cycle even with request-ready held low.
    requests, responses, stalls, _ = await run_program(
        dut, [wa(0)] + [toga(1, 0)] * 8 + [wa(2), 0], {}, fast=True)
    assert requests[1] - responses[0] == 9, "TOGA throughput is below 1/cycle"
    assert stalls > 0, "test did not hold IF behind a stalled WA"

    # Reset while a data response is pending, then start a fresh program.
    await run_program(dut, [wa(0), toga(2, 0), 0], {}, seed=0, abort_after=8)
    await run_program(dut, [wa(6), toga(3, 0), 0], {6: 0x20}, fast=True)
