`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
module top_module_unit_test (
    input  logic clk_i,
    input  logic rst_ni,
    output logic halt_o
);
    logic spi_cs_n, spi_sclk, spi_mosi, spi_miso;

    top_module cpu (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .spi_cs_no(spi_cs_n),
        .spi_sclk_o(spi_sclk),
        .spi_mosi_o(spi_mosi),
        .spi_miso_i(spi_miso),
        .halt_o(halt_o)
    );

    spi_ram_model ram (
        .cs_n(spi_cs_n),
        .sclk(spi_sclk),
        .mosi(spi_mosi),
        .miso(spi_miso)
    );
endmodule
/* verilator lint_on DECLFILENAME */
