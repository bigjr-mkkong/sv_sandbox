module icebreaker#(
    parameter UART_DATA_WIDTH = 8,
    parameter DATAW = 32
) (
    input  wire CLK,
    input  wire BTN_N,
    input  wire RX,
    output wire TX,
);

// F_PLLIN:    12.000 MHz (given)
// F_PLLOUT:   48.000 MHz (requested)
// F_PLLOUT:   48.000 MHz (achieved)

// FEEDBACK: SIMPLE
// F_PFD:   12.000 MHz
// F_VCO:  768.000 MHz

// DIVR:  0 (4'b0000)
// DIVF: 63 (7'b0111111)
// DIVQ:  4 (3'b100)

// FILTER_RANGE: 1 (3'b001)

wire clk_48;

SB_PLL40_PAD #(
    .FEEDBACK_PATH("SIMPLE"),
    .DIVR(4'b0000),
    .DIVF(7'b0111111),
    .DIVQ(3'b100),
    .FILTER_RANGE(3'b001)
) pll (
    .LOCK(),
    .RESETB(1'b1),
    .BYPASS(1'b0),
    .PACKAGEPIN(CLK),
    .PLLOUTGLOBAL(clk_48)
);

top_module #(
    .DATAW(DATAW),
    .PRE_W(PRE_W)
) top_module_inst (
		.clk_i(clk_48)
		,.rst_ni(rst_ni)

		,.rxd(RX)
		,.txd(TX)
    );
endmodule
