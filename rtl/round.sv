module round#(
    parameter DATAW = 16
    )(
        input   logic [DATAW-1:0]ptext_i,
        input   logic [DATAW-1:0]key_i,
        output  logic [DATAW-1:0]cipher_o
    );

    logic [DATAW-1:0] addrdkey_o;
    logic [DATAW-1:0] sbox_o;
    logic [DATAW-1:0] shift_o;
    logic [DATAW-1:0] mix_o;

    assign cipher_o = mix_o;

    add_round_key step_addrdkey(
        .ptext_i    (ptext_i),
        .key_i      (key_i),
        .mixed_o    (addrdkey_o)
    );

    sbox step_sbox(
        .data_i     (addrdkey_o),
        .data_o     (sbox_o)
    );

    row_shift step_rshift(
        .data_i     (sbox_o),
        .data_o     (shift_o)
    );

    colmix step_colmix(
        .data_i     (shift_o),
        .data_o     (mix_o)
    );

endmodule

module row_shift#(
    parameter DATAW = 16,
    localparam ROWCNT = $clog2(DATAW),
    localparam COLCNT = ROWCNT
    )(
    input   logic [DATAW-1:0]data_i,
    output  logic [DATAW-1:0]data_o
    );

    logic [DATAW-1: 0] shifted;
    integer row;
    always_comb begin
        shifted = data_i;
        for (row = 0; row < ROWCNT; row++) begin
            shifted[(row*4) +: 4] = data_i[(((row*4) + row) % (ROWCNT * COLCNT)) +: 4];
        end
        data_o = shifted;
    end
endmodule

module add_round_key#(
    parameter DATAW = 16
    )(
        input   logic [DATAW-1: 0] ptext_i,
        input   logic [DATAW-1: 0] key_i,
        output  logic [DATAW-1: 0] mixed_o
    );
    assign mixed_o = ptext_i ^ key_i;
endmodule

module colmix#(
    parameter DATAW = 16,
    localparam ROWCNT = $clog2(DATAW),
    localparam COLCNT = ROWCNT
    )(
        input   logic [DATAW-1:0] data_i,
        output  logic [DATAW-1:0] data_o
    );
    logic [ROWCNT-1:0] state [COLCNT-1:0];
    logic [ROWCNT-1:0] state_out [COLCNT-1:0];

    integer row, col;

    always_comb begin
        for (col = 0; col < COLCNT; col++) begin
            for (row = 0; row < ROWCNT; row++) begin
                state[col][row] = data_i[(col * ROWCNT) + row];
            end
        end

        for (col = 0; col < COLCNT; col++) begin
            state_out[col][0] = (state[col][0] << 1) ^ (state[col][1] << 1) ^ state[col][1] ^ state[col][2] ^ state[col][3];
            state_out[col][1] = state[col][0] ^ (state[col][1] << 1) ^ (state[col][2] << 1) ^ state[col][2] ^ state[col][3];
            state_out[col][2] = state[col][0] ^ state[col][1] ^ (state[col][2] << 1) ^ (state[col][3] << 1) ^ state[col][3];
            state_out[col][3] = (state[col][0] << 1) ^ state[col][0] ^ state[col][1] ^ state[col][2] ^ (state[col][3] << 1);
        end

        for (col = 0; col < COLCNT; col++) begin
            for (row = 0; row < ROWCNT; row++) begin
                data_o[(col * ROWCNT) + row] = state_out[col][row];
            end
        end
    end

endmodule
