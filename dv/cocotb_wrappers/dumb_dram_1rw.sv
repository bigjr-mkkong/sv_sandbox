`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNDRIVEN */
module dumb_dram_1rw_unit_test;
    localparam int unsigned ADDR_WIDTH = 64;
    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned DATA_PER_LINE = 8;

    logic clk_i;
    logic rst_ni;

    taxi_axil_if #(
        .DATA_W(DATA_WIDTH * DATA_PER_LINE),
        .ADDR_W(ADDR_WIDTH)
    ) s_axil();

    dumb_dram_1rw #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .s_axil_wr(s_axil),
        .s_axil_rd(s_axil)
    );
endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on DECLFILENAME */
