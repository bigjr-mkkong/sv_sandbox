import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


CLOCK_PERIOD_NS = 10
TEST_TIMEOUT_US = 20
L1_CACHE_CNT = 4
BUS_RDX = 2


async def settle():
    await Timer(1, unit="ns")


class GlobalCoherencyTB:
    def __init__(self, dut):
        self.dut = dut
        self._pseudo_delay_cfg = 0
        self._pseudo_resp_cfg = 0
        cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())

    async def reset(self):
        self.dut.cache_req_val.value = 0
        self.dut.cache_req_bus_op.value = 0
        self.dut.cache_req_addr.value = 0
        self.dut.cache_req_src.value = 0
        self.dut.cache_rsp_rdy.value = 0
        self._pseudo_delay_cfg = 0
        self._pseudo_resp_cfg = 0
        self.dut.pseudo_replier_delay_cfg.value = self._pseudo_delay_cfg
        self.dut.pseudo_replier_resp_cfg.value = self._pseudo_resp_cfg
        self.dut.rst_ni.value = 0
        for _ in range(3):
            await RisingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1
        await RisingEdge(self.dut.clk_i)
        await settle()

    async def submit(self, *, source, bus_op, address):
        self.dut.cache_req_src.value = source
        self.dut.cache_req_bus_op.value = bus_op
        self.dut.cache_req_addr.value = address
        self.dut.cache_req_val.value = 1
        while True:
            await settle()
            if int(self.dut.cache_req_rdy.value):
                await RisingEdge(self.dut.clk_i)
                break
            await RisingEdge(self.dut.clk_i)
        self.dut.cache_req_val.value = 0
        await settle()

    def pseudo_replier_delay(self, port, cycles):
        assert 0 <= port < L1_CACHE_CNT
        assert 0 <= cycles < (1 << 16)
        shift = 16 * port
        mask = 0xFFFF << shift
        self._pseudo_delay_cfg = (
            (self._pseudo_delay_cfg & ~mask) | (cycles << shift)
        )
        self.dut.pseudo_replier_delay_cfg.value = self._pseudo_delay_cfg

    def pseudo_replier_resp(self, port, *, shared):
        assert 0 <= port < L1_CACHE_CNT
        mask = 1 << port
        self._pseudo_resp_cfg = (
            (self._pseudo_resp_cfg & ~mask) | (int(shared) << port)
        )
        self.dut.pseudo_replier_resp_cfg.value = self._pseudo_resp_cfg

    async def wait_cache_response(self):
        while True:
            await settle()
            if int(self.dut.cache_rsp_val.value):
                return bool(int(self.dut.cache_rsp_shared.value))
            await RisingEdge(self.dut.clk_i)


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def excludes_requester_and_collects_independent_replies(dut):
    tb = GlobalCoherencyTB(dut)
    await tb.reset()

    source = 1
    address = 0x1234_5600
    expected_targets = ((1 << L1_CACHE_CNT) - 1) & ~(1 << source)
    expected_reply_cycles = {0: 3, 2: 1, 3: 2}
    for port in range(L1_CACHE_CNT):
        tb.pseudo_replier_delay(port, expected_reply_cycles.get(port, 0))
        tb.pseudo_replier_resp(port, shared=port == 3)

    await tb.submit(source=source, bus_op=BUS_RDX, address=address)

    assert int(dut.bus_req_val.value) == expected_targets
    for port in expected_reply_cycles:
        assert (int(dut.bus_req_op.value) >> (2 * port)) & 0x3 == BUS_RDX
        observed_addr = (int(dut.bus_req_addr.value) >> (64 * port)) & (
            (1 << 64) - 1
        )
        assert observed_addr == address
    assert int(dut.bus_req_rdy.value) == (1 << L1_CACHE_CNT) - 1

    await RisingEdge(dut.clk_i)
    await settle()

    observed_reply_cycles = {}
    for cycle in range(max(expected_reply_cycles.values()) + 1):
        response_valid = int(dut.bus_rsp_val.value) & expected_targets
        for port in expected_reply_cycles:
            if response_valid & (1 << port):
                assert port not in observed_reply_cycles
                observed_reply_cycles[port] = cycle
        await RisingEdge(dut.clk_i)
        await settle()

    assert observed_reply_cycles == expected_reply_cycles

    assert int(dut.cache_rsp_val.value) == 1
    assert int(dut.cache_rsp_shared.value) == 1
    for _ in range(3):
        await RisingEdge(dut.clk_i)
        await settle()
        assert int(dut.cache_rsp_val.value) == 1
        assert int(dut.cache_rsp_shared.value) == 1

    dut.cache_rsp_rdy.value = 1
    await RisingEdge(dut.clk_i)
    dut.cache_rsp_rdy.value = 0
    await settle()
    assert int(dut.cache_rsp_val.value) == 0
    assert int(dut.cache_req_rdy.value) == 1


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def returns_not_shared_when_no_snooper_has_a_copy(dut):
    tb = GlobalCoherencyTB(dut)
    await tb.reset()

    source = 0
    targets = (1, 2, 3)
    for port, delay in zip(targets, (2, 0, 4)):
        tb.pseudo_replier_delay(port, delay)
        tb.pseudo_replier_resp(port, shared=False)

    await tb.submit(source=source, bus_op=BUS_RDX, address=0xABC0)
    response_shared = await tb.wait_cache_response()

    assert int(dut.cache_rsp_val.value) == 1
    assert response_shared is False
