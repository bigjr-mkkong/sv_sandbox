`timescale 1ns / 1ps

/*
 * One logical 256-row by 64-bit synchronous 1RW cache bank.
 *
 * Simulation uses two unmodified BaseJump synchronous models. Synthesis uses
 * Nangate45 128x64 FakeRAM macros directly so physical-design tools see the
 * real macro boundary. Address bit zero selects the physical bank and the
 * remaining seven bits select its row.
 */

{% if RENDER_OPTION.SYNTH %}
(* blackbox *)
module fakeram45_128x64 (
    output logic [63:0] rd_out,
    input  logic [6:0]  addr_in,
    input  logic        we_in,
    input  logic [63:0] wd_in,
    input  logic [63:0] w_mask_in,
    input  logic        clk,
    input  logic        ce_in
);
endmodule
{% endif %}

module cache_bank (
    input  logic        clk_i,
    input  logic        reset_i,
    input  logic        v_i,
    input  logic        w_i,
    input  logic [7:0]  addr_i,
    input  logic [63:0] data_i,
    output logic [63:0] data_o
);
    logic [1:0][63:0] bank_data;
    logic [1:0] bank_ce;
    logic read_bank_q;

    always_comb begin
        bank_ce = '0;
        if (v_i) begin
            bank_ce[addr_i[0]] = 1'b1;
        end
    end

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            read_bank_q <= 1'b0;
        end else if (v_i && !w_i) begin
            read_bank_q <= addr_i[0];
        end
    end

    for (genvar bank = 0; bank < 2; bank++) begin : gen_bank
{% if RENDER_OPTION.SYNTH %}
        fakeram45_128x64 bank_mem (
            .rd_out(bank_data[bank]),
            .addr_in(addr_i[7:1]),
            .we_in(w_i),
            .wd_in(data_i),
            .w_mask_in({64{1'b1}}),
            .clk(clk_i),
            .ce_in(bank_ce[bank])
        );
{% else %}
        bsg_mem_1rw_sync #(
            .width_p(64),
            .els_p(128),
            .latch_last_read_p(0)
        ) bank_mem (
            .clk_i,
            .reset_i,
            .v_i(bank_ce[bank]),
            .w_i,
            .addr_i(addr_i[7:1]),
            .data_i,
            .data_o(bank_data[bank])
        );
{% endif %}
    end

    assign data_o = bank_data[read_bank_q];
endmodule
