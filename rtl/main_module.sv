`timescale 1ns / 1ps

module main_module (
    input  logic clk_i,
    input  logic rst_ni,

    output logic spi_cs_no,
    output logic spi_sclk_o,
    output logic spi_mosi_o,
    input  logic spi_miso_i,
    output logic halt_o
);
    logic icache_req_val, icache_req_rdy;
    logic icache_rsp_val, icache_rsp_rdy;
    logic [15:0] pc, instruction;

    // Source 0 carries pipeline data; source 1 carries instruction refills.
    spi_ram_if sources[2]();
    spi_ram_if master();

    togawa_pipeline pipeline (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .icache_req_val_o(icache_req_val),
        .pc_o(pc),
        .icache_req_rdy_i(icache_req_rdy),
        .icache_val_i(icache_rsp_val),
        .icache_inst_i(instruction),
        .icache_rdy_o(icache_rsp_rdy),
        .spi_o(sources[0]),
        .halt(halt_o)
    );

    iram_blk iram (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .req_val_i(icache_req_val),
        .pc_i(pc),
        .req_rdy_o(icache_req_rdy),
        .rsp_val_o(icache_rsp_val),
        .inst_o(instruction),
        .rsp_rdy_i(icache_rsp_rdy),
        .spi_o(sources[1])
    );

    two2one_spi_arbiter arbiter (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .slvs_i(sources),
        .mst_o(master)
    );

    // The arbiter captures the master's response pulse; the master has no ready input.
    spi_master spi (
        .clk(clk_i),
        .rst(!rst_ni),
        .req_val(master.req_val),
        .req_rdy(master.req_rdy),
        .req_we(master.req_we),
        .req_addr(master.req_addr),
        .req_wdata(master.req_wdata),
        .resp_val(master.rsp_val),
        .resp_rdata(master.rsp_rdata),
        .spi_cs_n(spi_cs_no),
        .spi_sclk(spi_sclk_o),
        .spi_mosi(spi_mosi_o),
        .spi_miso(spi_miso_i)
    );
endmodule
