`timescale 1ns / 1ps

module spi_master_unit_test (
    input logic clk,
    input logic rst,
    input logic req_val,
    output wire req_rdy,
    input logic req_we,
    input logic [15:0] req_addr,
    input logic req_is_inst,
    input logic [63:0] req_wdata,
    output wire resp_val,
    output wire [63:0] resp_rdata,
    output wire [15:0] resp_rinst,
    output wire spi_cs_n,
    output wire spi_sclk,
    output wire spi_mosi,
    output wire spi_miso
);
    spi_master master (.*);
    // Match a Pi handoff that has explicitly selected byte mode.
    spi_ram_model #(.INITIAL_MODE(8'h00)) ram (
        .cs_n(spi_cs_n), .sclk(spi_sclk), .mosi(spi_mosi), .miso(spi_miso)
    );
endmodule
