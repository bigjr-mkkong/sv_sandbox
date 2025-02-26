import serial

ser = serial.Serial('/dev/ttyUSB1', 115200, timeout=1)

while True:
    data = ser.read(1)
    print(f"Received: {data.hex()} (ASCII: {data.decode(errors='ignore')})")
