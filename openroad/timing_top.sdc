# ============================================================
# timing_top.sdc
#
# Purpose:
#   Characterize intrinsic timing of timing_top under the
#   selected OpenROAD PDK/platform.
#
# Assumption:
#   CPU-side logic is not modeled, so all external input/output
#   delays are normalized to 0 ns.
# ============================================================


# ------------------------------------------------------------
# Primary clock
#
# Start with a relaxed 2 ns period = 500 MHz.
# This is an optimization target, not the measured delay.
# ------------------------------------------------------------

create_clock \
    -name clk \
    -period 2.0 \
    [get_ports clk_i]


# ------------------------------------------------------------
# CPU request / response inputs
# ------------------------------------------------------------

set cpu_inputs [get_ports {
    cache0_req_val_i
    cache0_req_addr_i
    cache0_req_data_i
    cache0_req_is_write_i
    cache0_rsp_rdy_i

    cache1_req_val_i
    cache1_req_addr_i
    cache1_req_data_i
    cache1_req_is_write_i
    cache1_rsp_rdy_i
}]

set_input_delay \
    -clock clk \
    -max 0.0 \
    $cpu_inputs

set_input_delay \
    -clock clk \
    -min 0.0 \
    $cpu_inputs


# ------------------------------------------------------------
# CPU request / response outputs
# ------------------------------------------------------------

set cpu_outputs [get_ports {
    cache0_req_rdy_o
    cache0_rsp_val_o
    cache0_rsp_data_o

    cache1_req_rdy_o
    cache1_rsp_val_o
    cache1_rsp_data_o
}]

set_output_delay \
    -clock clk \
    -max 0.0 \
    $cpu_outputs

set_output_delay \
    -clock clk \
    -min 0.0 \
    $cpu_outputs


# ------------------------------------------------------------
# Reset
#
# Assuming rst_ni is an asynchronous active-low reset.
# Do not analyze it as a normal synchronous data path.
# ------------------------------------------------------------

# set_false_path \
#     -from [get_ports rst_ni]

