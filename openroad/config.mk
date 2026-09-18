export PLATFORM = nangate45
export DESIGN_NAME = top_module
export DESIGN_NICKNAME = top_module

# docker_shell mounts the project at /work. Keep generated artifacts separate.
export PROJECT_HOME = /work
export WORK_HOME = $(PROJECT_HOME)/openroad/output
export SYNTH_HDL_FRONTEND = slang

# Reuse the canonical ordering, including packages and interfaces before users.
export VERILOG_FILES = $(addprefix $(PROJECT_HOME)/,$(shell sed -e 's,//.*,,' -e '/^[[:space:]]*$$/d' $(PROJECT_HOME)/build/rtl/rtl.flist))
export SDC_FILE = $(PROJECT_HOME)/openroad/top_module.sdc

# Starting values for the default UART example, not cache-specific placement.
export CORE_UTILIZATION = 50
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 2
export PLACE_DENSITY = 0.60
