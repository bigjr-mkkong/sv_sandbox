TOP := top_module

export BASEJUMP_STL_DIR := $(abspath third_party/basejump_stl)
export YOSYS_DATDIR := $(shell yosys-config --datdir)

RTL := $(shell \
 BASEJUMP_STL_DIR=$(BASEJUMP_STL_DIR) \
 python3 misc/convert_filelist.py Makefile rtl/rtl.f \
)

SV2V_ARGS := $(shell \
 BASEJUMP_STL_DIR=$(BASEJUMP_STL_DIR) \
 python3 misc/convert_filelist.py sv2v rtl/rtl.f \
)

INCLUDES := $(shell grep '^-I' rtl/rtl.f)
COCOTB_BENCHES += dv.cocotb_benches.topmod_tb0

GLS_RTL := $(shell cat synth/yosys_generic/gls.f | grep -v '^//' )
GLS_TOP := top_module_sim_gls
GLS_EXT_ARGS := $(shell cat synth/yosys_generic/gls.f | grep '^-')

ICE_RTL := $(shell cat synth/icestorm_icebreaker/gls.f | grep -Ev '^(//|-)')
ICE_EXT_ARGS := $(shell cat synth/icestorm_icebreaker/gls.f | grep '^-')
ICE_TOP := icebreaker
ICE_COCOTB_BENCHES += dv.ICE_cocotb_benches.ice_topmod_tb0

.PHONY: lint sim-cocotb gls-cocotb icestorm_icebreaker_gls-cocotb icestorm_icebreaker_program icestorm_icebreaker_flash clean

lint:
	verilator lint/verilator.vlt -f rtl/rtl.f -f dv/dv.f --lint-only --top ${TOP}

sim-cocotb:
	@echo "RTLs:" "$(RTL)"
	@echo "INCLUDEs:" "$(INCLUDES)"
	@echo "TOPLEVEL:" $(TOP)
	@echo "COCOTB BENCHES:" "$(COCOTB_BENCHES)"
	@make -f Makefile.cocotb \
		VERILOG_SOURCES="$(RTL)" \
		INCLUDES="$(INCLUDES)" \
		TOPLEVEL=$(TOP) \
		MODULE="$(COCOTB_BENCHES)"

sim:
	@echo "sim target not usable in this Makefile, please use sim-cocotb instead"
	@exit 1
	verilator lint/verilator.vlt --Mdir ${TOP}_$@_dir -f rtl/rtl.f -f dv/pre_synth.f -f dv/dv.f --binary -Wno-fatal --top ${TOP}
	./${TOP}_$@_dir/V${TOP} +verilator+rand+reset+2

synth/build/rtl.sv2v.v: ${RTL} rtl/rtl.f
	mkdir -p $(dir $@)
	sv2v ${SV2V_ARGS} -w $@ -DSYNTHESIS

gls: synth/yosys_generic/build/synth.v
	@echo "gls target not usable in this Makefile, please use gls-cocotb instead"
	@exit 1
	verilator lint/verilator.vlt --Mdir ${TOP}_$@_dir -f synth/yosys_generic/gls.f -f dv/dv.f --binary -Wno-fatal --top ${TOP}
	./${TOP}_$@_dir/V${TOP} +verilator+rand+reset+2

gls-cocotb: synth/yosys_generic/build/synth.v
	@echo "Files 2 check: " "$(GLS_RTL)"
	@make -f Makefile.cocotb \
		VERILOG_SOURCES="$(GLS_RTL)" \
		TOPLEVEL=$(GLS_TOP) \
		EXTRA_ARGS="$(GLS_EXTRA_ARGS)" \
		MODULE="$(COCOTB_BENCHES)"

synth/yosys_generic/build/synth.v: synth/build/rtl.sv2v.v synth/yosys_generic/yosys.tcl
	mkdir -p $(dir $@)
	yosys -p 'tcl synth/yosys_generic/yosys.tcl synth/build/rtl.sv2v.v' -l synth/yosys_generic/build/yosys.log

icestorm_icebreaker_gls: synth/icestorm_icebreaker/build/synth.v
	@echo "icestorm_icebreaker_gls target not usable in this Makefile, please use icestorm_icebreaker_gls-cocotb instead"
	@exit 1
	verilator lint/verilator.vlt --Mdir ${TOP}_$@_dir -f synth/icestorm_icebreaker/gls.f -f dv/dv.f --binary -Wno-fatal --top ${TOP}
	./${TOP}_$@_dir/V${TOP} +verilator+rand+reset+2


icestorm_icebreaker_gls-cocotb: synth/icestorm_icebreaker/build/synth.v
	@echo "Files 2 check: " "$(ICE_RTL)"
	@echo "Top Module: " "$(ICE_TOP)"
	@echo "Extra Args: " "$(ICE_EXT_ARGS)"
	@make -f Makefile.cocotb \
		VERILOG_SOURCES="$(ICE_RTL)" \
		TOPLEVEL=$(ICE_TOP) \
		EXTRA_ARGS="$(ICE_EXT_ARGS)" \
		MODULE="$(ICE_COCOTB_BENCHES)"

synth/icestorm_icebreaker/build/synth.v synth/icestorm_icebreaker/build/synth.json: synth/build/rtl.sv2v.v synth/icestorm_icebreaker/icebreaker.v synth/icestorm_icebreaker/yosys.tcl
	mkdir -p $(dir $@)
	yosys -p 'tcl synth/icestorm_icebreaker/yosys.tcl' -l synth/icestorm_icebreaker/build/yosys.log

synth/icestorm_icebreaker/build/icebreaker.asc: synth/icestorm_icebreaker/build/synth.json synth/icestorm_icebreaker/nextpnr.py synth/icestorm_icebreaker/netpnr.pcf
	nextpnr-ice40 \
	 --json synth/icestorm_icebreaker/build/synth.json \
	 --up5k \
	 --package sg48 \
	 --pre-pack synth/icestorm_icebreaker/nextpnr.py \
	 --pcf synth/icestorm_icebreaker/netpnr.pcf \
	 --asc $@

%.bit: %.asc
	icepack $< $@

icestorm_icebreaker_program: synth/icestorm_icebreaker/build/icebreaker.bit
	sudo $(shell which openFPGALoader) -b ice40_generic $<

icestorm_icebreaker_flash: synth/icestorm_icebreaker/build/icebreaker.bit
	sudo $(shell which openFPGALoader) -f -b ice40_generic $<

synth/vivado_basys3/build/basys3/basys3.runs/impl_1/basys3.bit: synth/build/rtl.sv2v.v synth/vivado_basys3/basys3.sv synth/vivado_basys3/Basys3_Master.xdc synth/vivado_basys3/constraints.xdc synth/vivado_basys3/vivado.tcl
	rm -rf synth/vivado_basys3/build/basys3
	mkdir -p synth/vivado_basys3/build
	cd synth/vivado_basys3/build && \
	 vivado -quiet -nolog -nojournal -notrace -mode tcl \
	  -source ../vivado.tcl

vivado_basys3_program: synth/vivado_basys3/build/basys3/basys3.runs/impl_1/basys3.bit
	sudo $(shell which openFPGALoader) -b vivado_basys3 $<

clean:
	rm -rf \
	 *.memh *.memb \
	 *sim_dir *gls_dir \
	 dump.vcd dump.fst \
	 synth/build \
	 synth/yosys_generic/build \
	 synth/icestorm_icebreaker/build \
	 synth/vivado_basys3/build \
	 sim_build \
	 results.xml
