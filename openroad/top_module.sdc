# Default example clock: 48 MHz, matching rtl/config_pkg.sv.
create_clock -name clk -period 20.833333 [get_ports clk_i]

# Illustrative board-interface budgets; replace these for a real integration.
set_input_delay -clock clk -min 0.0 [get_ports {rst_ni rxd_i}]
set_input_delay -clock clk -max 2.0 [get_ports {rst_ni rxd_i}]
set_output_delay -clock clk -min 0.0 [get_ports txd_o]
set_output_delay -clock clk -max 2.0 [get_ports txd_o]
