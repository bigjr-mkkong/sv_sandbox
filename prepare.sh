#!/bin/bash
set -e  # Exit on error

source venv/bin/activate

RTL_FILES=".rtl_flist.tmp"
export BASEJUMP_STL_DIR="$(realpath third_party/basejump_stl)"

rm -f $RTL_FILES
rm -rf _rtl/

echo "[*] Touching $RTL_FILES"
touch "$RTL_FILES"

echo "[*] Rendering rtl"
python3 misc/rtl_renderer.py

echo "[*] Generating top module flist"
python3 misc/convert_filelist.py Makefile _rtl/rtl.flist > "$RTL_FILES"

echo "[*] Generating IPs.flist for taxi_uart"
python3 misc/third_party_flist.py third_party/taxi/src/lss/rtl/taxi_uart.f >> "$RTL_FILES"

deactivate
