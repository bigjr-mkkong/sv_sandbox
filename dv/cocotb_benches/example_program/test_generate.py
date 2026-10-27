"""Run with python3 -m unittest dv.cocotb_benches.example_program.test_generate."""

from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from dv.cocotb_benches.example_program.generate import (
    A, BENCHMARKS, BOUNDARY_INPUTS, Program, make_backward_branch_limits, make_benchmark,
)


def execute(program, initial):
    """Independent RTL-instruction interpreter, including HALT/writeback."""
    words = program.assemble()
    memory = dict(initial)
    pc, address, value, dirty = 0, 0, 0, False
    for _ in range(1_000_000):
        if not 0 <= pc < len(words):
            raise AssertionError(f"Branch outside program: {pc}")
        word = words[pc]
        pc += 1
        if word == 0:
            if dirty:
                memory[address] = value
            if pc != len(words):
                raise AssertionError(f"Premature HALT at PC {pc - 1}")
            return memory
        if word & 0x8000:
            if dirty:
                memory[address] = value
            address = (word & 0x7FFF) * 2
            value = memory.get(address, 0)
            dirty = False
        else:
            bit = (word >> 11) & 15
            offset = word & 0x7FF
            if offset & 0x400:
                offset -= 0x800
            value ^= 1 << bit
            dirty = True
            if not value & (1 << bit):
                pc += offset
    raise AssertionError("Program did not halt")


class AssemblerTest(unittest.TestCase):
    def test_encoding_and_labels(self):
        p = Program()
        p.mark("start")
        p.wa(0x200)
        p.toga(2, "end")
        p.toga(15, "start")
        p.mark("end")
        p.halt()
        self.assertEqual(p.assemble(), [0x8100, 0x1001, 0x7FFD, 0])
        self.assertEqual(p.assemble(), [0x8100, 0x1001, 0x7FFD, 0])

    def test_encoding_boundaries(self):
        p = Program()
        p.wa(0)
        p.wa(0xFFFE)
        p.toga(0, -1024)
        p.toga(15, 1023)
        self.assertEqual(p.assemble(), [0x8000, 0xFFFF, 0x0400, 0x7BFF])

    def test_invalid_operands(self):
        for address in (-2, 1, 65536):
            with self.subTest(address=address), self.assertRaises(ValueError):
                Program().wa(address)
        for bit, target in ((-1, 1), (16, 1), (1, -1025), (1, 1024), (0, 0), (1, "missing")):
            p = Program()
            p.toga(bit, target)
            with self.subTest(bit=bit, target=target), self.assertRaises(ValueError):
                p.assemble()
        p = Program()
        with self.assertRaises(ValueError):
            p.assemble()
        p.mark("duplicate")
        with self.assertRaises(ValueError):
            p.mark("duplicate")

    def test_memory_image(self):
        p = Program()
        p.wa(0x200)
        p.halt()
        with TemporaryDirectory() as directory:
            path = Path(directory) / "program.hex"
            p.write(path, 0x200, [0xA4, 0x5A])
            expected = "@0000\n00 81\n00 00\n@0200\na4 5a\n"
            self.assertEqual(path.read_text(), expected)
            for address, data in ((2, [0]), (65535, [0, 1]), (0x200, [256])):
                with self.subTest(address=address, data=data), self.assertRaises(ValueError):
                    p.write(path, address, data)
                self.assertEqual(path.read_text(), expected)

    def test_benchmarks(self):
        cases = [(name, 13, 7, 8) for name in BENCHMARKS]
        cases.extend(("incrementer", a, 0, 0) for a in range(256))
        edges = (0, 1, 2, 127, 128, 254, 255)
        for name in ("adder", "gcd"):
            cases.extend((name, a, b, 0) for a in edges for b in edges)
        cases.extend(("fibonacci", 0, 0, steps) for steps in (0, 1, 2, 8, 13, 24, 255))
        cases.extend(
            ("lfsr", seed, 0, steps)
            for seed in (0, 1, 13, 255)
            for steps in (0, 1, 2, 8, 255)
        )
        for name, a, b, steps in cases:
            with self.subTest(name=name, a=a, b=b, steps=steps):
                p, initial, expected = make_benchmark(name, a=a, b=b, steps=steps)
                memory = execute(p, initial)
                for address, value in expected.items():
                    self.assertEqual(memory[address], value)
                self.assertTrue(all(value <= 0xFF for value in memory.values()))

    def test_bit_zero_toggle(self):
        for value in (0, 1, 0x8000, 0x8001):
            p = Program()
            p.wa(A)
            p.toggle(0)
            p.halt()
            self.assertEqual(execute(p, {A: value})[A], value ^ 1)

    def test_boundary_inputs(self):
        for name, inputs in BOUNDARY_INPUTS.items():
            with self.subTest(name=name):
                p, initial, expected = make_benchmark(name, **inputs)
                memory = execute(p, initial)
                for address, value in expected.items():
                    self.assertEqual(memory[address], value)
                self.assertTrue(all(value <= 0xFF for value in memory.values()))
        self.assertEqual(make_benchmark("fibonacci", steps=13)[2][A + 4], 233)
        p, initial, expected = make_benchmark("fibonacci", steps=14)
        self.assertEqual(expected[A + 4], 377 & 0xFF)
        self.assertEqual(execute(p, initial)[A + 4], 121)

    def test_backward_branch_limits(self):
        words = make_backward_branch_limits().assemble()
        self.assertEqual(words[1], (2 << 11) | 0x7FF)
        self.assertEqual(words[3], (15 << 11) | 1022)
        self.assertEqual(words[1026], (2 << 11) | 0x400)

    def test_invalid_benchmark(self):
        for name, a, b, steps in (("unknown", 0, 0, 0), ("adder", -1, 0, 0), ("gcd", 0, 256, 0), ("lfsr", 0, 0, -1)):
            with self.subTest(name=name, a=a, b=b, steps=steps), self.assertRaises(ValueError):
                make_benchmark(name, a=a, b=b, steps=steps)

    def test_missing_benchmark_inputs(self):
        cases = [(name, {}) for name in BENCHMARKS]
        cases.extend((name, {"a": 255}) for name in ("adder", "gcd", "lfsr"))
        for name, inputs in cases:
            with self.subTest(name=name, inputs=inputs), self.assertRaises(ValueError):
                make_benchmark(name, **inputs)


if __name__ == "__main__":
    unittest.main()
