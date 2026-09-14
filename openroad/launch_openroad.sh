OR_IMAGE=openroad/orfs:latest \
../../OpenROAD-flow-scripts/flow/util/docker_shell \
make -f /OpenROAD-flow-scripts/flow/Makefile \
DESIGN_CONFIG=/work/config.mk \
WORK_HOME=/work/output \
open_place
# gui_floorplan

# Replace above with gui_floorplan for gui inspection
