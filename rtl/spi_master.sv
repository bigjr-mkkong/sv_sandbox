// =============================================================================
// spi_master.v
// Copied from BF CPU
// Source at: https://github.com/Josephwann/jj-tinytapeout/blob/main/src/spi_master.v
// Extended locally for 16-bit instruction and 64-bit data bursts.
// =============================================================================

`default_nettype none

{% do unit_test(
    module_name = "spi_master",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/spi_master.py") %}
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
    input  wire        req_is_inst,
    input  wire [63:0] req_wdata,

    output reg         resp_val,
    output wire [63:0] resp_rdata,
    output wire [15:0] resp_rinst,

    // ---- SPI pins ----
    output reg         spi_cs_n,
    output reg         spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso
);

    // ---- 23LC512 command bytes ----
    localparam [7:0] CMD_READ  = 8'h03;
    localparam [7:0] CMD_WRITE = 8'h02;
    localparam [7:0] CMD_WRMR  = 8'h01;

    typedef enum logic [2:0] {
        ST_RESET, ST_SET_MODE, ST_IDLE, ST_XFER, ST_DONE, ST_WAIT
    } state_t;
    state_t state;

    // ---- CS-high recovery counter ----
    localparam CSW = (CS_HIGH_CYCLES <= 1) ? 1 : $clog2(CS_HIGH_CYCLES);
    reg [CSW-1:0] cs_wait;

    // ---- Datapath registers ----
    reg [23:0] shift_out;
    reg [63:0] shift_data;
    reg sampled_miso;
    reg [6:0] bit_idx;
    reg is_inst;

    // ---- SCLK divider ----
    localparam DIVW = (CLK_DIV <= 2) ? 1 : $clog2(CLK_DIV);
    localparam [DIVW-1:0] DIV_MAX = DIVW'(CLK_DIV - 1);   // width-matched compare value
    reg [DIVW-1:0] div_cnt;
    wire half_period_done = (div_cnt == DIV_MAX);

    assign spi_mosi = bit_idx < 7'd24 ? shift_out[23] : shift_data[63];
    // Byte-lane wiring converts MSB-first serial bytes to little-endian words.
    for (genvar i = 0; i < 8; i = i + 1) begin : response_bytes
        assign resp_rdata[i*8 +: 8] = shift_data[(7-i)*8 +: 8];
    end
    assign resp_rinst = {shift_data[7:0], shift_data[15:8]};

    assign req_rdy = (state == ST_IDLE);

    always @(posedge clk) begin : transfer_registers
        if (rst) begin
            spi_sclk <= 1'b0;
            shift_out <= 24'd0;
            shift_data <= 64'd0;
            sampled_miso <= 1'b0;
            bit_idx <= 7'd0;
            div_cnt <= '0;
            is_inst <= 1'b0;
        end else begin
            case (state)
                ST_RESET: begin
                    shift_out <= {CMD_WRMR, 8'h40, 8'h00};
                    spi_sclk <= 1'b0;
                    div_cnt <= '0;
                    bit_idx <= 7'd0;
                end
                ST_IDLE: begin
                    if (req_val) begin
                        shift_out <= {req_we ? CMD_WRITE : CMD_READ, req_addr};
                        for (integer i = 0; i < 8; i = i + 1)
                            shift_data[(7-i)*8 +: 8] <= req_wdata[i*8 +: 8];
                        div_cnt <= '0;
                        bit_idx <= 7'd0;
                        is_inst <= req_is_inst;
                    end
                end
                ST_SET_MODE, ST_XFER: begin
                    if (half_period_done) begin
                        div_cnt <= '0;
                        spi_sclk <= ~spi_sclk;
                        if (!spi_sclk) begin
                            sampled_miso <= spi_miso;
                        end else begin
                            if (bit_idx < 7'd24)
                                shift_out <= {shift_out[22:0], 1'b0};
                            else
                                shift_data <= {shift_data[62:0], sampled_miso};
                            bit_idx <= bit_idx + 7'd1;
                        end
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end
                default: spi_sclk <= 1'b0;
            endcase
        end
    end

    always @(posedge clk) begin : controller
        if (rst) begin
            state <= ST_RESET;
            spi_cs_n <= 1'b1;
            resp_val <= 1'b0;
            cs_wait <= '0;
        end else begin
            resp_val <= 1'b0;
            case (state)
                // Reset holds pins idle; configure RAM once after reset releases.
                ST_RESET: begin
                    spi_cs_n <= 1'b0;
                    state <= ST_SET_MODE;
                end
                ST_SET_MODE: begin
                    if (half_period_done && spi_sclk && bit_idx == 7'd15) begin
                        spi_cs_n <= 1'b1;
                        cs_wait <= CSW'(CS_HIGH_CYCLES - 1);
                        state <= ST_WAIT;
                    end
                end
                ST_IDLE: begin
                    if (req_val) begin
                        spi_cs_n <= 1'b0;
                        state <= ST_XFER;
                    end
                end
                ST_XFER: begin
                    if (half_period_done && spi_sclk
                            && bit_idx == (is_inst ? 7'd39 : 7'd87)) begin
                        spi_cs_n <= 1'b1;
                        state <= ST_DONE;
                    end
                end
                ST_DONE: begin
                    resp_val <= 1'b1;
                    cs_wait <= CSW'(CS_HIGH_CYCLES - 1);
                    state <= ST_WAIT;
                end
                ST_WAIT: begin
                    if (cs_wait == '0)
                        state <= ST_IDLE;
                    else
                        cs_wait <= cs_wait - 1'b1;
                end
                default: begin
                    state <= ST_RESET;
                    spi_cs_n <= 1'b1;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
