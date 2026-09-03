# Minimal timing constraints for top_module.
# The absent CPU/core boundary is modeled with the measured optimal
# input/output delay of 0.02 ns (20 ps).

create_clock \
    -name clk \
    -period 2.0 \
    [get_ports clk_i]

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
    -max 0.02 \
    $cpu_inputs

set_input_delay \
    -clock clk \
    -min 0.02 \
    $cpu_inputs

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
    -max 0.02 \
    $cpu_outputs

set_output_delay \
    -clock clk \
    -min 0.02 \
    $cpu_outputs

# rst_ni is an asynchronous active-low reset and is intentionally excluded
# from normal synchronous input-delay constraints.
# set_false_path -from [get_ports rst_ni]
