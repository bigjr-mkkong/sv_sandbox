`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
module iram_blk_unit_test (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic run_i,
    input  logic mem_write_i,
    input  logic [15:0] mem_addr_i,
    input  logic [7:0] mem_data_i,
    input  logic req_val_i,
    input  logic [15:0] pc_i,
    output logic req_rdy_o,
    output logic rsp_val_o,
    output logic [15:0] inst_o,
    input  logic rsp_rdy_i,
    output logic iram_val_o,
    output logic [15:0] iram_new_pc_o,
    output logic spi_rdy_o,
    output logic spi_val_o
);
    spi_ram_if iram_spi();

    assign iram_val_o = iram_spi.req_val;
    assign iram_new_pc_o = iram_spi.req_addr;
    assign iram_spi.req_rdy = spi_rdy_o;
    assign iram_spi.rsp_val = spi_val_o;

    iram_blk iram (
        .clk_i(clk_i),
        .rst_ni(rst_ni && run_i),
        .req_val_i(req_val_i),
        .pc_i(pc_i),
        .req_rdy_o(req_rdy_o),
        .rsp_val_o(rsp_val_o),
        .inst_o(inst_o),
        .rsp_rdy_i(rsp_rdy_i),
        .spi_o(iram_spi)
    );

    // Preload through the same memory port while IRAM is held in reset.
    ideal_spi_ram spi (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .req_val(run_i ? iram_val_o : mem_write_i),
        .req_rdy(spi_rdy_o),
        .req_we(run_i ? iram_spi.req_we : 1'b1),
        .req_addr(run_i ? iram_new_pc_o : mem_addr_i),
        .req_wdata(run_i ? iram_spi.req_wdata : mem_data_i),
        .resp_val(spi_val_o),
        .resp_rdata(iram_spi.rsp_rdata)
    );
endmodule
/* verilator lint_on DECLFILENAME */
