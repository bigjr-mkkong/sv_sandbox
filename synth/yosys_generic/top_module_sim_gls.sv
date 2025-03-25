
module top_module_sim_gls#(
    parameter DATAW = 32
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input   logic [DATAW-1:0] ptext_i,
    input   logic [DATAW-1:0] key_i,
    output  logic [DATAW-1:0] cipher_o
);

top_module #(
    .DATAW(DATAW)
) top_module (
		.clk_i (clk_i),
		.rst_ni (rst_ni),

		.ptext_i (ptext_i),
		.key_i (key_i),
		.cipher_o (cipher_o)
    );

endmodule
