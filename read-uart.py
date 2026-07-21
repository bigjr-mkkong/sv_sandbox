#!/usr/bin/env python3
"""Print bytes received from a UART as hexadecimal and text."""

import argparse


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default="/dev/ttyUSB0", help="serial device")
    parser.add_argument("--baud", type=int, default=115_200, help="baud rate")
    args = parser.parse_args()

    try:
        import serial
    except ModuleNotFoundError as error:
        raise SystemExit("pyserial is missing; run 'make setup'") from error

    with serial.Serial(args.port, args.baud, timeout=1) as uart:
        print(f"Reading {args.port} at {args.baud} baud; press Ctrl-C to stop.")
        try:
            while True:
                data = uart.read(1)
                if data:
                    character = data.decode(errors="replace")
                    print(f"0x{data.hex()}  {character}")
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
