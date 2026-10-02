`timescale 1ns / 1ps


module sb_reset_sync (
    input  logic clk_i,
    input  logic arst_ni,
    output logic rst_ni
);

    (* ASYNC_REG = "TRUE" *) logic rst_q0, rst_q1;

    always_ff @(posedge clk_i or negedge arst_ni) begin
        if (!arst_ni) begin
            rst_q0 <= 1'b0;
            rst_q1 <= 1'b0;
        end else begin
            rst_q0 <= 1'b1;
            rst_q1 <= rst_q0;
        end
    end

    assign rst_ni = rst_q1;

endmodule


{% do unit_test(
    module_name = "sb_sync",
    test_framework = "cocotb",
    test_path = "dv/cocotb_benches/cdc_sb_sync_tb.py",
    use_wrapper = false) %}
module sb_sync (
    input  logic w_clk_i,
    input  logic rst_ni,
    input  logic r_clk_i,
    input  logic data_i,
    output logic data_o
);

    logic w_rst_ni;
    logic r_rst_ni;

    logic in_0;
    (* ASYNC_REG = "TRUE" *) logic out_0, out_1;

    sb_reset_sync w_reset_sync (
        .clk_i  (w_clk_i),
        .arst_ni(rst_ni),
        .rst_ni (w_rst_ni)
    );

    sb_reset_sync r_reset_sync (
        .clk_i  (r_clk_i),
        .arst_ni(rst_ni),
        .rst_ni (r_rst_ni)
    );

    always_ff @(posedge w_clk_i) begin
        if (!w_rst_ni)
            in_0 <= 1'b0;
        else
            in_0 <= data_i;
    end

    always_ff @(posedge r_clk_i) begin
        if (!r_rst_ni) begin
            out_0 <= 1'b0;
            out_1 <= 1'b0;
        end else begin
            out_0 <= in_0;
            out_1 <= out_0;
        end
    end

    assign data_o = out_1;

endmodule

module sb_sync_handshake (
    input  logic w_clk_i,
    input  logic rst_ni,
    input  logic r_clk_i,

    input  logic producer_val_i,
    output logic producer_ack_o,
    input  logic producer_data_i,

    output logic consumer_val_o,
    input  logic consumer_ack_i,
    output logic consumer_data_o
);

    sb_sync producer_val_sync (
        .w_clk_i(w_clk_i),
        .rst_ni (rst_ni),
        .r_clk_i(r_clk_i),
        .data_i (producer_val_i),
        .data_o (consumer_val_o)
    );

    assign consumer_data_o = producer_data_i;

    sb_sync consumer_ack_sync (
        .w_clk_i(r_clk_i),
        .rst_ni (rst_ni),
        .r_clk_i(w_clk_i),
        .data_i (consumer_ack_i),
        .data_o (producer_ack_o)
    );

endmodule

module sb_sync_pulse (
    input  logic w_clk_i,
    input  logic rst_ni,
    input  logic r_clk_i,

    input  logic producer_data_i,
    output logic consumer_data_o
);

    logic w_rst_ni;
    logic r_rst_ni;

    logic prod_tog;
    logic cons_tog_sync;
    logic cons_tog_q;

    sb_reset_sync w_reset_sync (
        .clk_i  (w_clk_i),
        .arst_ni(rst_ni),
        .rst_ni (w_rst_ni)
    );

    sb_reset_sync r_reset_sync (
        .clk_i  (r_clk_i),
        .arst_ni(rst_ni),
        .rst_ni (r_rst_ni)
    );

    always_ff @(posedge w_clk_i) begin
        if (!w_rst_ni) begin
            prod_tog <= 1'b0;
        end else if (producer_data_i) begin
            prod_tog <= ~prod_tog;
        end
    end

    sb_sync fw_sync (
        .w_clk_i(w_clk_i),
        .rst_ni (rst_ni),
        .r_clk_i(r_clk_i),
        .data_i (prod_tog),
        .data_o (cons_tog_sync)
    );

    always_ff @(posedge r_clk_i) begin
        if (!r_rst_ni) begin
            cons_tog_q      <= 1'b0;
            consumer_data_o <= 1'b0;
        end else begin
            cons_tog_q      <= cons_tog_sync;
            consumer_data_o <= cons_tog_sync ^ cons_tog_q;
        end
    end

endmodule
