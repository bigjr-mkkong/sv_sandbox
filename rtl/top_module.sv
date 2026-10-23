`timescale 1ns / 1ps

module top_module (
    input  logic clk_i,
    input  logic rst_ni,
    output logic spi_cs_no,
    output logic spi_sclk_o,
    output logic spi_mosi_o,
    input  logic spi_miso_i,
    output logic halt_o
);
    main_module main_module_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .spi_cs_no(spi_cs_no),
        .spi_sclk_o(spi_sclk_o),
        .spi_mosi_o(spi_mosi_o),
        .spi_miso_i(spi_miso_i),
        .halt_o(halt_o)
    );
endmodule
