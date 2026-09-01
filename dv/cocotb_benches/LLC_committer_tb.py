import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


CLOCK_PERIOD_NS = 10
LINE_BYTES = 64


class LLCCommitter:
    """Transaction-level driver for the two LLC-committer producers."""

    def __init__(self, dut):
        self.dut = dut
        self.last_coh_response_wait_cycles = 0
        self.last_cache_response_wait_cycles = 0
        cocotb.start_soon(
            Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start()
        )

    async def reset(self):
        dut = self.dut
        dut.coh_req_val_i.value = 0
        dut.coh_req_is_write_i.value = 0
        dut.coh_req_addr_i.value = 0
        dut.coh_req_data_i.value = 0
        dut.coh_rsp_rdy_i.value = 0
        dut.cache_req_val_i.value = 0
        dut.cache_req_is_write_i.value = 0
        dut.cache_req_addr_i.value = 0
        dut.cache_req_data_i.value = 0
        dut.cache_rsp_rdy_i.value = 0

        dut.rst_ni.value = 0
        for _ in range(4):
            await RisingEdge(dut.clk_i)
        dut.rst_ni.value = 1
        await RisingEdge(dut.clk_i)

    async def write_coh_request(self, *, is_write, address, data=0):
        await self._write_request(
            req_val=self.dut.coh_req_val_i,
            req_rdy=self.dut.coh_req_rdy_o,
            req_is_write=self.dut.coh_req_is_write_i,
            req_addr=self.dut.coh_req_addr_i,
            req_data=self.dut.coh_req_data_i,
            is_write=is_write,
            address=address,
            data=data,
        )

    async def write_cache_request(self, *, is_write, address, data=0):
        await self._write_request(
            req_val=self.dut.cache_req_val_i,
            req_rdy=self.dut.cache_req_rdy_o,
            req_is_write=self.dut.cache_req_is_write_i,
            req_addr=self.dut.cache_req_addr_i,
            req_data=self.dut.cache_req_data_i,
            is_write=is_write,
            address=address,
            data=data,
        )

    async def wait_coh_request(self):
        data, cycles = await self._wait_response(
            rsp_val=self.dut.coh_rsp_val_o,
            rsp_rdy=self.dut.coh_rsp_rdy_i,
            rsp_data=self.dut.coh_rsp_data_o,
            other_rsp_val=self.dut.cache_rsp_val_o,
        )
        self.last_coh_response_wait_cycles = cycles
        return data

    async def wait_cache_request(self):
        data, cycles = await self._wait_response(
            rsp_val=self.dut.cache_rsp_val_o,
            rsp_rdy=self.dut.cache_rsp_rdy_i,
            rsp_data=self.dut.cache_rsp_data_o,
            other_rsp_val=self.dut.coh_rsp_val_o,
        )
        self.last_cache_response_wait_cycles = cycles
        return data

    async def wait_dram_read_count(self, expected, limit=100):
        await self._wait_value(
            self.dut.dram_read_count_o, expected, limit
        )

    async def wait_dram_write_count(self, expected, limit=100):
        await self._wait_value(
            self.dut.dram_write_count_o, expected, limit
        )

    async def _write_request(
        self,
        *,
        req_val,
        req_rdy,
        req_is_write,
        req_addr,
        req_data,
        is_write,
        address,
        data,
    ):
        req_val.value = 1

        while True:
            await Timer(1, unit="ns")
            if req_rdy.value:
                req_is_write.value = int(is_write)
                req_addr.value = address
                req_data.value = data
                await RisingEdge(self.dut.clk_i)
                req_val.value = 0
                return
            await RisingEdge(self.dut.clk_i)

    async def _wait_response(
        self,
        *,
        rsp_val,
        rsp_rdy,
        rsp_data,
        other_rsp_val,
    ):
        wait_cycles = 0
        rsp_rdy.value = 1

        while True:
            await Timer(1, unit="ns")
            if rsp_val.value:
                result = int(rsp_data.value)
                assert not other_rsp_val.value
                await RisingEdge(self.dut.clk_i)
                rsp_rdy.value = 0
                return result, wait_cycles
            assert not other_rsp_val.value
            await RisingEdge(self.dut.clk_i)
            wait_cycles += 1

    async def _wait_value(self, signal, expected, limit):
        for _ in range(limit):
            await Timer(1, unit="ns")
            if int(signal.value) == expected:
                return
            await RisingEdge(self.dut.clk_i)
        raise AssertionError(
            f"timed out waiting for {signal._name} == {expected}"
        )


@cocotb.test()
async def coherence_priority_and_response_routing(dut):
    """Honor priority, ready-first responses, and real DRAM data flow."""
    tb = LLCCommitter(dut)
    await tb.reset()

    coh_addr = 0x1000
    cache_addr = coh_addr
    coh_line = int.from_bytes(
        bytes((0x80 + index) & 0xFF for index in range(LINE_BYTES)),
        "little",
    )
    # Simultaneous producers must accept coherence and leave cache valid held.
    coh_submit = cocotb.start_soon(
        tb.write_coh_request(
            is_write=True,
            address=coh_addr,
            data=coh_line,
        )
    )
    cache_submit = cocotb.start_soon(
        tb.write_cache_request(
            is_write=False,
            address=cache_addr,
        )
    )
    await Timer(1, unit="ns")
    assert dut.coh_req_rdy_o.value
    assert not dut.cache_req_rdy_o.value

    await coh_submit
    await tb.wait_dram_write_count(1)
    assert int(dut.dram_last_write_addr_o.value) == coh_addr
    assert int(dut.dram_last_write_data_o.value) == coh_line
    assert dut.cache_req_val_i.value

    assert await tb.wait_coh_request() == 0

    # Only after the coherence response is consumed can the held cache read
    # enter the real dumb DRAM and retrieve the coherence-written line.
    await cache_submit
    await tb.wait_dram_read_count(1)
    assert int(dut.dram_last_read_addr_o.value) == cache_addr
    assert await tb.wait_cache_request() == coh_line
    assert int(dut.dram_write_count_o.value) == 1
    assert int(dut.dram_read_count_o.value) == 1
