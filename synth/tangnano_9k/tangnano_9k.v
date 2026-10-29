`timescale 1ns / 1ps

module tangnano_9k (
    input  wire       clk,
    input  wire       togawa_rst_ni,
    output wire       togawa_halt,
    output wire [5:0] led,
    output wire       spi_cs_no,
    output wire       spi_sclk_o,
    output wire       spi_mosi_o,
    input  wire       spi_miso_i
);

    wire clk_48;
    wire pll_locked;

    tangnano_9k_pll pll (
        .clock_in(clk),
        .clock_out(clk_48),
        .locked(pll_locked)
    );

    // Hold reset until PLL lock; top_module synchronizes its release.
    top_module cpu (
        .clk_i(clk_48),
        .rst_ni(togawa_rst_ni & pll_locked),
        .spi_cs_no(spi_cs_no),
        .spi_sclk_o(spi_sclk_o),
        .spi_mosi_o(spi_mosi_o),
        .spi_miso_i(spi_miso_i),
        .halt_o(togawa_halt)
    );

    // LEDs are active low: LED 0 indicates PLL lock; the rest are static.
    assign led = {5'b10101, !pll_locked};

endmodule
