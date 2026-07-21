`timescale 1ns / 1ps

module basys3 (
    input  logic       sys_clk,
    input  logic       btnC,
    input  logic       RsRx,
    output logic       RsTx,
    output logic [0:0] led
);

    logic clk_48;

    mmcm_100_to_48 clock_generator (
        .clk_100(sys_clk),
        .clk_48(clk_48)
    );

    top_module u_top (
        .clk_i(clk_48),
        .rst_ni(!btnC),
        .rxd_i(RsRx),
        .txd_o(RsTx)
    );

    assign led[0] = RsTx;

endmodule
