`timescale 1ns / 1ps

module async_fifo#(
    parameter int unsigned ele_sz_bit = 32,
    parameter int unsigned ele_cnt    = 16
)(

    input  logic                         r_clk_i,
    input  logic                       rst_ni,
    input  logic                         r_val_i,
    output logic [ele_sz_bit-1:0]        r_data_o,
    output logic                        r_rdy_o,

    input  logic                         w_clk_i,
    input  logic                         w_val_i,
    input  logic [ele_sz_bit-1:0]        w_data_i,
    output logic                        w_rdy_o,
);

function grey_code(logic [$clog2(ele_cnt)-1: 0] bin_in) begin
    return bin_in ^ (bin_in >> 1);
endfunction

logic [$clog2(ele_cnt)-1: 0] head_d;
logic [$clog2(ele_cnt)-1: 0] head_q;

logic [$clog2(ele_cnt)-1: 0] tail_d;
logic [$clog2(ele_cnt)-1: 0] tail_q;

logic is_full;
logic is_empty;
    
logic read_en;
logic write_en;

logic [ele_sz_bit-1: 0] mem_out;

dual_port_ram(
    .r_clk_i(r_clk_i),
    .r_addr_i(tail_q),
    .r_val_i(read_en),

    .w_clk_i(w_clk_i),
    .w_addr_i(head_q),
    .w_data_i(w_data_i),
    .w_val_i(write_en),

    .r_data_o(mem_out),
    .r_rdy_o(r_rdy_o),
);

typedef enum{
    IDLE,
    RESP,
} r_state;

typedef enum{
    IDLE,
    RESP,
} w_state;

r_state r_state_d, r_state_q;
w_state w_state_d, w_state_q;

always_comb begin
    r_rdy_o = 1;
    if(r_val_i) begin
        write_en = 1;

    end
end


endmodule
