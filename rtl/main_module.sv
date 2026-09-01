`timescale 1ns / 1ps

module main_module #(
    parameter int unsigned ADDR_WIDTH     = config_pkg::ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH     = config_pkg::DATA_WIDTH,
    parameter int unsigned DATA_PER_LINE  = 8,
    parameter int unsigned CACHE_SIZE_KIB = 16
) (
    input  logic                  clk_i,
    input  logic                  rst_ni
);

    localparam int unsigned L1_CACHE_CNT = 2;
    localparam int unsigned CACHE_SRC_WIDTH = $clog2(L1_CACHE_CNT);

    upstream_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) upstream_cache_if_inst0();

    upstream_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) upstream_cache_if_inst1();

    taxi_axil_if #(
        .DATA_W(DATA_WIDTH * DATA_PER_LINE),
        .ADDR_W(ADDR_WIDTH)
    ) cache_interconn_axil_inst[2]();

    taxi_axil_if #(
        .DATA_W(DATA_WIDTH * DATA_PER_LINE),
        .ADDR_W(ADDR_WIDTH)
    ) interconn_dram_axil_inst[1]();

    coh_cache2bus_req #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SRC_WIDTH(CACHE_SRC_WIDTH)
    ) cache2arbiter_req[L1_CACHE_CNT]();

    coh_cache2bus_req #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SRC_WIDTH(CACHE_SRC_WIDTH)
    ) arbiter2global_req();

    coh_bus2cache_req #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) global2cache_req[L1_CACHE_CNT]();

    simple_cache_1rw #(
        .CACHE_SIZE_KIB(CACHE_SIZE_KIB),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE),
        .CACHE_ID(0)
    ) simple_cache_1rw_inst0 (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .upstream(upstream_cache_if_inst0),
        .m_axil_wr(cache_interconn_axil_inst[0]),
        .m_axil_rd(cache_interconn_axil_inst[0]),
        .cache2bus_req(cache2arbiter_req[0]),
        .bus2cache_req(global2cache_req[0])
    );

    simple_cache_1rw #(
        .CACHE_SIZE_KIB(CACHE_SIZE_KIB),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE),
        .CACHE_ID(1)
    ) simple_cache_1rw_inst1 (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .upstream(upstream_cache_if_inst1),
        .m_axil_wr(cache_interconn_axil_inst[1]),
        .m_axil_rd(cache_interconn_axil_inst[1]),
        .cache2bus_req(cache2arbiter_req[1]),
        .bus2cache_req(global2cache_req[1])
    );

    n21_coh_cache2bus_arbiter #(
        .SLV_CNT(L1_CACHE_CNT),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) coh_req_arbiter_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .slvs_i(cache2arbiter_req),
        .mst_o(arbiter2global_req)
    );

    cache_coherency_global #(
        .L1_CACHE_CNT(L1_CACHE_CNT),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) coh_global_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .cache_req(arbiter2global_req),
        .bus_op(global2cache_req)
    );

    taxi_axil_interconnect #(
        .S_COUNT(2),
        .M_COUNT(1),
        .ADDR_W(ADDR_WIDTH),
        .M_ADDR_W(32'(ADDR_WIDTH))
    ) two_2_one_axil_interconn_inst (
        .clk(clk_i),
        .rst(!rst_ni),
        .s_axil_wr(cache_interconn_axil_inst),
        .s_axil_rd(cache_interconn_axil_inst),
        .m_axil_wr(interconn_dram_axil_inst),
        .m_axil_rd(interconn_dram_axil_inst)
    );

    dumb_dram_1rw #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) dumb_dram_1rw_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .s_axil_wr(interconn_dram_axil_inst[0]),
        .s_axil_rd(interconn_dram_axil_inst[0])
    );
endmodule
