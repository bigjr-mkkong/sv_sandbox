SHELL := /bin/bash
.DEFAULT_GOAL := help

PROJECT_ROOT := $(abspath .)
OSS_CAD_SUITE ?= /opt/oss-cad-suite
VENV ?= $(PROJECT_ROOT)/venv
VENV_PYTHON ?= $(shell pyenv which python3 2>/dev/null || command -v python3)

ifneq ($(wildcard $(OSS_CAD_SUITE)/bin),)
export PATH := $(OSS_CAD_SUITE)/bin:$(OSS_CAD_SUITE)/py3bin:$(PATH)
export VERILATOR_ROOT := $(OSS_CAD_SUITE)/share/verilator
export GHDL_PREFIX := $(OSS_CAD_SUITE)/lib/ghdl
endif

ifneq ($(wildcard $(VENV)/bin/python3),)
export PATH := $(VENV)/bin:$(PATH)
PYTHON ?= $(VENV)/bin/python3
else
PYTHON ?= python3
endif

TOP := top_module
TOP_TB := $(TOP)_tb

RTL_MANIFEST := rtl/rtl.flist
RTL_INPUTS := $(shell sed -e 's,//.*,,' -e '/^[[:space:]]*$$/d' $(RTL_MANIFEST))
RTL_TEMPLATES := $(filter rtl/%,$(RTL_INPUTS))
RTL_VENDOR_SOURCES := $(filter-out rtl/%,$(RTL_INPUTS))
RTL_RENDERED := $(patsubst rtl/%,build/rtl/%,$(RTL_TEMPLATES))
RTL_SOURCES := $(RTL_VENDOR_SOURCES) $(RTL_RENDERED)
RTL_FILELIST := build/rtl/rtl.flist
RTL_STAMP := build/rtl/.prepared
RTL_TREE_INPUTS := $(shell find rtl -type f)
UNIT_TEST_MANIFEST := build/.unit-test.json

DV_SOURCES := dv/dv_pkg.sv dv/top_module_runner.sv dv/top_module_tb.sv
SIM_DIR := build/sim
SIM_BINARY := $(SIM_DIR)/V$(TOP_TB)

YOSYS_DATDIR = $(shell yosys-config --datdir 2>/dev/null)
YOSYS_NETLIST := build/yosys/synth.v
ICE_DIR := build/icebreaker
ICE_PLL := $(ICE_DIR)/icebreaker_pll.v
ICE_NETLIST := $(ICE_DIR)/synth.v
ICE_JSON := $(ICE_DIR)/synth.json
ICE_SIM_NETLIST := $(ICE_DIR)/synth_sim.v
ICE_ASC := $(ICE_DIR)/icebreaker.asc
ICE_BITSTREAM := $(ICE_DIR)/icebreaker.bit
VIVADO_BITSTREAM := synth/vivado_basys3/build/basys3/basys3.runs/impl_1/basys3.bit

.PHONY: help setup doctor prepare lint compile test test-cocotb unit-test synth yosys \
	test-gls icebreaker-pll icebreaker-synth icebreaker-bitstream test-icebreaker-gls \
	check-vivado-sources vivado-bitstream program-icebreaker flash-icebreaker program-basys3 \
	check clean FORCE

.NOTPARALLEL: check

help:
	@echo "SystemVerilog template targets"
	@echo "  make setup                 Create venv and install Python tools"
	@echo "  make doctor                Check the local toolchain and submodules"
	@echo "  make lint                  Lint the rendered RTL with Verilator"
	@echo "  make compile               Compile the SystemVerilog testbench"
	@echo "  make test                  Run the SystemVerilog testbench"
	@echo "  make test-cocotb           Run the RTL cocotb test"
	@echo "  make unit-test             Run registered RTL unit tests"
	@echo "  make synth                 Build a generic Yosys netlist"
	@echo "  make test-gls              Test the generic post-synthesis netlist"
	@echo "  make icebreaker-pll        Generate the iCEBreaker PLL source"
	@echo "  make icebreaker-bitstream  Build the iCEBreaker bitstream"
	@echo "  make test-icebreaker-gls   Test the iCE40-mapped netlist"
	@echo "  make check-vivado-sources  Syntax-check the Basys 3 source set"
	@echo "  make vivado-bitstream      Build the Basys 3 bitstream with Vivado"
	@echo "  make check                 Run every open-source check above"
	@echo "  make clean                 Remove generated files"

setup:
	$(VENV_PYTHON) -m venv $(VENV)
	$(VENV)/bin/python3 -m pip install -r requirements.txt

doctor:
	@command -v verilator >/dev/null || { echo "error: verilator not found" >&2; exit 1; }
	@command -v yosys >/dev/null || { echo "error: yosys not found" >&2; exit 1; }
	@command -v nextpnr-ice40 >/dev/null || { echo "error: nextpnr-ice40 not found" >&2; exit 1; }
	@command -v icepack >/dev/null || { echo "error: icepack not found" >&2; exit 1; }
	@command -v icepll >/dev/null || { echo "error: icepll not found" >&2; exit 1; }
	@command -v cocotb-config >/dev/null || { echo "error: cocotb-config not found" >&2; exit 1; }
	@$(PYTHON) -c 'import jinja2, serial' || { echo "error: run 'make setup' to install Python dependencies" >&2; exit 1; }
	@test -f third_party/taxi/src/lss/rtl/taxi_uart.sv || { echo "error: initialize git submodules" >&2; exit 1; }
	@yosys -m slang -Q -p 'help read_slang' >/dev/null || { echo "error: Yosys Slang plugin not available" >&2; exit 1; }
	@echo "Toolchain and submodules are ready."

$(RTL_STAMP) $(UNIT_TEST_MANIFEST) &: prepare.sh misc/rtl_renderer.py $(RTL_TREE_INPUTS)
	./prepare.sh
	@touch $(RTL_STAMP)

$(RTL_RENDERED) $(RTL_FILELIST): $(RTL_STAMP)

prepare: $(RTL_STAMP) $(UNIT_TEST_MANIFEST)

lint: $(RTL_STAMP) $(RTL_SOURCES) lint/verilator.vlt
	verilator lint/verilator.vlt --lint-only --Wall --top-module $(TOP) $(RTL_SOURCES)

$(SIM_BINARY): $(RTL_STAMP) $(RTL_SOURCES) $(DV_SOURCES) dv/dv.flist lint/verilator.vlt
	@mkdir -p $(SIM_DIR)
	verilator lint/verilator.vlt --Mdir $(SIM_DIR) --binary --top-module $(TOP_TB) \
		$(RTL_SOURCES) -f dv/dv.flist -o V$(TOP_TB)

compile: $(SIM_BINARY)

test: $(SIM_BINARY)
	$(SIM_BINARY) +verilator+rand+reset+2

test-cocotb: $(RTL_STAMP) $(RTL_SOURCES) Makefile.cocotb dv/cocotb_benches/topmod_tb0.py
	$(MAKE) -f Makefile.cocotb \
		SIM_BUILD=build/cocotb-rtl \
		COCOTB_RESULTS_FILE=$(abspath build/cocotb-rtl/results.xml) \
		USER_SIM_ARGS="--trace-file $(abspath build/cocotb-rtl/dump.vcd)" \
		VERILOG_SOURCES="$(RTL_SOURCES)" \
		COCOTB_TOPLEVEL=$(TOP) \
		COCOTB_TEST_MODULES=dv.cocotb_benches.topmod_tb0

unit-test: $(UNIT_TEST_MANIFEST) misc/unit-test.py Makefile.cocotb
	$(PYTHON) misc/unit-test.py --manifest $(UNIT_TEST_MANIFEST) --rtl-dir build/rtl

$(YOSYS_NETLIST): $(RTL_STAMP) $(RTL_SOURCES) synth/yosys_generic/yosys.tcl
	@mkdir -p $(dir $@)
	yosys -m slang -p 'tcl synth/yosys_generic/yosys.tcl $(RTL_FILELIST) $@' \
		-l build/yosys/yosys.log

synth yosys: $(YOSYS_NETLIST)

test-gls: $(YOSYS_NETLIST) Makefile.cocotb dv/cocotb_benches/topmod_tb0.py
	$(MAKE) -f Makefile.cocotb \
		SIM_BUILD=build/cocotb-gls \
		COCOTB_RESULTS_FILE=$(abspath build/cocotb-gls/results.xml) \
		USER_SIM_ARGS="--trace-file $(abspath build/cocotb-gls/dump.vcd)" \
		VERILOG_SOURCES="$(YOSYS_DATDIR)/simlib.v $(YOSYS_NETLIST)" \
		USER_COMPILE_ARGS="lint/verilator.vlt --bbox-unsup" \
		COCOTB_TOPLEVEL=$(TOP) \
		COCOTB_TEST_MODULES=dv.cocotb_benches.topmod_tb0

FORCE:

$(ICE_PLL): FORCE
	@mkdir -p $(dir $@)
	icepll -q -i 12 -o 48 -p -m -n icebreaker_pll -f $@

icebreaker-pll: $(ICE_PLL)

$(ICE_NETLIST) $(ICE_JSON) &: $(RTL_STAMP) $(RTL_SOURCES) \
		$(ICE_PLL) synth/icestorm_icebreaker/icebreaker.v \
		synth/icestorm_icebreaker/yosys.tcl
	@mkdir -p $(ICE_DIR)
	yosys -m slang -p 'tcl synth/icestorm_icebreaker/yosys.tcl hardware $(RTL_FILELIST) synth/icestorm_icebreaker/icebreaker.v $(ICE_NETLIST) $(ICE_PLL) $(YOSYS_DATDIR)/ice40/cells_sim.v $(ICE_JSON)' \
		-l $(ICE_DIR)/yosys.log

icebreaker-synth: $(ICE_NETLIST) $(ICE_JSON)

$(ICE_SIM_NETLIST): $(RTL_STAMP) $(RTL_SOURCES) \
		synth/icestorm_icebreaker/icebreaker.v synth/icestorm_icebreaker/yosys.tcl
	@mkdir -p $(ICE_DIR)
	yosys -m slang -p 'tcl synth/icestorm_icebreaker/yosys.tcl simulation $(RTL_FILELIST) synth/icestorm_icebreaker/icebreaker.v $@' \
		-l $(ICE_DIR)/yosys-sim.log

$(ICE_ASC): $(ICE_JSON) synth/icestorm_icebreaker/netpnr.pcf synth/icestorm_icebreaker/nextpnr.py
	nextpnr-ice40 --json $(ICE_JSON) --up5k --package sg48 \
		--pre-pack synth/icestorm_icebreaker/nextpnr.py \
		--pcf synth/icestorm_icebreaker/netpnr.pcf --pcf-allow-unconstrained --asc $@

$(ICE_BITSTREAM): $(ICE_ASC)
	icepack $< $@

icebreaker-bitstream: $(ICE_BITSTREAM)

test-icebreaker-gls: $(ICE_SIM_NETLIST) Makefile.cocotb \
		dv/ICE_cocotb_benches/ice_topmod_tb0.py
	$(MAKE) -f Makefile.cocotb \
		SIM_BUILD=build/cocotb-icebreaker-gls \
		COCOTB_RESULTS_FILE=$(abspath build/cocotb-icebreaker-gls/results.xml) \
		USER_SIM_ARGS="--trace-file $(abspath build/cocotb-icebreaker-gls/dump.vcd)" \
		VERILOG_SOURCES="$(YOSYS_DATDIR)/ice40/cells_sim.v $(ICE_SIM_NETLIST)" \
		USER_COMPILE_ARGS="lint/verilator.vlt -DNO_ICE40_DEFAULT_ASSIGNMENTS" \
		COCOTB_TOPLEVEL=icebreaker \
		COCOTB_TEST_MODULES=dv.ICE_cocotb_benches.ice_topmod_tb0

check-vivado-sources: $(RTL_STAMP) $(RTL_SOURCES) synth/vivado_basys3/basys3.sv
	yosys -m slang -Q -p 'read_slang --lint-only --ignore-unknown-modules --top basys3 -f $(RTL_FILELIST) synth/vivado_basys3/basys3.sv'

$(VIVADO_BITSTREAM): $(RTL_STAMP) $(RTL_SOURCES) synth/vivado_basys3/basys3.sv \
		synth/vivado_basys3/Basys3_Master.xdc synth/vivado_basys3/constraints.xdc \
		synth/vivado_basys3/vivado.tcl
	@command -v vivado >/dev/null || { echo "error: Vivado is required for this target" >&2; exit 1; }
	vivado -quiet -nolog -nojournal -notrace -mode batch \
		-source synth/vivado_basys3/vivado.tcl -tclargs $(abspath $(RTL_SOURCES))

vivado-bitstream: $(VIVADO_BITSTREAM)

program-icebreaker: $(ICE_BITSTREAM)
	openFPGALoader -b ice40_generic $<

flash-icebreaker: $(ICE_BITSTREAM)
	openFPGALoader -f -b ice40_generic $<

program-basys3: $(VIVADO_BITSTREAM)
	openFPGALoader -b basys3 $<

check: doctor lint unit-test test test-cocotb synth test-gls icebreaker-bitstream \
	test-icebreaker-gls check-vivado-sources

clean:
	rm -rf build synth/vivado_basys3/build _rtl sim_build \
		top_module_tb_sim_dir top_module_tb_gls_dir top_module_gls_dir \
		__pycache__ misc/__pycache__ dv/cocotb_benches/__pycache__ \
		dv/ICE_cocotb_benches/__pycache__
	rm -f dump.vcd dump.fst results.xml IPs.flist .rtl_flist.tmp
