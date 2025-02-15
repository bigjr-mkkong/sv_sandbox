
module top_module_sim_gls (
    input   logic clk_i,
    input   logic button_i,
    output  logic led_o
);

top_module  top_module (
    .clk_i(clk_i),
    .button_i(button_i),
    .led_o(led_o),
);

endmodule
