// Behavioral 23LC512 SPI SRAM: mode-0 reads/writes and mode-register access.
// =============================================================================
// SPI RAM model
// Copied from: BF CPU
// Extended locally for sequential/page addressing and WRMR/RDMR. This is a
// functional model; it does not model electrical setup/hold or output delays.
//
// Src: https://github.com/Josephwann/jj-tinytapeout/blob/main/test/spi_ram_model.v
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module spi_ram_model #(
    parameter integer SIZE = 65536,
    parameter [7:0] INITIAL_MODE = 8'h40
) (
    input  wire cs_n,
    input  wire sclk,
    input  wire mosi,
    output reg  miso
);

    localparam [7:0] CMD_READ  = 8'h03;
    localparam [7:0] CMD_WRITE = 8'h02;
    localparam [7:0] CMD_WRMR  = 8'h01;
    localparam [7:0] CMD_RDMR  = 8'h05;

    reg [7:0]  mem [0:SIZE-1];
    reg [31:0] rx;
    reg [7:0]  cmd;
    reg [15:0] addr;
    reg [7:0]  rdata;
    reg [5:0]  bitcnt;
    reg [7:0]  mode;

    function automatic [15:0] next_address(input [15:0] current);
        case (mode[7:6])
            2'b01: next_address = current + 16'd1;
            2'b10: next_address = {current[15:5], current[4:0] + 5'd1};
            default: next_address = current;
        endcase
    endfunction

    integer i;
    initial begin
        miso   = 1'b0;
        bitcnt = 6'd0;
        rx     = 32'd0;
        mode   = INITIAL_MODE;
        cmd    = 8'd0;
        addr   = 16'd0;
        rdata  = 8'd0;
        for (i = 0; i < SIZE; i = i + 1) mem[i] = 8'd0;
    end

    always @(negedge cs_n) begin
        bitcnt = 6'd0;
        rx     = 32'd0;
        cmd    = 8'd0;
    end

    // sample MOSI on the rising edge; decode bits as they arrive
    always @(posedge sclk) begin
        if (!cs_n) begin
            rx     = {rx[30:0], mosi};
            bitcnt = bitcnt + 6'd1;
            if (bitcnt == 6'd8) begin
                cmd = rx[7:0];
                if (cmd == CMD_RDMR) rdata = mode;
            end
            if (bitcnt == 6'd16 && cmd == CMD_WRMR) mode = rx[7:0] & 8'hC0;
            if (bitcnt == 6'd24 && (cmd == CMD_READ || cmd == CMD_WRITE)) begin
                addr  = rx[15:0];
                rdata = mem[rx[15:0]];
            end
            if (bitcnt == 6'd32 && (cmd == CMD_READ || cmd == CMD_WRITE)) begin
                if (cmd == CMD_WRITE) mem[addr] = rx[7:0];
                addr = next_address(addr);
                rdata = mem[addr];
                // Reuse the data-byte phase for the remainder of the frame.
                bitcnt = 6'd24;
            end
        end
    end

    // drive MISO on the falling edge during a read's data phase
    always @(negedge sclk or posedge cs_n) begin
        if (cs_n) begin
            miso = 1'b0;
        end else if ((cmd == CMD_READ && bitcnt >= 6'd24)
                     || (cmd == CMD_RDMR && bitcnt >= 6'd8)) begin
            miso  = rdata[7];
            rdata = {rdata[6:0], 1'b0};
        end
    end

endmodule

`default_nettype wire

