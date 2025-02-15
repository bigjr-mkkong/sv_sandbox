
module top_module#(
    ) (
    input   logic clk_i,
    input   logic button_i,
    output  logic led_o
);

    assign led_o = button_i;

endmodule
