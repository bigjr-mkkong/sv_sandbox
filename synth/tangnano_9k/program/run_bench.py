#!/usr/bin/env python3
"""Run every JSON program against the Pi/mux/FPGA circuit.

In the repository: python3 -m synth.tangnano_9k.program.run_bench
On the Pi: python3 run_bench.py (with utils.py and dv/cocotb_benches/programs/ beside it).
Requires python3-spidev, python3-gpiozero, SPI enabled in raspi-config, and
the wiring assumptions documented in utils.py.
"""

from contextlib import closing

from dv.cocotb_benches.programs.dataset import check_memory, initial_regions, load_programs

if __package__:
    from . import utils
else:
    import utils


def run_bench(spi, reset_n, mux, halt, program):
    """Reset, preload, execute and check one validated program dataset."""
    try:
        utils.reset_fpga(spi, reset_n, mux)
        for address, data in initial_regions(program):
            utils.write_ram(spi, address, data)
            if utils.read_ram(spi, address, len(data)) != data:
                raise RuntimeError(f"{program['name']}: preload failed at {address:#06x}")
        if halt.value:
            raise RuntimeError("HALT is high while FPGA is held in reset")
        utils.start_fpga(reset_n, mux)
        utils.wait_for_halt(halt)
        utils.select_pi(reset_n, mux)
        check_memory(program, lambda address, length: utils.read_ram(spi, address, length))
    finally:
        utils.select_pi(reset_n, mux)


def main():
    programs = load_programs()  # Validate every file before touching hardware.
    import spidev
    from gpiozero import DigitalInputDevice, DigitalOutputDevice

    failures = 0
    print("Checking HALT and RAM; internal RTL checks are simulation-only.")
    with DigitalOutputDevice(utils.RESET_GPIO, initial_value=False) as reset_n:
        utils.sleep(utils.SETTLE_SECONDS)
        with (DigitalOutputDevice(utils.MUX_GPIO, initial_value=False) as mux,
              DigitalInputDevice(utils.HALT_GPIO, pull_up=False) as halt,
              closing(spidev.SpiDev()) as spi):
            try:
                utils.select_pi(reset_n, mux)
                spi.open(0, 0)
                spi.mode = 0
                spi.max_speed_hz = 1_000_000
                spi.bits_per_word = 8
                for program in programs:
                    try:
                        run_bench(spi, reset_n, mux, halt, program)
                    except (AssertionError, TimeoutError, RuntimeError) as error:
                        failures += 1
                        print(f"FAIL {program['name']}: {error}")
                    else:
                        print(f"PASS {program['name']}")
            finally:
                utils.select_pi(reset_n, mux)
    print(f"{len(programs) - failures}/{len(programs)} programs passed")
    return int(failures != 0)


if __name__ == "__main__":
    raise SystemExit(main())
