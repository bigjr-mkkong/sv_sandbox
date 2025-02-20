module icebreaker (
    input  wire CLK,
    input  wire BTN_N,
    input  wire RX,
    output wire TX,
    output wire LEDG_N
);

wire clk_12 = CLK;
wire clk_50250;

//icepll -i 12 -o 50
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
    .DIVR(4'b0000),
    .DIVF(7'b1000010),
    .DIVQ(3'b100),
    .FILTER_RANGE(3'b001)
) pll (
    .LOCK(),
    .RESETB(1'b1),
    .BYPASS(1'b0),
    .PACKAGEPIN(clk_12),
    .PLLOUTGLOBAL(clk_50250)
);

    reg [31:0] counter = 0;
    reg start = 0;
    wire busy;
    wire tx_out;

    uart_tx uart (
        .clk(clk_50250),
        .rst_n(BTN_N),
        .data_val_i(1),
        .data_in(8'h48),
        .data_rdy_o(_),
        .tx(TX)
    );

    top_module dut(
    
    )
endmodule



