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

    taxi_axil_if #(
        .DATA_W(DATA_WIDTH),
        .ADDR_W(ADDR_WIDTH)
    ) upstream_cache_axil_inst();

    taxi_axil_if #(
        .DATA_W(DATA_WIDTH * DATA_PER_LINE),
        .ADDR_W(ADDR_WIDTH)
    ) cache_dram_axil_inst();

    dumb_dram_1rw #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) dumb_dram_1rw_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .s_axil_wr(cache_dram_axil_inst),
        .s_axil_rd(cache_dram_axil_inst)
    );

    simple_cache_1rw #(
        .CACHE_SIZE_KIB(CACHE_SIZE_KIB),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) simple_cache_1rw_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .s_axil_wr(upstream_cache_axil_inst),
        .s_axil_rd(upstream_cache_axil_inst),
        .m_axil_wr(cache_dram_axil_inst),
        .m_axil_rd(cache_dram_axil_inst)
    );

endmodule
