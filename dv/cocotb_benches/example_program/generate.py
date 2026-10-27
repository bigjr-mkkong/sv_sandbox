# SPDX-License-Identifier: BSD-3-Clause
"""Generate basic RTL programs and the five gem5 TOGAWA benchmarks.

Output is readmemh-style text: @byte_address followed by hex bytes. Instructions
are little endian. WA takes an eight-byte-aligned byte address; WA-indirect uses the current
register as an eight-byte word index. TOGA selects bits 0..63 and branches by
-256..255 instruction words relative to the next PC. HALT is exactly 0x0000.
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
        self.bit_base = 0
        self.island_sites = set()

    def label(self):
        self.label_count += 1
        return f"L{self.label_count}"

    def mark(self, label):
        if label in self.labels:
            raise ValueError(f"Duplicate label: {label}")
        self.labels[label] = len(self.code)

    def wa(self, address):
        if not 0 <= address <= 0xFFF8 or address & 7:
            raise ValueError(f"Invalid WA byte address: {address}")
        self.code.append(("wa", address))

    def wa_indirect(self):
        self.code.append(("wa_indirect",))

    def select_word(self, address):
        """Select a benchmark's 16-bit variable within an aligned 64-bit word."""
        if not 0 <= address <= 0xFFFE or address & 1:
            raise ValueError(f"Invalid variable address: {address}")
        self.island_sites.add(len(self.code))
        self.wa(address & ~7)
        self.bit_base = (address & 7) * 8

    def toga(self, bit, target=0):
        self.code.append(("toga", bit, target))

    def halt(self):
        self.code.append(("halt",))

    # Arithmetic macros adapted from gem5/configs/test/togawa-bench.py.
    def jump(self, target):
        # Bit 63 starts zero and is restored before reaching the target.
        self.toga(63)
        self.toga(63, target)

    def toggle(self, bit):
        bit += self.bit_base
        if bit == 0:
            # Skip a restoring scratch-bit pair instead of encoding HALT.
            self.toga(0, 2)
            self.toga(63)
            self.toga(63)
        else:
            self.toga(bit)

    def branch_zero(self, bit, target):
        """Branch on the original bit, restoring it on both paths."""
        self.toga(self.bit_base + bit, 1)
        self.toga(self.bit_base + bit, target)
        self.toga(self.bit_base + bit, 1)

    def clear_bit(self, bit):
        done = self.label()
        self.toga(self.bit_base + bit, done)
        self.toggle(bit)
        self.mark(done)

    def clear(self, address):
        self.select_word(address)
        for bit in range(8):
            self.clear_bit(bit)

    def copy(self, src, dst):
        self.clear(dst)
        self.select_word(src)
        for bit in range(8):
            done = self.label()
            self.branch_zero(bit, done)
            self.select_word(dst)
            self.toggle(bit)
            self.select_word(src)
            self.mark(done)

    def increment(self, address, start=0):
        """Add 2**start, propagating carry through the low byte."""
        self.select_word(address)
        done = self.label()
        for bit in range(start, 7):
            carry = self.label()
            self.toga(self.bit_base + bit, carry)
            self.jump(done)
            self.mark(carry)
        self.toga(self.bit_base + 7)
        self.mark(done)

    def decrement(self, address, start=0):
        self.select_word(address)
        done = self.label()
        for bit in range(start, 8):
            self.toga(self.bit_base + bit, done)
        self.mark(done)

    def add(self, left, right, dst):
        self.copy(left, dst)
        for bit in range(8):
            done = self.label()
            self.select_word(right)
            self.branch_zero(bit, done)
            self.increment(dst, bit)
            self.mark(done)

    def subtract(self, dst, src):
        for bit in range(8):
            done = self.label()
            self.select_word(src)
            self.branch_zero(bit, done)
            self.decrement(dst, bit)
            self.mark(done)

    def zero(self, address, target):
        nonzero = self.label()
        self.select_word(address)
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
            self.select_word(left)
            self.branch_zero(bit, left_zero)
            self.select_word(right)
            self.branch_zero(bit, greater)
            self.jump(next_bit)
            self.mark(left_zero)
            self.select_word(right)
            self.branch_zero(bit, next_bit)
            self.jump(less)
            self.mark(next_bit)
        self.jump(equal)

    def shift_right(self, address):
        self.select_word(address)
        for bit in range(7):
            self.clear_bit(bit)
            done = self.label()
            self.branch_zero(bit + 1, done)
            self.toggle(bit)
            self.mark(done)
        self.clear_bit(7)

    def remove_redundant_wa(self):
        """Omit WA only when every incoming path has its window resident."""
        if any(inst[0] not in ("wa", "toga") for inst in self.code):
            raise ValueError("WA optimization requires a direct-WA/TOGA benchmark")
        targets = {
            pc: (
                self.labels[inst[2]]
                if isinstance(inst[2], str)
                else pc + 1 + inst[2]
            )
            for pc, inst in enumerate(self.code)
            if inst[0] == "toga"
        }
        if any(
            not 0 <= target <= len(self.code) for target in targets.values()
        ):
            raise ValueError("Branch outside program")
        incoming = [set() for _ in range(len(self.code) + 1)]
        incoming[0].add(None)  # No window has been loaded at entry.
        pending = [0]
        while pending:
            pc = pending.pop()
            if pc == len(self.code):
                continue
            inst = self.code[pc]
            windows = {inst[1]} if inst[0] == "wa" else incoming[pc]
            successors = [pc + 1]
            if inst[0] == "toga":
                successors.append(targets[pc])
            for target in successors:
                if windows - incoming[target]:
                    incoming[target].update(windows)
                    pending.append(target)
        keep = [
            inst[0] != "wa" or incoming[pc] != {inst[1]}
            for pc, inst in enumerate(self.code)
        ]
        # Removing the entire skip of TOGA bit zero would turn it into HALT.
        for pc, target in targets.items():
            if self.code[pc][1] == 0 and target > pc + 1 and not any(keep[pc + 1:target]):
                keep[pc + 1] = True
        positions = [0]
        for retained in keep:
            positions.append(positions[-1] + retained)
        self.code = [
            (
                ("toga", inst[1], positions[targets[pc]] - positions[pc] - 1)
                if inst[0] == "toga" and not isinstance(inst[2], str)
                else inst
            )
            for pc, inst in enumerate(self.code)
            if keep[pc]
        ]
        self.labels = {
            label: positions[pc] for label, pc in self.labels.items()
        }
        self.island_sites = {positions[pc] for pc in self.island_sites}

    def relax_branches(self):
        """Route distant branches through islands skipped by normal flow."""
        # shortcut: relays need clear bit 63 at WA boundaries; generalize for non-benchmark programs.
        for _ in range(1000):
            for pc, inst in enumerate(self.code):
                if inst[0] != "toga" or not isinstance(inst[2], str):
                    continue
                target = self.labels[inst[2]]
                if -256 <= target - pc - 1 <= 255:
                    continue
                # Former WA boundaries remain safe after WA removal.
                forward = target > pc
                candidates = [
                    i
                    for i in self.island_sites
                    if (
                        pc + 32 <= i <= pc + 200 < target
                        if forward
                        else target < pc - 200 <= i <= pc - 32
                    )
                ]
                if not candidates:
                    raise ValueError(f"No branch island site at PC {pc}")
                at = max(candidates) if forward else min(candidates)
                relay, after = self.label(), self.label()
                for label, position in self.labels.items():
                    if position >= at:
                        self.labels[label] += 4
                self.island_sites = {
                    i + (4 if i >= at else 0) for i in self.island_sites
                }
                self.code[at:at] = [
                    ("toga", 63, 0),
                    ("toga", 63, after),
                    ("toga", 63, 0),
                    ("toga", 63, inst[2]),
                ]
                self.labels[relay], self.labels[after] = at + 2, at + 4
                self.code[pc + (4 if pc >= at else 0)] = (
                    "toga",
                    inst[1],
                    relay,
                )
                break
            else:
                return
        raise ValueError("Branch relaxation did not converge")

    def assemble(self):
        if not 1 <= len(self.code) <= 32768:
            raise ValueError("Program must contain 1..32768 instructions")
        words = []
        for pc, inst in enumerate(self.code):
            if inst[0] == "wa":
                word = 0x8000 | (inst[1] >> 3)
            elif inst[0] == "wa_indirect":
                word = 0xC000
            elif inst[0] == "halt":
                word = 0
            else:
                _, bit, target = inst
                if isinstance(target, str):
                    if target not in self.labels:
                        raise ValueError(f"Unknown label: {target}")
                    target = self.labels[target] - pc - 1
                if not 0 <= bit < 64 or not -256 <= target <= 255:
                    raise ValueError(f"Unencodable TOGA at PC {pc}")
                word = (bit << 9) | (target & 0x1FF)
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


def make_benchmark(name, *, a=None, b=None, steps=None):
    """Build a benchmark with explicit named inputs and 8-bit arithmetic.

    Incrementer needs a; adder/GCD need a and b; Fibonacci needs steps;
    LFSR needs a and steps. Generated program inputs are in BOUNDARY_INPUTS.
    """
    if name not in BENCHMARKS:
        raise ValueError(f"Unknown benchmark: {name}")
    required = {
        "incrementer": (a,),
        "adder": (a, b),
        "fibonacci": (steps,),
        "gcd": (a, b),
        "lfsr": (a, steps),
    }[name]
    if any(value is None for value in required):
        raise ValueError(f"Explicit inputs are required for {name}")
    if any(not isinstance(value, int) or not 0 <= value <= 255
           for value in (a, b, steps) if value is not None):
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
        p.select_word(A)
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
    p.remove_redundant_wa()
    p.relax_branches()
    p.halt()
    return p, initial, expected


def make_backward_branch_limits():
    """Exercise taken -1 and -256 offsets, with HALT guards on wrong paths."""
    p = Program()
    p.wa(DATA_BASE)
    p.mark("again")
    p.toga(2, "again")
    p.toga(63)
    p.mark("back")
    p.toga(63, "far")
    p.toga(63)
    p.halt()
    while len(p.code) < 258:
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
    p.write(output / "basic_wa.hex", 0x200, [0xA4, 0x5A, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC])

    for name, low_byte in (("basic_toga_no_jump", 0xA0), ("basic_toga_jump", 0xA4)):
        p = Program()
        p.wa(0x200)
        p.toga(2, "new_pc")
        p.halt()
        p.mark("new_pc")
        p.halt()
        p.write(output / f"{name}.hex", 0x200, [low_byte, 0x5A, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC])

    p = Program()
    p.wa(0xFFF8)
    p.toga(63, "far")
    while len(p.code) < 257:
        p.halt()
    p.mark("far")
    p.toga(16)
    p.halt()
    p.write(output / "wa_direct_64.hex", 0xFFF8,
            [0x10, 0x32, 0x54, 0x76, 0x98, 0xBA, 0xDC, 0xFE])

    p = Program()
    p.wa(DATA_BASE)
    p.toggle(0)
    p.wa_indirect()
    p.wa_indirect()
    p.toga(63)
    p.wa(0x5800)
    p.wa_indirect()
    p.toga(31)
    p.halt()
    data = [0x00] * (65536 - DATA_BASE)
    for address, value in ((DATA_BASE, 0x8000000000000B00),
                           (0x57F8, 0x0123456789ABCDEF),
                           (0x5800, 0x0B00), (0x5808, 0xA55A123456781FFF),
                           (0xFFF8, 0x5EF09ABC56781234)):
        data[address - DATA_BASE:address - DATA_BASE + 8] = value.to_bytes(8, "little")
    p.write(output / "wa_indirect.hex", DATA_BASE, data)

    p = Program()
    p.wa(DATA_BASE)
    p.wa_indirect()
    p.halt()
    p.write(output / "wa_indirect_zero.hex", DATA_BASE,
            [0x00, 0x20, 0xAB, 0x89, 0x67, 0x45, 0x23, 0xF1])

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
