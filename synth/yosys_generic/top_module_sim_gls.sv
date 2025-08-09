
module top_module_sim_gls#(
    parameter DATAW = 32,
    parameter PRE_W = 16
    ) (
    input  logic         clk_i,
    input  logic         rst_ni,

    input  wire logic               rxd,
    output wire logic               txd
);

top_module #(
    .DATAW(DATAW),
    .PRE_W(PRE_W)
) top_module (
		.clk_i(clk_i)
		,.rst_ni(rst_ni)

		,.rxd(rxd)
		,.txd(txd)
    );

endmodule
