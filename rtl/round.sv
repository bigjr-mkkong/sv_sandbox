module enc_round#(
    parameter DATAW = 32
    )(
        input   logic [DATAW-1:0]ptext_i,
        input   logic [DATAW-1:0]key_i,
        output  logic [DATAW-1:0]cipher_o
    );

    logic [DATAW-1:0] addrdkey_o;
    logic [DATAW-1:0] sbox_o;

    add_round_key step_addrdkey1(
        .ptext_i    (ptext_i),
        .key_i      (key_i),
        .mixed_o    (addrdkey_o)
    );

    sbox step_sbox(
        .data_i     (addrdkey_o),
        .data_o     (sbox_o)
    );

    pbox step_pbox(
        .data_i     (sbox_o),
        .data_o     (cipher_o)
    );


endmodule

module add_round_key#(
    parameter DATAW = 32
    )(
        input   logic [DATAW-1: 0] ptext_i,
        input   logic [DATAW-1: 0] key_i,
        output  logic [DATAW-1: 0] mixed_o
    );
    assign mixed_o = ptext_i ^ key_i;
endmodule

module pbox#(
    parameter DATAW = 32
    )(
        input   logic [DATAW-1: 0]data_i,
        output  logic [DATAW-1: 0]data_o
    );

    localparam int pbox[32] = {
    8, 29, 23, 15, 5, 6, 21, 18,
    19, 22, 17, 25, 14, 0, 31, 10,
    30, 24, 7, 16, 3, 9, 20, 1,
    13, 2, 27, 11, 28, 4, 26, 12
    };


    
    genvar i;
    generate
        for (i=0; i<DATAW; i++) begin
            assign data_o[i] = data_i[pbox[i]];
        end
    endgenerate

endmodule
