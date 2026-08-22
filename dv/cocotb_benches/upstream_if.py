"""Cocotb driver for the project's blocking upstream interface."""

from cocotb.triggers import RisingEdge


class UpstreamMaster:
    """Issue one naturally synchronized request and wait for its response."""

    def __init__(self, bus, clock):
        self.bus = bus
        self.clock = clock

        self.bus.req_val.value = 0
        self.bus.req_addr.value = 0
        self.bus.req_data.value = 0
        self.bus.req_rw_flag.value = 0
        self.bus.rsp_rdy.value = 0

    async def transaction(
        self,
        address,
        data=0,
        *,
        is_write,
        response_delay_cycles=0,
    ):
        """Handshake one request, optionally delaying response acceptance."""
        self.bus.req_addr.value = address
        self.bus.req_data.value = data
        self.bus.req_rw_flag.value = int(is_write)
        self.bus.req_val.value = 1
        self.bus.rsp_rdy.value = 0

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

        for _ in range(response_delay_cycles):
            await RisingEdge(self.clock)

        self.bus.rsp_rdy.value = 1
        while True:
            await RisingEdge(self.clock)
            if self.bus.rsp_val.value:
                response = int(self.bus.rsp_data.value)
                break

        self.bus.rsp_rdy.value = 0
        return response

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
