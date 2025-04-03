//32bit 1-round PRESENT encryption

module top_module#(
    parameter DATAW = 32
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input   logic req_val_i,
    input   logic [DATAW-1:0] ptext_i,
    input   logic [DATAW-1:0] key_i,
    output  logic req_ack_o,

    output  logic rsp_val_o,
    output  logic [DATAW-1:0] cipher_o,
    input   logic rsp_ack_i
);

    logic [DATAW-1:0] s01_ptext_d, s01_ptext_q;
    logic [DATAW-1:0] s01_key_d, s01_key_q;
    logic s01_valid_d, s01_valid_q;
    logic s01_ready;

    always_comb begin
        req_ack_o = s01_ready;
        s01_ptext_d = s01_ptext_q;
        s01_key_d = s01_key_q;
        s01_valid_d = s01_valid_q;
        if(req_val_i && req_ack_o) begin
            s01_ptext_d = ptext_i;
            s01_key_d = key_i;
            s01_valid_d = 1;
        end
    end

    always_ff @(posedge clk_i) begin
        if(~rst_ni) begin
            s01_ptext_q <= 0;
            s01_key_q <= 0;
            s01_valid_q <= 0;
        end else begin
            s01_ptext_q <= s01_ptext_d;
            s01_key_q <= s01_key_d;
            s01_valid_q <= s01_valid_d;
        end
    end


    always_comb begin
        s01_ready = 1;
        rsp_val_o = 0;
        cipher_o = 0;
        if(s01_valid_q) begin
            s01_ready = 0;
            if(rsp_ack_i) begin
                rsp_val_o = 1;
                cipher_o = s01_ptext_q ^ s01_key_q;
            end
        end
    end
    
endmodule
