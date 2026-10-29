"""Run: python3 -m unittest discover -s synth/tangnano_9k/program -p 'test_utils.py'."""

import unittest
from types import SimpleNamespace
from unittest.mock import Mock, call, patch

import utils as ram


class SpiRamTest(unittest.TestCase):
    def test_spi_frames_and_address_boundaries(self):
        spi = Mock()
        ram.write_ram(spi, 0x00FF, [0x12, 0xAB])
        self.assertEqual(spi.xfer2.call_args_list, [
            call([0x02, 0x00, 0xFF, 0x12]), call([0x02, 0x01, 0x00, 0xAB])])
        spi.reset_mock()
        spi.xfer2.side_effect = [[0, 0, 0, 0x35], [0, 0, 0, 0xA6]]
        self.assertEqual(ram.read_ram(spi, 0xFFFE, 2), bytes([0x35, 0xA6]))
        self.assertEqual(spi.xfer2.call_args_list, [
            call([0x03, 0xFF, 0xFE, 0]), call([0x03, 0xFF, 0xFF, 0])])

    def test_invalid_requests_do_not_touch_spi(self):
        spi = Mock()
        for address, length in [(-1, 1), (0, -1), (65535, 2), (65537, 0)]:
            with self.subTest(address=address, length=length):
                with self.assertRaises(ValueError):
                    ram.read_ram(spi, address, length)
        for address, data in [(65535, [1, 2]), (0, [1, 256])]:
            with self.assertRaises(ValueError):
                ram.write_ram(spi, address, data)
        self.assertEqual(ram.read_ram(spi, 65536, 0), b"")
        ram.write_ram(spi, 65536, b"")
        spi.xfer2.assert_not_called()

    def test_bus_handoff_and_halt_timeout(self):
        events = Mock()
        with patch.object(ram, "sleep", events.sleep):
            ram.start_fpga(events.reset_n, events.mux)
            ram.select_pi(events.reset_n, events.mux)
        pause = call.sleep(ram.SETTLE_SECONDS)
        self.assertEqual(events.mock_calls, [
            call.reset_n.off(), pause, call.mux.on(), pause, call.reset_n.on(),
            call.reset_n.off(), pause, call.mux.off(), pause])
        ram.wait_for_halt(SimpleNamespace(value=1), timeout=0)
        with self.assertRaises(TimeoutError):
            ram.wait_for_halt(SimpleNamespace(value=0), timeout=0)

    def test_reset_clears_previous_program_and_data(self):
        memory = bytearray([0xA5]) * ram.RAM_SIZE
        state = SimpleNamespace(mode=0x80, reset=1, mux=1)
        reset_n = Mock()
        mux = Mock()
        reset_n.off.side_effect = lambda: setattr(state, "reset", 0)
        mux.off.side_effect = lambda: setattr(state, "mux", 0)

        def transfer(frame):
            self.assertEqual((state.reset, state.mux), (0, 0))
            if frame[0] == 0x01:
                self.assertEqual(frame, [0x01, 0x00])
                state.mode = frame[1]
            else:
                self.assertEqual(frame[0], 0x02)
                self.assertEqual(len(frame), 4)
                self.assertEqual(state.mode, 0)
                memory[(frame[1] << 8) | frame[2]] = frame[3]
            return [0] * len(frame)

        spi = SimpleNamespace(xfer2=transfer)
        with patch.object(ram, "sleep"):
            ram.reset_fpga(spi, reset_n, mux)
            self.assertEqual(memory, bytes(ram.RAM_SIZE))
            ram.write_ram(spi, 0, bytes([0x12]) * 64)
            memory[0x0200] = 0xAB  # A result left by the first program.
            memory[0xFFFF] = 0xCD
            state.reset = state.mux = 1
            ram.select_pi(reset_n, mux)
            self.assertEqual(memory[0x0200], 0xAB)  # Handoff preserves results.
            ram.reset_fpga(spi, reset_n, mux)
            self.assertEqual(memory, bytes(ram.RAM_SIZE))
            ram.write_ram(spi, 0, [0x56, 0x78])
            self.assertEqual(memory[:64], bytes([0x56, 0x78]) + bytes(62))
        reset_n.on.assert_not_called()
        mux.on.assert_not_called()

    def test_reset_failure_leaves_cpu_stopped(self):
        events = Mock()
        events.spi.xfer2.side_effect = OSError("SPI transfer failed")
        with patch.object(ram, "sleep", events.sleep), self.assertRaises(OSError):
            ram.reset_fpga(events.spi, events.reset_n, events.mux)
        self.assertEqual(events.mock_calls, [
            call.reset_n.off(), call.sleep(ram.SETTLE_SECONDS),
            call.mux.off(), call.sleep(ram.SETTLE_SECONDS),
            call.spi.xfer2([0x01, 0x00])])


if __name__ == "__main__":
    unittest.main()
