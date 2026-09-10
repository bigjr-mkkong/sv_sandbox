"""Passive edge checks shared by upstream and AXI backpressure tests."""

from cocotb.triggers import RisingEdge


async def monitor_handshakes(clock, channels, transfers, stalls):
    """Count transfers/stalls and require stalled valid/payload to stay stable."""
    held = {}
    for name in channels:
        transfers[name] = 0
        stalls[name] = 0
    while True:
        await RisingEdge(clock)
        for name, (valid, ready, payload) in channels.items():
            value = tuple(int(signal.value) for signal in payload)
            if name in held:
                assert valid.value, f"{name}: valid dropped before acceptance"
                assert value == held[name], f"{name}: stalled payload changed"
            if valid.value and not ready.value:
                held[name] = value
                stalls[name] += 1
            else:
                held.pop(name, None)
            if valid.value and ready.value:
                transfers[name] += 1
