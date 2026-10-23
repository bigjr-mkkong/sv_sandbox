// spi_ram_model.v -- behavioral 23LC512 SPI SRAM, stand-in for the RP2040
// emulated RAM (sim only). SPI mode 0, 0x03 read / 0x02 write, 16-bit address.
// =============================================================================
// SPI RAM model
// Copied from: BF CPU
// Limitation: This model only support single byte return. It does not
// implement the sequential burst as a real SPI memory.
//
// It works for the unmofifield spi_master, but both of them does not match
// real SPI memory. This is for functional test on pipeline only, not final
// timing model
//
// Src: https://github.com/Josephwann/jj-tinytapeout/blob/main/test/spi_ram_model.v
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module spi_ram_model #(
    parameter integer SIZE = 65536
) (
    input  wire cs_n,
    input  wire sclk,
    input  wire mosi,
    output reg  miso
);

    localparam [7:0] CMD_READ  = 8'h03;
    localparam [7:0] CMD_WRITE = 8'h02;

    reg [7:0]  mem [0:SIZE-1];
    reg [31:0] rx;
    reg [7:0]  cmd;
    reg [15:0] addr;
    reg [7:0]  rdata;
    reg [5:0]  bitcnt;

    integer i;
    initial begin
        miso   = 1'b0;
        bitcnt = 6'd0;
        rx     = 32'd0;
        for (i = 0; i < SIZE; i = i + 1) mem[i] = 8'd0;
    end

    always @(negedge cs_n) begin
        bitcnt = 6'd0;
        rx     = 32'd0;
    end

    // sample MOSI on the rising edge; decode bits as they arrive
    always @(posedge sclk) begin
        if (!cs_n) begin
            rx     = {rx[30:0], mosi};
            bitcnt = bitcnt + 6'd1;
            if (bitcnt == 6'd8)  cmd = rx[7:0];
            if (bitcnt == 6'd24) begin
                addr  = rx[15:0];
                rdata = mem[rx[15:0]];
            end
            if (bitcnt == 6'd32 && cmd == CMD_WRITE) mem[addr] = rx[7:0];
        end
    end

    // drive MISO on the falling edge during a read's data phase
    always @(negedge sclk) begin
        if (!cs_n && cmd == CMD_READ && bitcnt >= 6'd24) begin
            miso  = rdata[7];
            rdata = {rdata[6:0], 1'b0};
        end
    end

endmodule

`default_nettype wire

