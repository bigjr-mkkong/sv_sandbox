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

RTL_MANIFEST := rtl/rtl.flist
RTL_INPUTS := $(shell sed -e 's,//.*,,' -e '/^[[:space:]]*$$/d' $(RTL_MANIFEST))
RTL_TEMPLATES := $(filter rtl/%,$(RTL_INPUTS))
RTL_VENDOR_SOURCES := $(filter-out rtl/%,$(RTL_INPUTS))
RTL_RENDERED := $(patsubst rtl/%,build/rtl/%,$(RTL_TEMPLATES))
RTL_SOURCES := $(RTL_VENDOR_SOURCES) $(RTL_RENDERED)
RTL_INCLUDE_FLAGS := -Ithird_party/basejump_stl/bsg_misc
RTL_HEADERS := third_party/basejump_stl/bsg_misc/bsg_defines.sv
RTL_FILELIST := build/rtl/rtl.flist
RTL_STAMP := build/rtl/.prepared
RTL_TREE_INPUTS := $(shell find rtl -type f)
UNIT_TEST_MANIFEST := build/.unit-test.json

YOSYS_DATDIR = $(shell yosys-config --datdir 2>/dev/null)
YOSYS_NETLIST := build/yosys/synth.v
ORFS_HOME ?= $(abspath ../OpenROAD-flow-scripts)
ORFS_IMAGE ?= openroad/orfs:latest
ORFS_DESIGN_CONFIG ?= /work/openroad/config.mk
DEFAULT_GOAL ?= all
QT_QPA_PLATFORM ?= offscreen
ICE_DIR := build/icebreaker
ICE_PLL := $(ICE_DIR)/icebreaker_pll.v
ICE_NETLIST := $(ICE_DIR)/synth.v
ICE_JSON := $(ICE_DIR)/synth.json
ICE_ASC := $(ICE_DIR)/icebreaker.asc
ICE_BITSTREAM := $(ICE_DIR)/icebreaker.bit
TANG_DIR := build/tangnano_9k
TANG_PLL := $(TANG_DIR)/tangnano_9k_pll.v
TANG_JSON := $(TANG_DIR)/synth.json
TANG_ROUTED := $(TANG_DIR)/routed.json
TANG_BITSTREAM := $(TANG_DIR)/tangnano_9k.fs
VIVADO_BITSTREAM := synth/vivado_basys3/build/basys3/basys3.runs/impl_1/basys3.bit

.PHONY: help setup doctor prepare lint test-cocotb unit-test synth yosys orfs \
	icebreaker-pll icebreaker-synth icebreaker-bitstream \
	tangnano-pll tangnano-synth tangnano-bitstream program-tangnano \
	check-vivado-sources vivado-bitstream program-icebreaker flash-icebreaker program-basys3 \
	check clean FORCE

.NOTPARALLEL: check

help:
	@echo "SystemVerilog template targets"
	@echo "  make setup                 Create venv and install Python tools"
	@echo "  make doctor                Check the local toolchain and submodules"
	@echo "  make lint                  Lint the rendered RTL with Verilator"
	@echo "  make test-cocotb           Run the registered top-module unit test"
	@echo "  make unit-test             Run registered RTL unit tests"
	@echo "  make synth                 Build a generic Yosys netlist"
	@echo "  make orfs DEFAULT_GOAL=<choice>  Run optional Docker-backed OpenROAD flow"
	@echo "                             Choices: synth floorplan place cts route finish all"
	@echo "                             Configure ORFS_HOME and ORFS_IMAGE; default goal: all"
	@echo "  make icebreaker-pll        Generate the iCEBreaker PLL source"
	@echo "  make icebreaker-bitstream  Build the iCEBreaker bitstream"
	@echo "  make tangnano-pll          Generate the Tang Nano 9K 27-to-48 MHz PLL"
	@echo "  make tangnano-bitstream    Build the Tang Nano 9K CPU with PLL and external SPI RAM pins"
	@echo "  make program-tangnano      Load the CPU into a locally attached board's SRAM"
	@echo "  make check-vivado-sources  Syntax-check the Basys 3 source set"
	@echo "  make vivado-bitstream      Build the Basys 3 bitstream with Vivado"
	@echo "  make check                 Run CPU lint, component tests, and synthesis"
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
	@test -f third_party/basejump_stl/bsg_misc/bsg_defines.sv || { echo "error: initialize git submodules" >&2; exit 1; }
	@yosys -m slang -Q -p 'help read_slang' >/dev/null || { echo "error: Yosys Slang plugin not available" >&2; exit 1; }
	@echo "Toolchain and submodules are ready."

$(RTL_STAMP) $(UNIT_TEST_MANIFEST) &: prepare.sh misc/rtl_renderer.py $(RTL_TREE_INPUTS)
	./prepare.sh
	@touch $(RTL_STAMP)

$(RTL_RENDERED) $(RTL_FILELIST): $(RTL_STAMP)

prepare: $(RTL_STAMP) $(UNIT_TEST_MANIFEST)

lint: $(RTL_STAMP) $(RTL_SOURCES) $(RTL_HEADERS) lint/verilator.vlt
	verilator lint/verilator.vlt --lint-only --Wall $(RTL_INCLUDE_FLAGS) --top-module $(TOP) $(RTL_SOURCES)

# Do not simulate RTL rendered for synthesis-only implementations.
define check_simulation_config
@$(PYTHON) -c 'import json, sys; synth = json.load(open("rtl/config.json")).get("RENDER_OPTION", {}).get("SYNTH", False); sys.exit("\n############################################################\n# SYNTH ON: simulation disabled. Set RENDER_OPTION.SYNTH=false.\n############################################################" if synth else 0)'
endef

test-cocotb:
	$(MAKE) unit-test UNIT_TEST_MODULE=top_module

unit-test: $(UNIT_TEST_MANIFEST) misc/unit-test.py Makefile.cocotb
	$(check_simulation_config)
	$(PYTHON) misc/unit-test.py --manifest $(UNIT_TEST_MANIFEST) --rtl-dir build/rtl $(if $(UNIT_TEST_MODULE),--module $(UNIT_TEST_MODULE))

$(YOSYS_NETLIST): $(RTL_STAMP) $(RTL_SOURCES) $(RTL_HEADERS) synth/yosys_generic/yosys.tcl
	@mkdir -p $(dir $@)
	yosys -m slang -p 'tcl synth/yosys_generic/yosys.tcl $(RTL_FILELIST) $@' \
		-l build/yosys/yosys.log

synth yosys: $(YOSYS_NETLIST)

orfs:
	@$(PYTHON) -c 'import json, sys; sys.exit(0 if json.load(open("rtl/config.json")).get("RENDER_OPTION", {}).get("SYNTH") is True else "error: make orfs requires RENDER_OPTION.SYNTH=true")'
	@test -x "$(ORFS_HOME)/flow/util/docker_shell" || { echo "error: set ORFS_HOME to an OpenROAD-flow-scripts checkout" >&2; exit 1; }
	$(MAKE) prepare
	OR_IMAGE=$(ORFS_IMAGE) "$(ORFS_HOME)/flow/util/docker_shell" -- \
		make DESIGN_CONFIG=$(ORFS_DESIGN_CONFIG) QT_QPA_PLATFORM=$(QT_QPA_PLATFORM) $(DEFAULT_GOAL)

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

$(ICE_ASC): $(ICE_JSON) synth/icestorm_icebreaker/netpnr.pcf synth/icestorm_icebreaker/nextpnr.py
	nextpnr-ice40 --json $(ICE_JSON) --up5k --package sg48 \
		--pre-pack synth/icestorm_icebreaker/nextpnr.py \
		--pcf synth/icestorm_icebreaker/netpnr.pcf --pcf-allow-unconstrained --asc $@

$(ICE_BITSTREAM): $(ICE_ASC)
	icepack $< $@

icebreaker-bitstream: $(ICE_BITSTREAM)

$(TANG_PLL): Makefile
	@mkdir -p $(dir $@)
	gowin_pll -i 27 -o 48 -d GW1NR-LV9QN88PC6/I5 -m tangnano_9k_pll -f $@

tangnano-pll: $(TANG_PLL)

$(TANG_JSON): $(RTL_STAMP) $(RTL_SOURCES) $(RTL_HEADERS) \
		$(TANG_PLL) synth/tangnano_9k/tangnano_9k.v synth/tangnano_9k/yosys.tcl
	yosys -m slang -p 'tcl synth/tangnano_9k/yosys.tcl $(RTL_FILELIST) $(TANG_PLL) synth/tangnano_9k/tangnano_9k.v $(YOSYS_DATDIR)/gowin/cells_sim.v $@' \
		-l $(TANG_DIR)/yosys.log

tangnano-synth: $(TANG_JSON)

$(TANG_ROUTED): $(TANG_JSON) synth/tangnano_9k/netpnr.cst synth/tangnano_9k/nextpnr.py Makefile
	nextpnr-himbaechel --json $(TANG_JSON) --write $@ \
		--device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C \
		--vopt cst=synth/tangnano_9k/netpnr.cst --pre-pack synth/tangnano_9k/nextpnr.py \
		--freq 48 --report $(TANG_DIR)/timing.json -l $(TANG_DIR)/nextpnr.log

$(TANG_BITSTREAM): $(TANG_ROUTED) Makefile
	gowin_pack -d GW1N-9C -o $@ $<

tangnano-bitstream: $(TANG_BITSTREAM)

program-tangnano: $(TANG_BITSTREAM)
	openFPGALoader -b tangnano9k --freq 1000000 $<

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

check: doctor lint unit-test synth

clean:
	rm -rf build openroad/output synth/vivado_basys3/build _rtl sim_build \
		top_module_tb_sim_dir top_module_tb_gls_dir top_module_gls_dir \
		__pycache__ misc/__pycache__ dv/cocotb_benches/__pycache__ \
		dv/ICE_cocotb_benches/__pycache__
	rm -f dump.vcd dump.fst results.xml IPs.flist .rtl_flist.tmp
