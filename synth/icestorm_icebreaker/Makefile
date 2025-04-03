TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(shell pwd)/icebreaker.v $(shell pwd)/uart/uart_tx.v
TOPLEVEL = icebreaker
MODULE = modtest

export PYTHON_BIN = python3
SIM = verilator  # or use verilator, modelsim, etc.

COMPILE_ARGS += $(INCLUDES)
COMPILE_ARGS += -Wno-fatal

EXTRA_ARGS += --trace --trace-fst --trace-structs

include $(shell cocotb-config --makefiles)/Makefile.sim

