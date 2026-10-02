`timescale 1ns / 1ps

{% do unit_test(
    module_name = "sync_fifo",
    test_framework = "cocotb",
    test_path = "dv/cocotb_benches/sync_fifo_tb.py",
    use_wrapper = false) %}

module sync_fifo #(
    parameter int unsigned ELE_SZ_BIT = 32,
    parameter int unsigned ELE_CNT = 16
) (
    input logic clk_i,
    input logic rst_ni,

    //Push interface
    input logic push_req_val_i,
    input logic [ELE_SZ_BIT-1:0] push_req_data_i,
    output logic push_erm_o, //Error Message : 0: Normal, 1: FIFO filled
    output logic push_req_rdy_o,


    //Pop interface
    input logic pop_req_val_i,
    output logic [ELE_SZ_BIT-1:0] pop_req_data_o,
    output logic pop_erm_o, //Error Message : 0: Normal, 1: FIFO empty
    output logic pop_req_rdy_o
);
    localparam int unsigned PTR_WIDTH = ELE_CNT > 1 ? $clog2(ELE_CNT) : 1;

    logic [ELE_SZ_BIT-1:0] buffer [0:ELE_CNT-1];
    logic [PTR_WIDTH-1:0] head_q;
    logic [PTR_WIDTH-1:0] tail_q;

    logic is_full_q;
    logic is_empty_q;

    logic do_push;
    logic do_pop;

    function automatic logic [PTR_WIDTH-1:0] ptr_next(input logic [PTR_WIDTH-1:0] ptr);
        if (ptr == PTR_WIDTH'(ELE_CNT-1)) begin
            return '0;
        end else begin
            return ptr + 1'b1;
        end
    endfunction

    always_comb begin
        push_req_rdy_o = 1'b1;
        push_erm_o = 1'b0;
        do_push = 1'b0;

        if (push_req_val_i && !pop_req_val_i) begin
            push_erm_o = is_full_q;
            if (!is_full_q) begin
                do_push = 1'b1;
            end
        end
    end

    always_comb begin
        pop_req_rdy_o = 1'b1;
        pop_erm_o = 1'b0;
        do_pop = 1'b0;

        if (pop_req_val_i && !push_req_val_i) begin
            pop_erm_o = is_empty_q;
            if (!is_empty_q) begin
                do_pop = 1'b1;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            head_q <= '0;
            tail_q <= '0;
            is_full_q <= 1'b0;
            is_empty_q <= 1'b1;
            pop_req_data_o <= '0;
        end else begin
            if (do_push) begin
                buffer[head_q] <= push_req_data_i;
                head_q <= ptr_next(head_q);
                is_full_q <= ptr_next(head_q) == tail_q;
                is_empty_q <= 1'b0;
            end
            if (do_pop) begin
                tail_q <= ptr_next(tail_q);
                is_full_q <= 1'b0;
                is_empty_q <= ptr_next(tail_q) == head_q;
            end

            if (push_req_val_i && pop_req_val_i) begin
                pop_req_data_o <= push_req_data_i;
            end else if (do_pop) begin
                pop_req_data_o <= buffer[tail_q];
            end
        end
    end
endmodule
