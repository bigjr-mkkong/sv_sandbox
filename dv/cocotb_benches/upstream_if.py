"""Cocotb driver for the project's blocking upstream interface."""

from cocotb.triggers import RisingEdge


class UpstreamMaster:
    """One request-pin owner and one response-pin owner may run independently."""

    def __init__(self, bus, clock):
        self.bus = bus
        self.clock = clock

        self.bus.req_val.value = 0
        self.bus.req_addr.value = 0
        self.bus.req_data.value = 0
        self.bus.req_rw_flag.value = 0
        self.bus.rsp_rdy.value = 0

    async def send_request(self, address, data=0, *, is_write):
        """Hold a request until accepted; do not touch response-ready."""
        self.bus.req_addr.value = address
        self.bus.req_data.value = data
        self.bus.req_rw_flag.value = int(is_write)
        self.bus.req_val.value = 1

        while True:
            await RisingEdge(self.clock)
            if self.bus.req_rdy.value:
                break

        # The request payload is no longer required to remain stable after the
        # handshake. Clearing it also verifies that the DUT latched all fields.
        self.bus.req_val.value = 0
        self.bus.req_addr.value = 0
        self.bus.req_data.value = 0
        self.bus.req_rw_flag.value = 0

    async def receive_response(self, *, response_delay_cycles=0):
        """Optionally stall an actual valid response, then consume it."""
        assert response_delay_cycles >= 0
        if response_delay_cycles:
            self.bus.rsp_rdy.value = 0
            while True:
                await RisingEdge(self.clock)
                if self.bus.rsp_val.value:
                    held = int(self.bus.rsp_data.value)
                    break
            for _ in range(response_delay_cycles - 1):
                await RisingEdge(self.clock)
                assert self.bus.rsp_val.value, "response valid dropped during stall"
                assert int(self.bus.rsp_data.value) == held

        self.bus.rsp_rdy.value = 1
        while True:
            await RisingEdge(self.clock)
            if self.bus.rsp_val.value:
                response = int(self.bus.rsp_data.value)
                if response_delay_cycles:
                    assert response == held
                break

        self.bus.rsp_rdy.value = 0
        return response

    async def transaction(
        self, address, data=0, *, is_write, response_delay_cycles=0,
    ):
        """Convenience path for intentionally serialized functional tests."""
        await self.send_request(address, data, is_write=is_write)
        return await self.receive_response(
            response_delay_cycles=response_delay_cycles,
        )

    async def read(self, address, *, response_delay_cycles=0):
        return await self.transaction(
            address,
            is_write=False,
            response_delay_cycles=response_delay_cycles,
        )

    async def write(self, address, data, *, response_delay_cycles=0):
        return await self.transaction(
            address,
            data,
            is_write=True,
            response_delay_cycles=response_delay_cycles,
        )
