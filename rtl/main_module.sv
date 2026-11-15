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
    logic [15:0] pc;
    // The 16-bit word PC aliases into the external 64 KiB byte address space.
    wire _unused_pc = pc[15];
    spi_ram_if #(.DATA_W(64)) sources[2]();
    spi_ram_if #(.DATA_W(64)) master();

    togawa_pipeline pipeline (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .icache_req_val_o(sources[1].req_val),
        .pc_o(pc),
        .icache_req_rdy_i(sources[1].req_rdy),
        .icache_val_i(sources[1].rsp_val),
        .icache_inst_i(sources[1].rsp_rinst),
        .icache_rdy_o(sources[1].rsp_rdy),
        .spi_o(sources[0]),
        .halt(halt_o)
    );

    assign sources[1].req_we = 1'b0;
    assign sources[1].req_is_inst = 1'b1;
    assign sources[1].req_addr = {pc[14:0], 1'b0};
    assign sources[1].req_wdata = 64'd0;

    two2one_spi_arbiter #(.DATA_W(64)) arbiter (
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
        .req_is_inst(master.req_is_inst),
        .req_wdata(master.req_wdata),
        .resp_val(master.rsp_val),
        .resp_rdata(master.rsp_rdata),
        .resp_rinst(master.rsp_rinst),
        .spi_cs_n(spi_cs_no),
        .spi_sclk(spi_sclk_o),
        .spi_mosi(spi_mosi_o),
        .spi_miso(spi_miso_i)
    );
endmodule
