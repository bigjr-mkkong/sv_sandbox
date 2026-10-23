"""Byte-range access to verilog memory arrays for preload and result inspection.

Write while the memory's consumer is held in reset; inspect after it stops.
"""

from cocotb.triggers import Timer


def read_memory(memory, address, length):
    """Read a list of byte values from a zero-based HDL byte array."""
    if address < 0 or length < 0 or address + length > len(memory):
        raise ValueError("Memory read is out of range")
    return [int(memory[index].value) for index in range(address, address + length)]


async def write_memory(memory, address, data):
    """Write byte values, validating the payload and range before changing memory."""
    data = bytes(data)
    if address < 0 or address + len(data) > len(memory):
        raise ValueError("Memory write is out of range")
    for index, byte in enumerate(data, start=address):
        memory[index].value = byte
    await Timer(1, unit="ns")
