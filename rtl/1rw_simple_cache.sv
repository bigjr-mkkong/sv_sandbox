`timescale 1ns / 1ps

/*
 * Configurable direct-mapped cache.
 *
 * A write allocates a line. Since this cache has no backing-memory port,
 * words other than the written word are cleared when a new tag is allocated.
 * A read whose tag is not resident returns RSP_MISS in rsp_state_o.
 */

/* verilator lint_off DECLFILENAME */
{% do unit_test(
    module_name = "simple_cache_1rw",
    test_framework = "cocotb",
    test_path = "dv/cocotb_benches/1rw_simple_cache_tb.py") %}
module simple_cache_1rw #(
    parameter int unsigned CACHE_SIZE_KIB = 16,
    parameter int unsigned ADDR_WIDTH     = 64,
    parameter int unsigned DATA_WIDTH     = 64,
    parameter int unsigned DATA_PER_LINE  = 8
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,

    input  logic                  req_val_i,
    input  logic [ADDR_WIDTH-1:0] req_addr_i,
    input  logic [DATA_WIDTH-1:0] req_data_i,
    input  logic                  req_rw_flag_i, // 0: read, 1: write
    output logic                  req_rdy_o,

    input  logic                  rsp_rdy_i,
    output logic [DATA_WIDTH-1:0] rsp_data_o,
    output logic [3:0]            rsp_state_o,
    output logic                  rsp_val_o
);

    localparam int unsigned CACHE_BYTES = CACHE_SIZE_KIB * 1024;
    localparam int unsigned DATA_BYTES = DATA_WIDTH / 8;
    localparam int unsigned LINE_BYTES = DATA_BYTES * DATA_PER_LINE;
    localparam int unsigned ROW_CNT = CACHE_BYTES / LINE_BYTES;
    localparam int unsigned BYTE_OFFSET_WIDTH = $clog2(DATA_BYTES);
    localparam int unsigned WORD_INDEX_WIDTH = $clog2(DATA_PER_LINE);
    localparam int unsigned OFFSET_WIDTH = $clog2(LINE_BYTES);
    localparam int unsigned INDEX_BITS = $clog2(ROW_CNT);
    localparam int unsigned TAG_WIDTH = ADDR_WIDTH - OFFSET_WIDTH - INDEX_BITS;

    localparam logic [3:0] RSP_OK   = 4'd0;
    localparam logic [3:0] RSP_MISS = 4'd1;

    typedef struct packed {
        logic                                      line_valid;
        logic [TAG_WIDTH-1:0]                      line_tag;
        logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] line_data;
    } cache_line_t;

    typedef enum logic {
        IDLE,
        RESP
    } state_e;

    cache_line_t cache [ROW_CNT-1:0];

    state_e state_d, state_q;

    logic [DATA_WIDTH-1:0] rsp_data_d, rsp_data_q;
    logic [3:0]            rsp_state_d, rsp_state_q;

    logic [TAG_WIDTH-1:0]        req_addr_tag;
    logic [INDEX_BITS-1:0]      req_addr_idx;
    logic [WORD_INDEX_WIDTH-1:0] req_word_idx;

    logic                                      write_cache_flag;
    logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] write_cache_line;
    logic                                      is_hit;

    always_comb begin
        state_d = state_q;
        rsp_data_d = rsp_data_q;
        rsp_state_d = rsp_state_q;

        req_rdy_o = 1'b0;
        rsp_data_o = rsp_data_q;
        rsp_state_o = rsp_state_q;
        rsp_val_o = 1'b0;

        {req_addr_tag, req_addr_idx, req_word_idx} = {
            TAG_WIDTH'(req_addr_i >> (OFFSET_WIDTH + INDEX_BITS)),
            INDEX_BITS'(req_addr_i >> OFFSET_WIDTH),
            WORD_INDEX_WIDTH'(req_addr_i >> BYTE_OFFSET_WIDTH)
        };

        is_hit = cache[req_addr_idx].line_valid
            && cache[req_addr_idx].line_tag == req_addr_tag;

        write_cache_flag = 1'b0;
        write_cache_line = cache[req_addr_idx].line_data;

        case (state_q)
            IDLE: begin
                req_rdy_o = 1'b1;

                if (req_val_i) begin
                    rsp_data_d = '0;

                    if (req_rw_flag_i) begin// Write
                        if (!is_hit) begin
                            write_cache_line = '0;
                        end
                        write_cache_line[req_word_idx] = req_data_i;
                        write_cache_flag = 1'b1;
                        rsp_state_d = RSP_OK;
                    end else if (is_hit) begin //Read
                        rsp_data_d = cache[req_addr_idx].line_data[req_word_idx];
                        rsp_state_d = RSP_OK;
                    end else begin
                        rsp_state_d = RSP_MISS;
                    end

                    state_d = RESP;
                end
            end

            RESP: begin
                rsp_val_o = 1'b1;
                if (rsp_rdy_i) begin
                    state_d = IDLE;
                end
            end

            default: begin
                state_d = IDLE;
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            rsp_data_q <= '0;
            rsp_state_q <= RSP_OK;

            for (int unsigned i = 0; i < ROW_CNT; i++) begin
                cache[i].line_valid <= 1'b0;
            end
        end else begin
            state_q <= state_d;
            rsp_data_q <= rsp_data_d;
            rsp_state_q <= rsp_state_d;

            if (write_cache_flag) begin
                cache[req_addr_idx].line_valid <= 1'b1;
                cache[req_addr_idx].line_tag <= req_addr_tag;
                cache[req_addr_idx].line_data <= write_cache_line;
            end
        end
    end

endmodule
/* verilator lint_on DECLFILENAME */
