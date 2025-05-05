//32bit 1-round PRESENT encryption

module top_module#(
    parameter int DATAW = 32
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input   logic req_val_i,
    input   logic [DATAW-1:0] ptext_i,
    input   logic [DATAW-1:0] key_i,
    output  logic req_rdy_o,

    output  logic [DATAW-1:0] cipher_o
);

    logic [DATAW-1: 0] ptext_rd0_d, ptext_rd0_q;
    logic [DATAW-1: 0] key_rd0_d, key_rd0_q;
    logic valid_rd0_d, valid_rd0_q;

    logic [DATAW-1: 0] cipher_rd1_d, cipher_rd1_q;
    logic valid_rd1_d, valid_rd1_q;

    always_comb begin
        req_ack_o = 0;
        ptext_rd0_d = 0;
        key_rd0_d = 0;
        valid_rd0_d = 0;
        if (req_val_i) begin
            req_ack_o = 1;
            ptext_rd0_d = ptext_i;
            key_rd0_d = key_i;
            valid_rd0_d = 1;
        end 
    end

    always_ff begin
        if (~rst_ni) begin
            ptext_rd0_q <= 0;
            key_rd0_q <= 0;
            valid_rd0_q <= 0;
        end else begin
            ptext_rd0_q <= ptext_rd0_d;
            key_rd0_q <= key_rd0_d;
            valid_rd0_q <= valid_rd0_d;
        end
    end
    
    logic [DATAW-1: 0] enc0_ptext_i, enc0_key_i;

    assign enc0_ptext_i = (valid_rd0_q)?ptext_rd0_q:0;
    assign enc0_key_i = (valid_rd0_q)?key_rd0_q:0;
    assign valid_rd1_d = valid_rd0_q;

    enc_round #(
        .DATAW(DATAW)
        ) enc0 (
            .ptext_i (enc0_ptext_i),
            .key_i (enc0_key_i),
            .cipher_o(cipher_rd1_d)
        );

    always_ff begin
        if (~rst_ni) begin
            valid_rd1_q <= 0;
            cipher_rd1_q <= 0;
        end else begin
            valid_rd1_q <= valid_rd1_d;
            cipher_rd1_q <= cipher_rd1_d;
        end
    end

    assign cipher_o = valid_rd1_q?cipher_rd1_q:0;

endmodule
