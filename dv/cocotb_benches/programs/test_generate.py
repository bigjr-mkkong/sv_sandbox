"""Run with python3 -m unittest dv.cocotb_benches.programs.test_generate."""

from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from dv.cocotb_benches.programs.generate import (
    A, BENCHMARKS, BOUNDARY_INPUTS, Program, make_backward_branch_limits, make_benchmark,
)
from dv.cocotb_benches.programs.dataset import DATA_DIR, initial_regions, load_program


def execute(program, initial):
    """Independent RTL decoder; memory maps byte addresses to 16-bit pieces."""
    words = program.assemble()
    memory = dict(initial)
    pc, address, value, dirty = 0, 0, 0, False
    for _ in range(1_000_000):
        if not 0 <= pc < len(words):
            raise AssertionError(f"Branch outside program: {pc}")
        word = words[pc]
        pc += 1
        if dirty and (word == 0 or word & 0x8000):
            for offset in range(0, 8, 2):
                memory[address + offset] = (value >> (8 * offset)) & 0xFFFF
        if word == 0:
            if pc != len(words):
                raise AssertionError(f"Premature HALT at PC {pc - 1}")
            return memory
        if word & 0x8000:
            operand = value if word & 0x4000 else word & 0x3FFF
            address = (operand * 8) & 0xFFFF
            value = sum(memory.get(address + offset, 0) << (8 * offset)
                        for offset in range(0, 8, 2))
            dirty = False
        else:
            bit = (word >> 9) & 63
            offset = word & 0x1FF
            if offset & 0x100:
                offset -= 0x200
            value ^= 1 << bit
            dirty = True
            if not value & (1 << bit):
                pc = (pc + offset) & 0xFFFF
    raise AssertionError("Program did not halt")


class AssemblerTest(unittest.TestCase):
    def test_encoding_and_labels(self):
        p = Program()
        p.mark("start")
        p.wa(0x200)
        p.toga(2, "end")
        p.toga(63, "start")
        p.mark("end")
        p.halt()
        self.assertEqual(p.assemble(), [0x8040, 0x0401, 0x7FFD, 0])
        self.assertEqual(p.assemble(), [0x8040, 0x0401, 0x7FFD, 0])

    def test_encoding_boundaries(self):
        p = Program()
        p.wa(0)
        p.wa(0xFFF8)
        p.wa_indirect()
        p.toga(0, -256)
        p.toga(63, 255)
        self.assertEqual(p.assemble(), [0x8000, 0x9FFF, 0xC000, 0x0100, 0x7EFF])

    def test_invalid_operands(self):
        for address in (-8, 1, 2, 4, 0xFFFE, 65536):
            with self.subTest(address=address), self.assertRaises(ValueError):
                Program().wa(address)
        for bit, target in ((-1, 1), (64, 1), (1, -257), (1, 256), (0, 0), (1, "missing")):
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
            expected = "@0000\n40 80\n00 00\n@0200\na4 5a\n"
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

    def test_all_register_bits(self):
        for bit in range(64):
            for value in (0, (1 << 64) - 1):
                p = Program()
                p.wa(A)
                p.toggle(bit)
                p.halt()
                initial = {A + offset: (value >> (8 * offset)) & 0xFFFF
                           for offset in range(0, 8, 2)}
                memory = execute(p, initial)
                actual = sum(memory[A + offset] << (8 * offset) for offset in range(0, 8, 2))
                self.assertEqual(actual, value ^ (1 << bit))

    def test_indirect_dirty_pointer_and_upper_address(self):
        p = Program()
        p.wa(A)
        p.toggle(0)
        p.wa_indirect()
        p.wa_indirect()
        p.toga(63)
        p.halt()
        memory = execute(p, {A: 0x0B00, A + 6: 0x8000, 0x5808: 0x1FFF,
                             0xFFF8: 0x1234, 0xFFFA: 0x5678, 0xFFFC: 0x9ABC,
                             0xFFFE: 0x5EF0})
        self.assertEqual(memory[A], 0x0B01)
        self.assertEqual(memory[A + 6], 0x8000)
        self.assertEqual([memory[a] for a in range(0xFFF8, 0x10000, 2)],
                         [0x1234, 0x5678, 0x9ABC, 0xDEF0])

    def test_wa_optimization_preserves_halt_distinction(self):
        for value in (0, 1):
            p = Program()
            p.wa(A)
            p.toga(0, 1)
            p.wa(A)
            p.remove_redundant_wa()
            p.halt()
            self.assertEqual(execute(p, {A: value})[A], value ^ 1)
            self.assertNotIn(0, p.assemble()[:-1])

    def test_wa_optimization_rejects_indirect(self):
        p = Program()
        p.wa_indirect()
        with self.assertRaises(ValueError):
            p.remove_redundant_wa()

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

    def test_benchmark_datasets_match_assembler(self):
        for name in (*BENCHMARKS, "fibonacci_overflow"):
            with self.subTest(name=name):
                case = load_program(DATA_DIR / f"{name}.json")
                benchmark = "fibonacci" if name == "fibonacci_overflow" else name
                program, initial, expected = make_benchmark(benchmark, **case["inputs"])
                code = b"".join(word.to_bytes(2, "little") for word in program.assemble())
                self.assertEqual(case["code"], code)
                memory = bytearray(65536)
                for address, data in initial_regions(case):
                    memory[address:address + len(data)] = data
                for address in range(A, A + 16, 2):
                    self.assertEqual(int.from_bytes(memory[address:address + 2], "little"),
                                     initial.get(address, 0))
                for block in case["postcondition"]["memory"]:
                    memory[block["address"]:block["address"] + len(block["bytes"])] = block["bytes"]
                for address, value in expected.items():
                    self.assertEqual(int.from_bytes(memory[address:address + 2], "little"), value)

    def test_backward_branch_limits(self):
        words = make_backward_branch_limits().assemble()
        self.assertEqual(words[1], (2 << 9) | 0x1FF)
        self.assertEqual(words[3], (63 << 9) | 254)
        self.assertEqual(words[258], (2 << 9) | 0x100)

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
