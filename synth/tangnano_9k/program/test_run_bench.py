"""Host-only runner checks; no GPIO or SPI device is opened."""

from contextlib import redirect_stdout
from io import StringIO
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, Mock, patch

from dv.cocotb_benches.programs.dataset import DATA_DIR, initial_regions, load_program
import run_bench as bench


class BenchTest(unittest.TestCase):
    def test_repeated_scenarios_and_corrupt_result(self):
        memory = bytearray(65536)
        state = SimpleNamespace(reset=1, mux=1)
        halt = SimpleNamespace(value=0)

        def assert_reset():
            state.reset = 0
            halt.value = 0

        reset_n = SimpleNamespace(off=assert_reset, on=lambda: setattr(state, "reset", 1))
        mux = SimpleNamespace(off=lambda: setattr(state, "mux", 0),
                              on=lambda: setattr(state, "mux", 1))

        def transfer(frame):
            self.assertEqual((state.reset, state.mux), (0, 0))
            if frame[0] == 0x01:
                return [0, 0]
            address = (frame[1] << 8) | frame[2]
            if frame[0] == 0x02:
                memory[address] = frame[3]
            else:
                self.assertEqual(frame[0], 0x03)
            return [0, 0, 0, memory[address]]

        spi = SimpleNamespace(xfer2=transfer)
        for name, corrupt in [("spi_ram_access", False), ("spi_ram_access", True),
                              ("basic_wa", False), ("basic_toga_jump", False),
                              ("basic_toga_jump", True)]:
            program = load_program(DATA_DIR / f"{name}.json")
            memory[0x100] = 0xA5  # Each new scenario must clear stale data.

            def emulate_completion(_halt):
                self.assertEqual((state.reset, state.mux), (1, 1))
                self.assertEqual(memory[0x100], 0)
                for address, data in initial_regions(program):
                    self.assertEqual(memory[address:address + len(data)], data)
                for block in program["postcondition"]["memory"]:
                    address, data = block["address"], block["bytes"]
                    if program["code"] != b"\x00\x00":
                        memory[address:address + len(data)] = data
                if corrupt:
                    memory[address] ^= 1
                halt.value = 1

            with (patch.object(bench.utils, "sleep"),
                  patch.object(bench.utils, "wait_for_halt", side_effect=emulate_completion)):
                if corrupt:
                    address = program["postcondition"]["memory"][-1]["address"]
                    with self.assertRaisesRegex(AssertionError, f"{name} at {address:#06x}"):
                        bench.run_bench(spi, reset_n, mux, halt, program)
                else:
                    bench.run_bench(spi, reset_n, mux, halt, program)
            self.assertEqual((state.reset, state.mux), (0, 0))

    def test_main_runs_all_entries_and_reports_failure(self):
        programs = [{"name": "first"}, {"name": "second"}]
        fake_gpio = SimpleNamespace(DigitalOutputDevice=MagicMock(), DigitalInputDevice=MagicMock())
        fake_spi = SimpleNamespace(SpiDev=Mock())
        with (patch.dict("sys.modules", {"spidev": fake_spi, "gpiozero": fake_gpio}),
              patch.object(bench, "load_programs", return_value=programs),
              patch.object(bench.utils, "sleep"), patch.object(bench.utils, "select_pi"),
              patch.object(bench, "run_bench", side_effect=[AssertionError("bad result"), None]) as run,
              redirect_stdout(StringIO()) as output):
            self.assertEqual(bench.main(), 1)
        self.assertEqual([entry.args[-1] for entry in run.call_args_list], programs)
        self.assertIn("FAIL first", output.getvalue())
        self.assertIn("PASS second", output.getvalue())
        self.assertIn("1/2 programs passed", output.getvalue())
        fake_spi.SpiDev.return_value.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
