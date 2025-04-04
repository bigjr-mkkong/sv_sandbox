
module top_module_sim_gls#(
    parameter DATAW = 32
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input   logic req_val_i,
    input   logic [DATAW-1:0] ptext_i,
    input   logic [DATAW-1:0] key_i,
    output  logic req_rdy_o,

    output  logic rsp_val_o,
    output  logic [DATAW-1:0] cipher_o,
    input   logic rsp_rdy_i
);

top_module #(
    .DATAW(DATAW)
) top_module (
		.clk_i	(clk_i),
		.rst_ni	(rst_ni),

		.req_val_i	(req_val_i),
		.ptext_i	(ptext_i),
		.key_i	(key_i),
		.req_rdy_o	(req_rdy_o),

		.rsp_val_o	(rsp_val_o),
		.cipher_o	(cipher_o),
		.rsp_rdy_i	(rsp_rdy_i)
    );

endmodule
