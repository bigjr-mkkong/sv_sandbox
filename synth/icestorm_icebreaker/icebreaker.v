`timescale 1ns / 1ps

module icebreaker (
    input  logic CLK,
    input  logic BTN_N,
    input  logic RX,
    output logic TX
);

    logic clk_48;

`ifdef ICEBREAKER_SIMULATION
    // The primitive library does not model PLL behavior in RTL simulation.
    assign clk_48 = CLK;
`else
    icebreaker_pll pll (
        .clock_in(CLK),
        .clock_out(clk_48),
        .locked()
    );
`endif

    top_module u_top (
        .clk_i(clk_48),
        .rst_ni(BTN_N),
        .rxd_i(RX),
        .txd_o(TX)
    );

endmodule
