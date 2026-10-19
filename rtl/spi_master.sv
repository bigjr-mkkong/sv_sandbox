// =============================================================================
// spi_master.v
// Copied from BF CPU
// Source at: https://github.com/Josephwann/jj-tinytapeout/blob/main/src/spi_master.v
// =============================================================================

`default_nettype none

module spi_master #(
    parameter CLK_DIV        = 4,
    parameter CS_HIGH_CYCLES = 32
) (
    input  wire        clk,
    input  wire        rst,

    // ---- Memory request/response port ----
    input  wire        req_val,
    output wire        req_rdy,
    input  wire        req_we,
    input  wire [15:0] req_addr,
    input  wire [7:0]  req_wdata,

    output reg         resp_val,
    output reg  [7:0]  resp_rdata,

    // ---- SPI pins ----
    output reg         spi_cs_n,
    output reg         spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso
);

    // ---- spi-ram-emu command bytes ----
    localparam [7:0] CMD_READ  = 8'h03;
    localparam [7:0] CMD_WRITE = 8'h02;

    // ---- Top-level states ----
    localparam ST_IDLE = 2'd0;
    localparam ST_XFER = 2'd1;
    localparam ST_DONE = 2'd2;
    localparam ST_WAIT = 2'd3;   // CS-high recovery before the next frame
    reg [1:0] state;

    // ---- CS-high recovery counter ----
    localparam CSW = (CS_HIGH_CYCLES <= 1) ? 1 : $clog2(CS_HIGH_CYCLES);
    reg [CSW-1:0] cs_wait;

    // ---- Datapath registers ----
    reg [31:0] shift_out;
    reg [7:0]  shift_in;
    reg [5:0]  bit_idx;

    // ---- SCLK divider ----
    localparam DIVW = (CLK_DIV <= 2) ? 1 : $clog2(CLK_DIV);
    localparam [DIVW-1:0] DIV_MAX = DIVW'(CLK_DIV - 1);   // width-matched compare value
    reg [DIVW-1:0] div_cnt;
    wire half_period_done = (div_cnt == DIV_MAX);

    assign spi_mosi = shift_out[31];

    assign req_rdy = (state == ST_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state      <= ST_IDLE;
            spi_cs_n   <= 1'b1;
            spi_sclk   <= 1'b0;
            resp_val   <= 1'b0;
            resp_rdata <= 8'h00;
            shift_out  <= 32'h0;
            shift_in   <= 8'h0;
            bit_idx    <= 6'd0;
            div_cnt    <= {DIVW{1'b0}};
            cs_wait    <= {CSW{1'b0}};
        end else begin
            resp_val <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                ST_IDLE: begin
                    spi_cs_n <= 1'b1;
                    spi_sclk <= 1'b0;
                    if (req_val) begin
                        shift_out <= req_we ? {CMD_WRITE, req_addr, req_wdata}
                                            : {CMD_READ,  req_addr, 8'h00};
                        spi_cs_n  <= 1'b0;   // assert CS, begin the frame
                        spi_sclk  <= 1'b0;
                        div_cnt   <= {DIVW{1'b0}};
                        bit_idx   <= 6'd0;
                        state     <= ST_XFER;
                    end
                end

                // ---------------------------------------------------------
                ST_XFER: begin
                    if (half_period_done) begin
                        div_cnt  <= {DIVW{1'b0}};
                        spi_sclk <= ~spi_sclk;

                        if (!spi_sclk) begin
                            shift_in <= {shift_in[6:0], spi_miso};
                        end else begin
                            shift_out <= {shift_out[30:0], 1'b0};
                            bit_idx   <= bit_idx + 6'd1;
                            if (bit_idx == 6'd31) begin
                                spi_cs_n <= 1'b1;
                                state    <= ST_DONE;
                            end
                        end
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                // ---------------------------------------------------------
                ST_DONE: begin
                    resp_val   <= 1'b1;
                    resp_rdata <= shift_in;
                    spi_sclk   <= 1'b0;
                    spi_cs_n   <= 1'b1;                    // keep CS de-asserted
                    cs_wait    <= CSW'(CS_HIGH_CYCLES - 1);
                    state      <= ST_WAIT;
                end

                // ---------------------------------------------------------
                // Hold CS high long enough for the RP2040 to recover before
                // the next frame. req_rdy stays low (state != ST_IDLE), so a
                // pending request is held until recovery completes.
                ST_WAIT: begin
                    spi_cs_n <= 1'b1;
                    spi_sclk <= 1'b0;
                    if (cs_wait == {CSW{1'b0}})
                        state <= ST_IDLE;
                    else
                        cs_wait <= cs_wait - 1'b1;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire

