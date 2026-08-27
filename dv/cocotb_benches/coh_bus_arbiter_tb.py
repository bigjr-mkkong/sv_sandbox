import random
from dataclasses import dataclass

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge


CLOCK_PERIOD_NS = 10
TEST_TIMEOUT_US = 20
SLV_CNT = 2
ADDR_WIDTH = 64

BUS_RDX = 2


@dataclass(frozen=True)
class CohRequest:
    bus_op: int
    address: int


class CohBusArbiterTB:
    """Small source-side abstraction for the coherence-bus arbiter."""

    def __init__(self, dut):
        self.dut = dut
        self._responses = [None] * SLV_CNT
        self._req_valid = 0
        self._bus_ops = 0
        self._req_addresses = 0
        self._rsp_ready = 0
        cocotb.start_soon(Clock(dut.clk_i, CLOCK_PERIOD_NS, unit="ns").start())

    @staticmethod
    def _replace_lane(aggregate, port, width, value):
        mask = ((1 << width) - 1) << (port * width)
        return (aggregate & ~mask) | (value << (port * width))

    @staticmethod
    def _read_lane(signal, port, width=1):
        return (int(signal.value) >> (port * width)) & ((1 << width) - 1)

    async def reset(self):
        self.dut.rst_ni.value = 0
        self.dut.slv_req_val.value = 0
        self.dut.slv_bus_op.value = 0
        self.dut.slv_req_addr.value = 0
        self.dut.slv_rsp_rdy.value = 0
        self.dut.mst_rsp_delay_cycles.value = 0
        self._responses = [None] * SLV_CNT
        self._req_valid = 0
        self._bus_ops = 0
        self._req_addresses = 0
        self._rsp_ready = 0

        for _ in range(3):
            await RisingEdge(self.dut.clk_i)
        await FallingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1

    def write_req(self, port, value):
        assert 0 <= port < SLV_CNT
        self._bus_ops = self._replace_lane(
            self._bus_ops, port, 2, value.bus_op
        )
        self._req_addresses = self._replace_lane(
            self._req_addresses, port, ADDR_WIDTH, value.address
        )
        self._req_valid = self._replace_lane(self._req_valid, port, 1, 1)

        self.dut.slv_bus_op.value = self._bus_ops
        self.dut.slv_req_addr.value = self._req_addresses
        self.dut.slv_req_val.value = self._req_valid

    def randomize_response_delay(self):
        """Choose the wrapper responder latency for this test."""
        response_delay = random.randint(1, 32)
        self.dut.mst_rsp_delay_cycles.value = response_delay
        return response_delay

    @staticmethod
    def expected_shared(value):
        """Mirror the wrapper responder: command LSB XOR address LSB."""
        return bool((value.bus_op & 1) ^ (value.address & 1))

    async def wait_req(self, port):
        assert 0 <= port < SLV_CNT
        while True:
            await RisingEdge(self.dut.clk_i)
            if self._read_lane(self.dut.slv_req_rdy, port):
                request = CohRequest(
                    bus_op=self._read_lane(self.dut.slv_bus_op, port, 2),
                    address=self._read_lane(
                        self.dut.slv_req_addr, port, ADDR_WIDTH
                    ),
                )
                self._req_valid = self._replace_lane(
                    self._req_valid, port, 1, 0
                )
                self.dut.slv_req_val.value = self._req_valid
                return request

    async def wait_rsp(self, port):
        assert 0 <= port < SLV_CNT
        self._rsp_ready = self._replace_lane(self._rsp_ready, port, 1, 1)
        self.dut.slv_rsp_rdy.value = self._rsp_ready
        while True:
            await RisingEdge(self.dut.clk_i)
            if self._read_lane(self.dut.slv_rsp_val, port):
                self._responses[port] = bool(
                    self._read_lane(self.dut.slv_rsp_shared, port)
                )
                self._rsp_ready = self._replace_lane(
                    self._rsp_ready, port, 1, 0
                )
                self.dut.slv_rsp_rdy.value = self._rsp_ready
                return

    def read_rsp(self, port):
        assert 0 <= port < SLV_CNT
        assert self._responses[port] is not None
        return self._responses[port]


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def single_source_request_response(dut):
    """Route the wrapper controller's computed responses to their sources."""
    tb = CohBusArbiterTB(dut)
    await tb.reset()
    tb.randomize_response_delay()

    requests = (
        (0, CohRequest(bus_op=BUS_RDX, address=0x1234_5600)),
        (1, CohRequest(bus_op=BUS_RDX, address=0x1234_5601)),
    )

    for port, request in requests:
        tb.write_req(port, request)

        accepted = await tb.wait_req(port)
        assert accepted == request
        assert int(dut.slv_req_rdy.value) & (1 << (port ^ 1)) == 0

        await tb.wait_rsp(port)
        assert tb.read_rsp(port) is tb.expected_shared(request)
        assert int(dut.slv_rsp_val.value) & (1 << (port ^ 1)) == 0


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def dual_source_request_response(dut):
    """Route the wrapper controller's computed responses to their sources."""
    tb = CohBusArbiterTB(dut)
    await tb.reset()
    tb.randomize_response_delay()

    requests = (
        (0, CohRequest(bus_op=BUS_RDX, address=0x1234_5600)),
        (1, CohRequest(bus_op=BUS_RDX, address=0x1234_5601)),
    )

    for port, request in requests:
        tb.write_req(port, request)

    accepted = await tb.wait_req(0)
    assert accepted == requests[0][1], (
        f"port 0 accepted {accepted}, expected {requests[0][1]}"
    )
    await tb.wait_rsp(0)
    assert tb.read_rsp(0) is tb.expected_shared(requests[0][1])

    accepted = await tb.wait_req(1)
    assert accepted == requests[1][1], (
        f"port 1 accepted {accepted}, expected {requests[1][1]}"
    )
    await tb.wait_rsp(1)
    assert tb.read_rsp(1) is tb.expected_shared(requests[1][1])


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def port0_back2back_req_rsp(dut):
    """Accept a second port-0 request after its first response completes."""
    tb = CohBusArbiterTB(dut)
    await tb.reset()
    tb.randomize_response_delay()

    requests = (
        CohRequest(bus_op=BUS_RDX, address=0x1234_5600),
        CohRequest(bus_op=BUS_RDX, address=0x1234_5601),
    )

    tb.write_req(0, requests[0])

    accepted = await tb.wait_req(0)
    assert accepted == requests[0]
    await tb.wait_rsp(0)
    assert tb.read_rsp(0) is tb.expected_shared(requests[0])

    tb.write_req(0, requests[1])
    accepted = await tb.wait_req(0)
    assert accepted == requests[1]
    await tb.wait_rsp(0)
    assert tb.read_rsp(0) is tb.expected_shared(requests[1])


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def port1_back2back_req_rsp(dut):
    """Accept a second port-1 request after its first response completes."""
    tb = CohBusArbiterTB(dut)
    await tb.reset()
    tb.randomize_response_delay()

    requests = (
        CohRequest(bus_op=BUS_RDX, address=0x2345_6700),
        CohRequest(bus_op=BUS_RDX, address=0x2345_6701),
    )

    for request in requests:
        tb.write_req(1, request)
        accepted = await tb.wait_req(1)
        assert accepted == request
        await tb.wait_rsp(1)
        assert tb.read_rsp(1) is tb.expected_shared(request)


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def delayed_response(dut):
    """Keep the selected source stable while the controller delays response."""
    tb = CohBusArbiterTB(dut)
    await tb.reset()

    response_delay = tb.randomize_response_delay()
    request = CohRequest(bus_op=BUS_RDX, address=0x3456_7801)

    tb.write_req(0, request)
    accepted = await tb.wait_req(0)
    assert accepted == request

    for _ in range(response_delay):
        await FallingEdge(dut.clk_i)
        assert tb._read_lane(dut.slv_rsp_val, 0) == 0
        assert tb._read_lane(dut.slv_req_rdy, 1) == 0

    await FallingEdge(dut.clk_i)
    assert tb._read_lane(dut.slv_rsp_val, 0) == 1
    assert tb._read_lane(dut.slv_rsp_val, 1) == 0

    await tb.wait_rsp(0)
    assert tb.read_rsp(0) is tb.expected_shared(request)


@cocotb.test(timeout_time=TEST_TIMEOUT_US, timeout_unit="us")
async def random_req_offset(dut):
    """Serialize requests asserted at different random cycle offsets."""
    tb = CohBusArbiterTB(dut)
    await tb.reset()
    tb.randomize_response_delay()

    requests = (
        CohRequest(bus_op=BUS_RDX, address=0x4567_8900),
        CohRequest(bus_op=BUS_RDX, address=0x4567_8901),
    )

    tb.write_req(0, requests[0])
    port0_accept = cocotb.start_soon(tb.wait_req(0))

    await ClockCycles(dut.clk_i, random.randint(1, 8))

    tb.write_req(1, requests[1])
    port1_accept = cocotb.start_soon(tb.wait_req(1))

    await ClockCycles(dut.clk_i, random.randint(1, 8))
    assert tb._read_lane(dut.slv_req_rdy, 1) == 0

    accepted = await port0_accept
    assert accepted == requests[0]
    await tb.wait_rsp(0)
    assert tb.read_rsp(0) is tb.expected_shared(requests[0])

    accepted = await port1_accept
    assert accepted == requests[1]
    await tb.wait_rsp(1)
    assert tb.read_rsp(1) is tb.expected_shared(requests[1])
