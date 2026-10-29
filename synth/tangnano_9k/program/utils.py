#!/usr/bin/env python3
"""Raspberry Pi helpers for a 23LC512 and a level-controlled SPI bus mux.

The entry point is run_bench.py; this module only controls SPI and GPIO.
Call reset_fpga(spi, reset_n, mux) before each new program: it holds the CPU
in reset and clears all RAM. Check the previous result before calling it.

Example BCM GPIO assignments (edit for your circuit):
  SPI0: MOSI=10, MISO=9, SCLK=11, CE0=8 -> mux Pi-side SPI connections.
  GPIO17 -> mux select: low=Pi, high=FPGA; hold the level, do not pulse it.
  GPIO27 -> FPGA pin 29 (active-low reset).
  GPIO22 <- FPGA pin 30 (active-high HALT).
  FPGA SPI mux connections: CS=25, SCLK=26, MOSI=27, MISO=28.

Use 3.3 V logic and common ground. The mux must isolate the two masters,
including CS; RAM /CS needs a pull-up, and /HOLD and SIO2 must be held high.
External reset/select pull-downs must hold reset and select Pi while this
process is absent (the FPGA currently has an internal reset pull-up).
Assumes a programmed FPGA with a running PLL, and RAM in single-bit SPI mode.
"""

from time import monotonic, sleep

MUX_GPIO = 17
RESET_GPIO = 27
HALT_GPIO = 22
RAM_SIZE = 65536
SETTLE_SECONDS = 0.001


def check_range(address, length):
    if not 0 <= address <= RAM_SIZE or not 0 <= length <= RAM_SIZE - address:
        raise ValueError("Access must stay within the 23LC512's 64 KiB")


def read_ram(spi, address, length):
    """Read bytes while the mux selects Pi and the FPGA is held in reset."""
    check_range(address, length)
    # shortcut: one byte per CS frame; use sequential bursts for faster bulk loads.
    return bytes(spi.xfer2([0x03, addr >> 8, addr & 0xFF, 0x00])[-1]
                 for addr in range(address, address + length))


def write_ram(spi, address, data):
    """Write bytes while Pi owns the bus; validate the whole payload first."""
    data = bytes(data)
    check_range(address, len(data))
    for addr, value in enumerate(data, address):
        spi.xfer2([0x02, addr >> 8, addr & 0xFF, value])


def select_pi(reset_n, mux):
    reset_n.off()
    sleep(SETTLE_SECONDS)  # Allow the clocked SPI master to return CS high.
    mux.off()
    sleep(SETTLE_SECONDS)


def reset_fpga(spi, reset_n, mux):
    """Prepare a new test; leave reset asserted and RAM connected to the Pi.

    The SPI device must already be open/configured in single-bit SPI mode.
    All previous program/data bytes are discarded; this does not reload the FPGA.
    """
    select_pi(reset_n, mux)
    spi.xfer2([0x01, 0x00])  # WRMR: restore byte-access mode.
    # The 23LC512 has no memory-clear reset, so overwrite its entire array.
    write_ram(spi, 0, bytes(RAM_SIZE))


def start_fpga(reset_n, mux):
    reset_n.off()
    sleep(SETTLE_SECONDS)
    mux.on()
    sleep(SETTLE_SECONDS)
    reset_n.on()


def wait_for_halt(halt, timeout=10.0):
    deadline = monotonic() + timeout
    while not halt.value:
        if monotonic() >= deadline:
            raise TimeoutError("FPGA did not assert HALT")
        sleep(0.001)

