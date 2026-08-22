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

    simple_cache_1rw #(
        .CACHE_SIZE_KIB(CACHE_SIZE_KIB),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) simple_cache_1rw_inst0 (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .upstream(upstream_cache_if_inst0),
        .m_axil_wr(cache_interconn_axil_inst[0]),
        .m_axil_rd(cache_interconn_axil_inst[0])
    );

    simple_cache_1rw #(
        .CACHE_SIZE_KIB(CACHE_SIZE_KIB),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) simple_cache_1rw_inst1 (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .upstream(upstream_cache_if_inst1),
        .m_axil_wr(cache_interconn_axil_inst[1]),
        .m_axil_rd(cache_interconn_axil_inst[1])
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
