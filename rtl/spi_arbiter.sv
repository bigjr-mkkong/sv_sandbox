module two2one_spi_arbiter(
    input  wire        clk_i,
    input  wire        rst_ni,

    spi_ram_if.if_sink  slvs_i[2],
    spi_ram_if.if_src   mst_o
);

endmodule
