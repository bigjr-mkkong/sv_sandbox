//16bit 1-round aes-like encryption
//Only go through addkey->sbox->permu

module top_module#(
    parameter DATAW = 32
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input   logic [DATAW-1:0] ptext_i,
    input   logic [DATAW-1:0] key_i,
    output  logic [DATAW-1:0] cipher_o
);

    logic [DATAW-1:0] cipher_buf;
    round#(
        .DATAW(DATAW)
    )round_dut(
        .ptext_i    (ptext_i),
        .key_i      (key_i),
        .cipher_o   (cipher_buf)
    );

    always @(posedge clk_i) begin
        if (~rst_ni) begin
            cipher_o <= 0;
        end else begin
            cipher_o <= cipher_buf;
        end
    end
    

endmodule


