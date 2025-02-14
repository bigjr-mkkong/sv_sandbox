module icebreaker (
    input  wire CLK,
    input  wire RX,
    output wire TX
);

wire clk_12 = CLK;
wire clk_50;

// icepll -i 12 -o 50
// F_PLLIN:    12.000 MHz (given)
// F_PLLOUT:   50.000 MHz (requested)
// F_PLLOUT:   50.250 MHz (achieved)

// FEEDBACK: SIMPLE
// F_PFD:   12.000 MHz
// F_VCO:  804.000 MHz

// DIVR:  0 (4'b0000)
// DIVF: 66 (7'b1000010)
// DIVQ:  4 (3'b100)

// FILTER_RANGE: 1 (3'b001)

SB_PLL40_PAD #(
    .FEEDBACK_PATH("SIMPLE"),
    .DIVR(4'd0),
    .DIVF(7'd66),
    .DIVQ(3'd4),
    .FILTER_RANGE(3'd1)
) pll (
    .LOCK(),
    .RESETB(1'b1),
    .BYPASS(1'b0),
    .PACKAGEPIN(clk_12),
    .PLLOUTGLOBAL(clk_50)
);

top_module #(
    .clk_frac_rate(5)
) icebreaker_top_module (
    .clk_i(clk_50),
    .rst_ni(BTN_N),
    .led_o(led)
);

endmodule
