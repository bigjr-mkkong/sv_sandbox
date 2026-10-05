`timescale 1ns / 1ps

{% do unit_test(
    module_name = "async_fifo",
    test_framework = "cocotb",
    test_path = "dv/cocotb_benches/async_fifo_tb.py",
    use_wrapper = false,
    rtl_dependencies = ["rtl/cdc.sv", "rtl/dual_port_ram.sv"]) %}
module async_fifo #(
    parameter int unsigned ele_sz_bit = 32,
    parameter int unsigned ele_cnt = 16
) (
    input  logic                  r_clk_i,
    input  logic                  rst_ni,
    input  logic                  r_val_i,
    output logic [ele_sz_bit-1:0] r_data_o,
    output logic                  r_rdy_o,

    input  logic                  w_clk_i,
    input  logic                  w_val_i,
    input  logic [ele_sz_bit-1:0] w_data_i,
    output logic                  w_rdy_o
);
    localparam int unsigned ADDR_W = ele_cnt > 1 ? $clog2(ele_cnt) : 1;
    localparam int unsigned PTR_W = ADDR_W + 1;
    localparam logic [PTR_W-1:0] FULL_MASK = PTR_W'(3) << (PTR_W-2);

    initial begin
        if (ele_cnt < 2 || (ele_cnt & (ele_cnt - 1)) != 0)
            $fatal(1, "async_fifo ele_cnt must be a power of two >= 2");
    end

    function automatic logic [PTR_W-1:0] gray_code(input logic [PTR_W-1:0] bin);
        return bin ^ (bin >> 1);
    endfunction

    logic w_rst_ni, r_rst_ni;
    logic [PTR_W-1:0] w_bin_q, r_bin_q;
    logic [PTR_W-1:0] w_gray_q, r_gray_q;
    (* ASYNC_REG = "TRUE" *) logic [PTR_W-1:0] r_gray_w0, r_gray_w1;
    (* ASYNC_REG = "TRUE" *) logic [PTR_W-1:0] w_gray_r0, w_gray_r1;
    logic write_en, read_en, mem_rdy;

    sb_reset_sync w_reset_sync (
        .clk_i(w_clk_i), .arst_ni(rst_ni), .rst_ni(w_rst_ni)
    );
    sb_reset_sync r_reset_sync (
        .clk_i(r_clk_i), .arst_ni(rst_ni), .rst_ni(r_rst_ni)
    );

    // Writes use val/ready; r_rdy_o validates the registered RAM read response.
    assign w_rdy_o = w_rst_ni && (w_gray_q != (r_gray_w1 ^ FULL_MASK));
    assign write_en = w_val_i && w_rdy_o;
    assign read_en = r_val_i && r_rst_ni && (r_gray_q != w_gray_r1);
    assign r_rdy_o = r_rst_ni && mem_rdy;

    dual_port_ram #(.ele_sz_bit(ele_sz_bit), .ele_cnt(ele_cnt)) mem (
        .r_clk_i(r_clk_i), .r_addr_i(r_bin_q[ADDR_W-1:0]),
        .r_val_i(read_en), .r_data_o(r_data_o), .r_rdy_o(mem_rdy),
        .w_clk_i(w_clk_i), .w_addr_i(w_bin_q[ADDR_W-1:0]),
        .w_data_i(w_data_i), .w_val_i(write_en)
    );

    always_ff @(posedge w_clk_i or negedge w_rst_ni) begin
        if (!w_rst_ni) begin
            w_bin_q <= '0;
            w_gray_q <= '0;
            r_gray_w0 <= '0;
            r_gray_w1 <= '0;
        end else begin
            r_gray_w0 <= r_gray_q;
            r_gray_w1 <= r_gray_w0;
            if (write_en) begin
                w_bin_q <= w_bin_q + 1'b1;
                w_gray_q <= gray_code(w_bin_q + 1'b1);
            end
        end
    end

    always_ff @(posedge r_clk_i or negedge r_rst_ni) begin
        if (!r_rst_ni) begin
            r_bin_q <= '0;
            r_gray_q <= '0;
            w_gray_r0 <= '0;
            w_gray_r1 <= '0;
        end else begin
            w_gray_r0 <= w_gray_q;
            w_gray_r1 <= w_gray_r0;
            if (read_en) begin
                r_bin_q <= r_bin_q + 1'b1;
                r_gray_q <= gray_code(r_bin_q + 1'b1);
            end
        end
    end
endmodule
