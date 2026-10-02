`timescale 1ns / 1ps
module dual_port_ram #(
    parameter int unsigned ele_sz_bit = 32,
    parameter int unsigned ele_cnt    = 16
) (
    input  logic                         r_clk_i,
    input  logic [$clog2(ele_cnt)-1:0]  r_addr_i,
    input  logic                         r_val_i,

    input  logic                         w_clk_i,
    input  logic [$clog2(ele_cnt)-1:0]  w_addr_i,
    input  logic [ele_sz_bit-1:0]        w_data_i,
    input  logic                         w_val_i,

    output logic [ele_sz_bit-1:0]        r_data_o,
    output logic                         r_rdy_o
);

    logic [ele_sz_bit-1:0] buffer [0:ele_cnt-1];

    always_ff @(posedge r_clk_i) begin
        r_rdy_o <= r_val_i;

        if (r_val_i) begin
            r_data_o <= buffer[r_addr_i];
        end
    end

    always_ff @(posedge w_clk_i) begin
        if (w_val_i) begin
            buffer[w_addr_i] <= w_data_i;
        end
    end

endmodule
