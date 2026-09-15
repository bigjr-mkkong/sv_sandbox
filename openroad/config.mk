export PLATFORM = nangate45

export DESIGN_NAME = top_module
export DESIGN_NICKNAME = top_module

# Keep all ORFS-generated logs, objects, reports, and results together while
# retaining a stable root for project RTL and constraint inputs.
export PROJECT_HOME = /work
export WORK_HOME = $(PROJECT_HOME)/openroad/output

# The project RTL must be rendered with RENDER_OPTION.SYNTH=true before ORFS
# starts. Explicit ordering keeps interfaces and packages ahead of their users.
export SYNTH_HDL_FRONTEND = slang
export VERILOG_FILES = \
    $(PROJECT_HOME)/third_party/taxi/src/axi/rtl/taxi_axil_if.sv \
    $(PROJECT_HOME)/third_party/taxi/src/prim/rtl/taxi_penc.sv \
    $(PROJECT_HOME)/third_party/taxi/src/prim/rtl/taxi_arbiter.sv \
    $(PROJECT_HOME)/third_party/taxi/src/axi/rtl/taxi_axil_interconnect_rd.sv \
    $(PROJECT_HOME)/third_party/taxi/src/axi/rtl/taxi_axil_interconnect_wr.sv \
    $(PROJECT_HOME)/third_party/taxi/src/axi/rtl/taxi_axil_interconnect.sv \
    $(PROJECT_HOME)/build/rtl/config_pkg.sv \
    $(PROJECT_HOME)/build/rtl/1rw_dumb_dram.sv \
    $(PROJECT_HOME)/build/rtl/MESI_protocol.sv \
    $(PROJECT_HOME)/build/rtl/cache_coherency.sv \
    $(PROJECT_HOME)/build/rtl/coh_bus_arbiter.sv \
    $(PROJECT_HOME)/build/rtl/cache_bank.sv \
    $(PROJECT_HOME)/build/rtl/cache_committer.sv \
    $(PROJECT_HOME)/build/rtl/cache_coherency_bus_responder.sv \
    $(PROJECT_HOME)/build/rtl/LLC_committer.sv \
    $(PROJECT_HOME)/build/rtl/1rw_simple_cache.sv \
    $(PROJECT_HOME)/build/rtl/main_module.sv \
    $(PROJECT_HOME)/build/rtl/top_module.sv

export SDC_FILE = $(PROJECT_HOME)/openroad/top_module.sdc

export ADDITIONAL_LEFS = \
    $(PLATFORM_DIR)/lef/fakeram45_128x64.lef

export ADDITIONAL_LIBS = \
    $(PLATFORM_DIR)/lib/fakeram45_128x64.lib

# Coarse stacked floorplan: cache 0 SRAMs / control logic / cache 1 SRAMs.
export CORE_UTILIZATION = 50
export CORE_ASPECT_RATIO = 0.70
export CORE_MARGIN = 2

export PLACE_DENSITY = 0.60
export MACRO_PLACE_HALO = 5 5
export MACRO_BLOCKAGE_HALO = 5

# export SYNTH_MEMORY_MAX_BITS = 144384
# export SYNTH_MOCK_LARGE_MEMORIES=1

export MACRO_PLACEMENT_TCL = $(PROJECT_HOME)/openroad/sram_placement.tcl
# Keep the previous guided floorplan/results available for comparison.
export FLOW_VARIANT = simple_cache
