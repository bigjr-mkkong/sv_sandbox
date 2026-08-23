`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNDRIVEN */
module simple_cache_1rw_unit_test;
    localparam int unsigned ADDR_WIDTH = 64;
    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned DATA_PER_LINE = 8;

    logic clk_i;
    logic rst_ni;

    logic coh_bus_req_rdy_i;
    config_pkg::coh_bus_op coh_bus_req_op_o;
    logic [ADDR_WIDTH-1:0] coh_bus_req_addr_o;
    logic coh_bus_req_val_o;
    logic coh_bus_rsp_val_i;
    logic coh_bus_shared_i;
    logic coh_bus_rsp_rdy_o;

    upstream_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) upstream();

    taxi_axil_if #(
        .DATA_W(DATA_WIDTH * DATA_PER_LINE),
        .ADDR_W(ADDR_WIDTH)
    ) m_axil();

    simple_cache_1rw #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .upstream(upstream),
        .m_axil_wr(m_axil),
        .m_axil_rd(m_axil),
        .coh_bus_req_rdy_i(coh_bus_req_rdy_i),
        .coh_bus_req_op_o(coh_bus_req_op_o),
        .coh_bus_req_addr_o(coh_bus_req_addr_o),
        .coh_bus_req_val_o(coh_bus_req_val_o),
        .coh_bus_rsp_val_i(coh_bus_rsp_val_i),
        .coh_bus_shared_i(coh_bus_shared_i),
        .coh_bus_rsp_rdy_o(coh_bus_rsp_rdy_o)
    );
endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on DECLFILENAME */
