//32bit 1-round PRESENT encryption

module top_module#(
    parameter DATAW = 32
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input   logic req_val_i;
    input   logic [DATAW-1:0] ptext_i,
    input   logic [DATAW-1:0] key_i,
    output  logic req_ack_o;

    output  logic rsp_val_o;
    output  logic [DATAW-1:0] cipher_o
    input   logic rsp_ack_i;
);

    logic [DATAW-1:0] c0_cip_buf;
    logic [DATAW-1:0] c1_cip_buf;
    logic [DATAW-1:0] key0, key1;

    logic [DATAW-1:0] c01_key0_d, c01_key1_d;
    logic [DATAW-1:0] c01_key0_q, c01_key1_q;
    logic [DATAW-1:0] c01_data_d;
    logic [DATAW-1:0] c01_data_q;
    logic c1_enable;

    assign key0 = {key_i[DATAW-1: DATAW/2], 16'd0};
    assign key1 = {key_i[DATAW/2-1: 0], 16'd0};

    enc_round#(
        .DATAW(DATAW)
    )enc_round_dut0(
        .ptext_i    (ptext_i),
        .key_i      (key0),
        .cipher_o   (c0_cip_buf)
    );

    assign c01_key0_d = key0;
    assign c01_key1_d = key1;
    assign c01_data_d = c0_cip_buf;

    always @(posedge clk_i) begin
        if (~rst_ni) begin
            c01_data_q <= 0;
            c01_key0_q <= 0;
            c01_key1_q <= 0;
            c1_enable <= 0;
        end else begin
            c01_data_q <= c01_data_d;
            c01_key0_q <= c01_key0_d;
            c01_key1_q <= c01_key1_d;
            c1_enable <= 1;
        end
    end
    
    enc_round#(
        .DATAW(DATAW)
    )enc_round_dut1(
        .ptext_i    (c01_data_q),
        .key_i      (c01_key1_q),
        .cipher_o   (c1_cip_buf)
    );

    always @(posedge clk_i) begin
        if (~rst_ni || ~c1_enable) begin
            cipher_o <= 0;
        end else begin
            cipher_o <= c1_cip_buf;
        end
    end

endmodule


