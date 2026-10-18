`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
module iram_blk_unit_test (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic req_val_i,
    input  logic [15:0] pc_i,
    output logic req_rdy_o,
    output logic rsp_val_o,
    output logic [15:0] inst_o,
    input  logic rsp_rdy_i,
    output logic iram_val_o,
    output logic [15:0] iram_new_pc_o,
    output logic spi_rdy_o,
    output logic spi_cs_n,
    output logic spi_sclk,
    output logic spi_mosi,
    input  logic spi_miso
);
    spi_ram_if spi_req();

    assign spi_req.req_val_i = iram_val_o;
    assign spi_req.req_we = 1'b0;
    assign spi_req.req_addr = iram_new_pc_o;
    assign spi_req.req_wdata = 8'd0;
    assign spi_rdy_o = spi_req.req_rdy;

    iram_blk iram (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .req_val_i(req_val_i),
        .pc_i(pc_i),
        .req_rdy_o(req_rdy_o),
        .rsp_val_o(rsp_val_o),
        .inst_o(inst_o),
        .rsp_rdy_i(rsp_rdy_i),
        .iram_val_o(iram_val_o),
        .iram_new_pc_o(iram_new_pc_o),
        .spi_rdy_i(spi_rdy_o),
        .spi_val_i(spi_req.resp_val),
        .spi_data_i(spi_req.resp_rdata)
    );

    spi_master #(.CLK_DIV(1), .CS_HIGH_CYCLES(3)) spi (
        .clk(clk_i),
        .rst(!rst_ni),
        .mem_if(spi_req),
        .spi_cs_n(spi_cs_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );
endmodule
/* verilator lint_on DECLFILENAME */
