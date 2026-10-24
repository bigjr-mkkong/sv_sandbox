# SPDX-License-Identifier: BSD-3-Clause
"""Generate basic RTL programs and the five gem5 TOGAWA benchmarks.

Output is readmemh-style text: @byte_address followed by hex bytes. Instructions
are little endian. WA takes an aligned byte address; TOGA takes a bit index and
a label or signed displacement from the next word PC. HALT is exactly 0x0000.
"""

import math
from pathlib import Path


BENCHMARKS = ("incrementer", "adder", "fibonacci", "gcd", "lfsr")
BOUNDARY_INPUTS = {
    "incrementer": {"a": 255},
    "adder": {"a": 127, "b": 129},
    "fibonacci": {"steps": 13},
    "gcd": {"a": 255, "b": 251},
    "lfsr": {"a": 255, "steps": 255},
}
DATA_BASE = 0x4000
A, B, RESULT = DATA_BASE, DATA_BASE + 2, DATA_BASE + 4
X, Y, TEMP, COUNT = (DATA_BASE + offset for offset in (8, 10, 12, 14))


class Program:
    """Small label-resolving assembler for the RTL's 16-bit TOGAWA ISA."""

    def __init__(self):
        self.code = []
        self.labels = {}
        self.label_count = 0

    def label(self):
        self.label_count += 1
        return f"L{self.label_count}"

    def mark(self, label):
        if label in self.labels:
            raise ValueError(f"Duplicate label: {label}")
        self.labels[label] = len(self.code)

    def wa(self, address):
        if not 0 <= address <= 0xFFFE or address & 1:
            raise ValueError(f"Invalid WA byte address: {address}")
        self.code.append(("wa", address))

    def toga(self, bit, target=0):
        self.code.append(("toga", bit, target))

    def halt(self):
        self.code.append(("halt",))

    # Arithmetic macros adapted from gem5/configs/test/togawa-bench.py.
    def jump(self, target):
        # Bit 15 starts zero and is restored before reaching the target.
        self.toga(15)
        self.toga(15, target)

    def toggle(self, bit):
        if bit == 0:
            # Skip a restoring scratch-bit pair instead of encoding HALT.
            self.toga(0, 2)
            self.toga(15)
            self.toga(15)
        else:
            self.toga(bit)

    def branch_zero(self, bit, target):
        """Branch on the original bit, restoring it on both paths."""
        self.toga(bit, 1)
        self.toga(bit, target)
        self.toga(bit, 1)

    def clear_bit(self, bit):
        done = self.label()
        self.toga(bit, done)
        self.toggle(bit)
        self.mark(done)

    def clear(self, address):
        self.wa(address)
        for bit in range(8):
            self.clear_bit(bit)

    def copy(self, src, dst):
        self.clear(dst)
        self.wa(src)
        for bit in range(8):
            done = self.label()
            self.branch_zero(bit, done)
            self.wa(dst)
            self.toggle(bit)
            self.wa(src)
            self.mark(done)

    def increment(self, address, start=0):
        """Add 2**start, propagating carry through the low byte."""
        self.wa(address)
        done = self.label()
        for bit in range(start, 7):
            carry = self.label()
            self.toga(bit, carry)
            self.jump(done)
            self.mark(carry)
        self.toga(7)
        self.mark(done)

    def decrement(self, address, start=0):
        self.wa(address)
        done = self.label()
        for bit in range(start, 8):
            self.toga(bit, done)
        self.mark(done)

    def add(self, left, right, dst):
        self.copy(left, dst)
        for bit in range(8):
            done = self.label()
            self.wa(right)
            self.branch_zero(bit, done)
            self.increment(dst, bit)
            self.mark(done)

    def subtract(self, dst, src):
        for bit in range(8):
            done = self.label()
            self.wa(src)
            self.branch_zero(bit, done)
            self.decrement(dst, bit)
            self.mark(done)

    def zero(self, address, target):
        nonzero = self.label()
        self.wa(address)
        for bit in range(8):
            next_bit = self.label()
            self.branch_zero(bit, next_bit)
            self.jump(nonzero)
            self.mark(next_bit)
        self.jump(target)
        self.mark(nonzero)

    def compare(self, left, right, less, equal, greater):
        for bit in reversed(range(8)):
            left_zero, next_bit = self.label(), self.label()
            self.wa(left)
            self.branch_zero(bit, left_zero)
            self.wa(right)
            self.branch_zero(bit, greater)
            self.jump(next_bit)
            self.mark(left_zero)
            self.wa(right)
            self.branch_zero(bit, next_bit)
            self.jump(less)
            self.mark(next_bit)
        self.jump(equal)

    def shift_right(self, address):
        self.wa(address)
        for bit in range(7):
            self.clear_bit(bit)
            done = self.label()
            self.branch_zero(bit + 1, done)
            self.toggle(bit)
            self.mark(done)
        self.clear_bit(7)

    def assemble(self):
        if not 1 <= len(self.code) <= 32768:
            raise ValueError("Program must contain 1..32768 instructions")
        words = []
        for pc, inst in enumerate(self.code):
            if inst[0] == "wa":
                word = 0x8000 | (inst[1] >> 1)
            elif inst[0] == "halt":
                word = 0
            else:
                _, bit, target = inst
                if isinstance(target, str):
                    if target not in self.labels:
                        raise ValueError(f"Unknown label: {target}")
                    target = self.labels[target] - pc - 1
                if not 0 <= bit < 16 or not -1024 <= target <= 1023:
                    raise ValueError(f"Unencodable TOGA at PC {pc}")
                word = (bit << 11) | (target & 0x7FF)
                if word == 0:
                    raise ValueError("TOGA bit 0 with displacement 0 encodes HALT")
            words.append(word)
        return words

    def write(self, path, address, data):
        """Write code at zero and one non-overlapping initial data range."""
        words = self.assemble()
        if address < 2 * len(words) or address + len(data) > 65536:
            raise ValueError("Initial data overlaps code or exceeds SPI RAM")
        if any(not 0 <= byte <= 0xFF for byte in data):
            raise ValueError("Initial data must contain byte values")
        lines = ["@0000", *(f"{word & 0xFF:02x} {word >> 8:02x}" for word in words)]
        lines.extend((f"@{address:04x}", " ".join(f"{byte:02x}" for byte in data)))
        Path(path).write_text("\n".join(lines) + "\n", encoding="ascii")


def make_benchmark(name, a=13, b=7, steps=8):
    """Build the gem5 benchmarks with 8-bit arithmetic in 16-bit data words."""
    if name not in BENCHMARKS:
        raise ValueError(f"Unknown benchmark: {name}")
    if any(not isinstance(value, int) or not 0 <= value <= 255 for value in (a, b, steps)):
        raise ValueError("Inputs and step count must be in 0..255")
    p = Program()
    if name == "incrementer":
        initial = {A: a}
        p.increment(A)
        expected = {A: (a + 1) & 0xFF}
    elif name == "adder":
        initial = {A: a, B: b, RESULT: 0}
        p.add(A, B, RESULT)
        expected = {A: a, B: b, RESULT: (a + b) & 0xFF}
    elif name == "fibonacci":
        initial = {A: steps, RESULT: 0, X: 0, Y: 1, TEMP: 0, COUNT: steps}
        loop, done = p.label(), p.label()
        p.mark(loop)
        p.zero(COUNT, done)
        p.add(X, Y, TEMP)
        p.copy(Y, X)
        p.copy(TEMP, Y)
        p.decrement(COUNT)
        p.jump(loop)
        p.mark(done)
        p.copy(X, RESULT)
        x, y = 0, 1
        for _ in range(steps):
            x, y = y, (x + y) & 0xFF
        expected = {A: steps, RESULT: x}
    elif name == "gcd":
        initial = {A: a, B: b, RESULT: 0, X: 0, Y: 0}
        use_a, use_b, end = p.label(), p.label(), p.label()
        loop, less, equal, greater = (p.label() for _ in range(4))
        p.zero(A, use_b)
        p.zero(B, use_a)
        p.copy(A, X)
        p.copy(B, Y)
        p.mark(loop)
        p.compare(X, Y, less, equal, greater)
        p.mark(less)
        p.subtract(Y, X)
        p.jump(loop)
        p.mark(greater)
        p.subtract(X, Y)
        p.jump(loop)
        p.mark(equal)
        p.copy(X, RESULT)
        p.jump(end)
        p.mark(use_a)
        p.copy(A, RESULT)
        p.jump(end)
        p.mark(use_b)
        p.copy(B, RESULT)
        p.mark(end)
        expected = {A: a, B: b, RESULT: math.gcd(a, b)}
    else:
        initial = {A: a, B: steps}
        loop, done = p.label(), p.label()
        p.mark(loop)
        p.zero(B, done)
        p.wa(A)
        no_feedback = p.label()
        p.branch_zero(0, no_feedback)
        p.toggle(8)  # Save the outgoing bit above the 8-bit state.
        p.mark(no_feedback)
        p.shift_right(A)
        no_feedback = p.label()
        p.branch_zero(8, no_feedback)
        p.toggle(8)
        for bit in (7, 5, 4, 3):
            p.toggle(bit)
        p.mark(no_feedback)
        p.decrement(B)
        p.jump(loop)
        p.mark(done)
        value = a
        for _ in range(steps):
            value = (value >> 1) ^ (0xB8 if value & 1 else 0)
        expected = {A: value, B: 0}
    p.halt()
    return p, initial, expected


def make_backward_branch_limits():
    """Exercise taken -1 and -1024 offsets, with HALT guards on wrong paths."""
    p = Program()
    p.wa(DATA_BASE)
    p.mark("again")
    p.toga(2, "again")
    p.toga(15)
    p.mark("back")
    p.toga(15, "far")
    p.toga(15)
    p.halt()
    while len(p.code) < 1026:
        p.halt()
    p.mark("far")
    p.toga(2, "back")
    p.halt()
    return p


def generate():
    output = Path(__file__).resolve().parent
    p = Program()
    p.wa(0x200)
    p.halt()
    p.write(output / "basic_wa.hex", 0x200, [0xA4, 0x5A])

    for name, low_byte in (("basic_toga_no_jump", 0xA0), ("basic_toga_jump", 0xA4)):
        p = Program()
        p.wa(0x200)
        p.toga(2, "new_pc")
        p.halt()
        p.mark("new_pc")
        p.halt()
        p.write(output / f"{name}.hex", 0x200, [low_byte, 0x5A])

    for name, inputs in (*BOUNDARY_INPUTS.items(), ("fibonacci_overflow", {"steps": 14})):
        p, initial, _ = make_benchmark("fibonacci" if name == "fibonacci_overflow" else name, **inputs)
        data = [0x00] * 16
        for address, value in initial.items():
            data[address - DATA_BASE] = value
        p.write(output / f"{name}.hex", DATA_BASE, data)

    make_backward_branch_limits().write(
        output / "backward_branch_limits.hex", DATA_BASE, [0x04, 0x00]
    )


if __name__ == "__main__":
    generate()
