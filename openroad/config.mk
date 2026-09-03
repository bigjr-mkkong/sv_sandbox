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
    $(PROJECT_HOME)/build/rtl/cache_committer.sv \
    $(PROJECT_HOME)/build/rtl/cache_coherency_bus_responder.sv \
    $(PROJECT_HOME)/build/rtl/LLC_committer.sv \
    $(PROJECT_HOME)/build/rtl/1rw_simple_cache.sv \
    $(PROJECT_HOME)/build/rtl/main_module.sv \
    $(PROJECT_HOME)/build/rtl/top_module.sv

export SDC_FILE = $(PROJECT_HOME)/openroad/top_module.sdc

# Initial physical-design parameters. These only provide a starting point for
# the first timing experiment and are not intended as a tuned floorplan.
export CORE_UTILIZATION = 50
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 2

export PLACE_DENSITY = 0.60

# Use unrealistic large memory just to pass flow and get delay info in top module
# export SYNTH_MEMORY_MAX_BITS = 144384
export SYNTH_MOCK_LARGE_MEMORIES=1
