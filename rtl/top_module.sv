`timescale 1ns / 1ps

{% do unit_test(
    module_name = "top_module",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/top_module.py") %}
module top_module (
    input  logic clk_i,
    input  logic rst_ni,
    output logic spi_cs_no,
    output logic spi_sclk_o,
    output logic spi_mosi_o,
    input  logic spi_miso_i,
    output logic halt_o
);
    logic rst_sync_ni;

    reset_sync reset_sync_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .rst_sync_ni(rst_sync_ni)
    );

    main_module main_module_inst (
        .clk_i(clk_i),
        .rst_ni(rst_sync_ni),
        .spi_cs_no(spi_cs_no),
        .spi_sclk_o(spi_sclk_o),
        .spi_mosi_o(spi_mosi_o),
        .spi_miso_i(spi_miso_i),
        .halt_o(halt_o)
    );
endmodule
