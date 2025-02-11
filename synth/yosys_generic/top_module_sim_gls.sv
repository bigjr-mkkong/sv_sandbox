
module top_module_sim_gls (
    input  logic clk_i,
    input  logic rst_ni,
    output logic led_o
);

top_module #(
    .clk_frac_rate(5)
) top_module (.*);

endmodule
