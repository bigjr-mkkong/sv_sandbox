"""Load version-1 datasets for the 16-bit ISA and 64-bit working register.

Code is a list of four-digit hex instruction words, loaded little endian at
byte address zero. RAM is cleared to zero before applying precondition.memory.
Memory blocks contain an integer byte address and a list of integer bytes.
postcondition.memory and HALT are observable on both simulation and hardware.
The optional simulation section contains internal register/branch/transaction
checks; reg_q is a 16-digit hex string to preserve all 64 bits in JSON tools.
Data transactions are [write, byte_address, write_data_or_zero] triples.
"""

import json
from pathlib import Path
import re

DATA_DIR = Path(__file__).resolve().parent
RAM_SIZE = 65536


def _keys(value, required, optional=()):
    if not isinstance(value, dict) or not set(required) <= value.keys():
        raise ValueError(f"Expected an object containing {sorted(required)}")
    if value.keys() - set(required) - set(optional):
        raise ValueError(f"Unknown fields: {sorted(value.keys() - set(required) - set(optional))}")


def _integer(value, lower, upper):
    if type(value) is not int or not lower <= value <= upper:
        raise ValueError(f"Expected an integer in {lower}..{upper}: {value!r}")
    return value


def _hex(value, digits):
    if not isinstance(value, str) or re.fullmatch(f"[0-9a-fA-F]{{{digits}}}", value) is None:
        raise ValueError(f"Expected {digits} hexadecimal digits: {value!r}")
    return int(value, 16)


def _blocks(blocks, occupied=()):
    if not isinstance(blocks, list):
        raise ValueError("Memory must be a list of address/bytes blocks")
    ranges = list(occupied)
    for block in blocks:
        _keys(block, ("address", "bytes"))
        address = _integer(block["address"], 0, RAM_SIZE - 1)
        data = block["bytes"]
        if not isinstance(data, list) or not data or len(data) > RAM_SIZE - address:
            raise ValueError("Memory block must be nonempty and fit within 64 KiB")
        block["bytes"] = bytes(_integer(byte, 0, 255) for byte in data)
        end = address + len(data)
        if any(address < stop and start < end for start, stop in ranges):
            raise ValueError("Overlapping code or memory blocks")
        ranges.append((address, end))


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON field: {key}")
        result[key] = value
    return result


def load_program(path):
    """Validate a complete dataset before any simulator or GPIO mutation."""
    path = Path(path)
    try:
        case = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_object)
        _keys(case, ("schema_version", "name", "code", "precondition", "postcondition"),
              ("simulation", "inputs"))
        _integer(case["schema_version"], 1, 1)
        if not isinstance(case["name"], str) or re.fullmatch(r"[a-z][a-z0-9_]*", case["name"]) is None:
            raise ValueError("Program name must use lowercase letters, digits and underscores")
        code = case["code"]
        if not isinstance(code, list) or not 1 <= len(code) <= RAM_SIZE // 2:
            raise ValueError("Code must contain 1..32768 instruction words")
        case["code"] = b"".join(_hex(word, 4).to_bytes(2, "little") for word in code)
        _keys(case["precondition"], ("memory",))
        _blocks(case["precondition"]["memory"], [(0, len(case["code"]))])
        _keys(case["postcondition"], ("halt", "memory"))
        if case["postcondition"]["halt"] is not True:
            raise ValueError("Program must expect HALT")
        if not case["postcondition"]["memory"]:
            raise ValueError("At least one memory postcondition is required")
        _blocks(case["postcondition"]["memory"])
        inputs = case.get("inputs", {})
        _keys(inputs, (), ("a", "b", "steps"))
        for value in inputs.values():
            _integer(value, 0, 255)
        sim = case.setdefault("simulation", {})
        _keys(sim, (), ("registers", "min_backward_branches", "backward_offsets", "data_transactions", "timeout_ms"))
        if "timeout_ms" in sim:
            _integer(sim["timeout_ms"], 1, 2**31 - 1)
        registers = sim.get("registers", {})
        _keys(registers, (), ("pc_q", "reg_addr_q", "reg_q"))
        for name, value in registers.items():
            registers[name] = _hex(value, 16) if name == "reg_q" else _integer(value, 0, 65535)
        if "min_backward_branches" in sim:
            _integer(sim["min_backward_branches"], 1, 2**31 - 1)
        if "backward_offsets" in sim:
            if not isinstance(sim["backward_offsets"], list):
                raise ValueError("Backward offsets must be a list")
            for offset in sim["backward_offsets"]:
                _integer(offset, -256, -1)
        if "data_transactions" in sim:
            if not isinstance(sim["data_transactions"], list):
                raise ValueError("Data transactions must be a list")
            for transfer in sim["data_transactions"]:
                if not isinstance(transfer, list) or len(transfer) != 3:
                    raise ValueError("Expected [write, address, data] transaction")
                write, address, data = transfer
                _integer(write, 0, 1)
                _integer(address, 0, 65535)
                _integer(data, 0, 255 if write else 0)
        return case
    except (ValueError, TypeError) as error:
        raise ValueError(f"{path}: {error}") from error


def load_programs():
    cases = [load_program(path) for path in sorted(DATA_DIR.glob("*.json"))]
    names = [case["name"] for case in cases]
    if not cases or len(names) != len(set(names)):
        raise ValueError("Dataset must contain programs with unique names")
    return cases


def initial_regions(case):
    """Return code and explicit preconditions after the caller zeroes RAM."""
    return [(0, case["code"])] + [
        (block["address"], block["bytes"]) for block in case["precondition"]["memory"]]


def check_memory(case, read):
    """Use the same byte comparisons with either model RAM or real SPI reads."""
    for block in case["postcondition"]["memory"]:
        address, expected = block["address"], block["bytes"]
        actual = bytes(read(address, len(expected)))
        if actual != expected:
            raise AssertionError(
                f"{case['name']} at {address:#06x}: got {actual.hex(' ')}, "
                f"expected {expected.hex(' ')}")
