
module top_module_sim_gls#(
    parameter int DATAW = 32
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input   logic req_val_i,
    input   logic [DATAW-1:0] ptext_i,
    input   logic [DATAW-1:0] key_i,
    output  logic req_ack_o,

    output  logic [DATAW-1:0] cipher_o
);

top_module #(
    .DATAW(DATAW)
) top_module (
		.clk_i (clk_i),
		.rst_ni (rst_ni),
        
        .req_val_i (req_val_i),
		.ptext_i (ptext_i),
		.key_i (key_i),
        .req_ack_o (req_ack_o),

		.cipher_o (cipher_o)
    );

endmodule
