"""Host-only dataset/export checks: python3 -m unittest dv.cocotb_benches.programs.test_dataset."""

import copy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from dv.cocotb_benches.programs.dataset import DATA_DIR, check_memory, initial_regions, load_program, load_programs


class DatasetTest(unittest.TestCase):
    def test_halt_only_ram_access_preserves_preload(self):
        case = load_program(DATA_DIR / "spi_ram_access.json")
        self.assertEqual(case["code"], b"\x00\x00")
        self.assertEqual(case["precondition"]["memory"], case["postcondition"]["memory"])
        self.assertEqual(case["simulation"]["data_transactions"], [])
        memory = bytearray(65536)
        for address, data in initial_regions(case):
            memory[address:address + len(data)] = data
        check_memory(case, lambda address, length: memory[address:address + length])
        memory[0xFFFF] ^= 1
        with self.assertRaisesRegex(AssertionError, "spi_ram_access at 0xfff0"):
            check_memory(case, lambda address, length: memory[address:address + length])

    def test_basic_word_order_and_shared_postconditions(self):
        case = load_program(DATA_DIR / "basic_wa.json")
        self.assertEqual(case["code"], bytes([0x40, 0x80, 0, 0]))
        self.assertEqual(case["simulation"]["registers"]["reg_q"], 0xBC9A785634125AA4)
        memory = bytearray(65536)
        for address, data in initial_regions(case):
            memory[address:address + len(data)] = data
        check_memory(case, lambda address, length: memory[address:address + length])
        memory[0x207] ^= 0x80
        with self.assertRaisesRegex(AssertionError, "basic_wa at 0x0200"):
            check_memory(case, lambda address, length: memory[address:address + length])

    def test_hex_export_matches_every_dataset(self):
        from dv.cocotb_benches.programs.generate import generate

        with TemporaryDirectory() as directory:
            generate(directory)
            for case in load_programs():
                with self.subTest(name=case["name"]):
                    actual, expected = bytearray(65536), bytearray(65536)
                    for line in (Path(directory) / f"{case['name']}.hex").read_text().splitlines():
                        if line.startswith("@"):
                            address = int(line[1:], 16)
                        else:
                            data = bytes.fromhex(line)
                            actual[address:address + len(data)] = data
                            address += len(data)
                    for address, data in initial_regions(case):
                        expected[address:address + len(data)] = data
                    self.assertEqual(actual, expected)

    def test_invalid_datasets_are_rejected(self):
        original = json.loads((DATA_DIR / "basic_wa.json").read_text())
        mutations = [
            lambda c: c.update(schema_version=2),
            lambda c: c.update(schema_version=True),
            lambda c: c.update(code=[]),
            lambda c: c.update(code=["10000"]),
            lambda c: c.update(code=[0x8040]),
            lambda c: c.update(code=["0000"] * 32769),
            lambda c: c["precondition"]["memory"][0].update(address=0),
            lambda c: c["precondition"]["memory"][0].update(address=65535),
            lambda c: c["precondition"]["memory"][0].update(bytes=[True]),
            lambda c: c["precondition"]["memory"][0].update(bytes=[256]),
            lambda c: c["precondition"]["memory"].append(c["precondition"]["memory"][0]),
            lambda c: c["postcondition"].update(halt=False),
            lambda c: c["postcondition"].update(memory=[]),
            lambda c: c["postcondition"].update(memroy=[]),
            lambda c: c["simulation"]["registers"].update(reg_q=0xBC9A785634125AA4),
            lambda c: c["simulation"]["registers"].update(unknown=1),
            lambda c: c["simulation"].update(backward_offsets=[-257]),
            lambda c: c["simulation"].update(data_transactions=[[0, 65536, 0]]),
            lambda c: c["simulation"].update(data_transactions=[[0, 0, 1]]),
        ]
        with TemporaryDirectory() as directory:
            path = Path(directory) / "invalid.json"
            for index, mutate in enumerate(mutations):
                case = copy.deepcopy(original)
                mutate(case)
                path.write_text(json.dumps(case))
                with self.subTest(index=index), self.assertRaises(ValueError):
                    load_program(path)
            path.write_text('{"name":"first", "name":"second"}')
            with self.assertRaisesRegex(ValueError, "Duplicate JSON field"):
                load_program(path)


if __name__ == "__main__":
    unittest.main()
