`timescale 1ns / 1ps

/*
 * Blocking, direct-mapped, write-back cache.
 *
 * The synchronized upstream request interface transfers one DATA_WIDTH word.
 * The downstream AXI-Lite bus transfers one complete cache line per request.
 * Writes update the cache and mark the line dirty; a dirty victim is written
 * downstream before it is replaced.
 */

/* verilator lint_off DECLFILENAME */
{% do unit_test(
    module_name = "simple_cache_1rw",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/1rw_simple_cache_tb.py") %}
module simple_cache_1rw #(
    parameter int unsigned CACHE_SIZE_KIB = 16,
    parameter int unsigned ADDR_WIDTH     = 64,
    parameter int unsigned DATA_WIDTH     = 64,
    parameter int unsigned DATA_PER_LINE  = 8
) (
    input logic clk_i,
    input logic rst_ni,

    // Upstream CPU request/response interface. req_rw_flag is 1 for writes.
    upstream_if.if_slv upstream,

    // Downstream memory AXI-Lite master interface.
    taxi_axil_if.wr_mst m_axil_wr,
    taxi_axil_if.rd_mst m_axil_rd
);

    localparam int unsigned CACHE_BYTES = CACHE_SIZE_KIB * 1024;
    localparam int unsigned DATA_BYTES = DATA_WIDTH / 8;
    localparam int unsigned LINE_BYTES = DATA_BYTES * DATA_PER_LINE;
    localparam int unsigned LINE_WIDTH = DATA_WIDTH * DATA_PER_LINE;
    localparam int unsigned ROW_CNT = CACHE_BYTES / LINE_BYTES;
    localparam int unsigned BYTE_OFFSET_WIDTH = $clog2(DATA_BYTES);
    localparam int unsigned WORD_INDEX_WIDTH = $clog2(DATA_PER_LINE);
    localparam int unsigned OFFSET_WIDTH = $clog2(LINE_BYTES);
    localparam int unsigned INDEX_BITS = $clog2(ROW_CNT);
    localparam int unsigned TAG_WIDTH = ADDR_WIDTH - OFFSET_WIDTH - INDEX_BITS;

    typedef struct packed {
        logic                                      line_valid;
        logic                                      line_dirty;
        logic [TAG_WIDTH-1:0]                      line_tag;
        logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] line_data;
    } cache_line_t;

    typedef enum logic [2:0] {
        IDLE,
        RESP,
        MISS_SUBMIT,
        MISS_WAIT,
        EVICT_SUBMIT,
        EVICT_WAIT
    } state_e;

    cache_line_t cache [ROW_CNT-1:0];

    state_e state_d, state_q;

    logic [DATA_WIDTH-1:0] rsp_data_d, rsp_data_q;
    logic [ADDR_WIDTH-1:0] req_addr_d, req_addr_q;
    logic [DATA_WIDTH-1:0] req_data_d, req_data_q;
    logic                  req_is_write_d, req_is_write_q;
    logic                  evict_aw_done_d, evict_aw_done_q;
    logic                  evict_w_done_d, evict_w_done_q;

    logic [TAG_WIDTH-1:0]        req_addr_tag;
    logic [INDEX_BITS-1:0]      req_addr_idx;
    logic [WORD_INDEX_WIDTH-1:0] req_word_idx;
    logic [TAG_WIDTH-1:0]        pending_addr_tag;
    logic [INDEX_BITS-1:0]      pending_addr_idx;
    logic [WORD_INDEX_WIDTH-1:0] pending_word_idx;
    logic [ADDR_WIDTH-1:0]       pending_line_addr;
    logic [ADDR_WIDTH-1:0]       victim_line_addr;

    logic                                      is_hit;
    logic                                      victim_is_dirty;
    logic                                      write_cache_flag;
    logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] write_cache_line;
    logic [INDEX_BITS-1:0]                    write_cache_idx;
    logic [TAG_WIDTH-1:0]                     write_cache_tag;
    logic                                      write_cache_dirty;

    always_comb begin
        state_d = state_q;
        rsp_data_d = rsp_data_q;
        req_addr_d = req_addr_q;
        req_data_d = req_data_q;
        req_is_write_d = req_is_write_q;
        evict_aw_done_d = evict_aw_done_q;
        evict_w_done_d = evict_w_done_q;

        {req_addr_tag, req_addr_idx, req_word_idx} = {
            TAG_WIDTH'(upstream.req_addr >> (OFFSET_WIDTH + INDEX_BITS)),
            INDEX_BITS'(upstream.req_addr >> OFFSET_WIDTH),
            WORD_INDEX_WIDTH'(upstream.req_addr >> BYTE_OFFSET_WIDTH)
        };

        {pending_addr_tag, pending_addr_idx, pending_word_idx} = {
            TAG_WIDTH'(req_addr_q >> (OFFSET_WIDTH + INDEX_BITS)),
            INDEX_BITS'(req_addr_q >> OFFSET_WIDTH),
            WORD_INDEX_WIDTH'(req_addr_q >> BYTE_OFFSET_WIDTH)
        };

        pending_line_addr = {
            pending_addr_tag,
            pending_addr_idx,
            {OFFSET_WIDTH{1'b0}}
        };
        victim_line_addr = {
            cache[pending_addr_idx].line_tag,
            pending_addr_idx,
            {OFFSET_WIDTH{1'b0}}
        };

        is_hit = cache[req_addr_idx].line_valid
            && cache[req_addr_idx].line_tag == req_addr_tag;
        victim_is_dirty = cache[req_addr_idx].line_valid
            && !is_hit
            && cache[req_addr_idx].line_dirty;

        write_cache_flag = 1'b0;
        write_cache_line = cache[req_addr_idx].line_data;
        write_cache_idx = req_addr_idx;
        write_cache_tag = req_addr_tag;
        write_cache_dirty = cache[req_addr_idx].line_dirty;

        upstream.req_rdy = 1'b0;
        upstream.rsp_val = 1'b0;
        upstream.rsp_data = rsp_data_q;

        m_axil_wr.awaddr = victim_line_addr;
        m_axil_wr.awprot = '0;
        m_axil_wr.awuser = '0;
        m_axil_wr.awvalid = 1'b0;
        m_axil_wr.wdata = cache[pending_addr_idx].line_data;
        m_axil_wr.wstrb = '1;
        m_axil_wr.wuser = '0;
        m_axil_wr.wvalid = 1'b0;
        m_axil_wr.bready = 1'b0;

        m_axil_rd.araddr = pending_line_addr;
        m_axil_rd.arprot = '0;
        m_axil_rd.aruser = '0;
        m_axil_rd.arvalid = 1'b0;
        m_axil_rd.rready = 1'b0;

        case (state_q)
            IDLE: begin
                upstream.req_rdy = 1'b1;

                if (upstream.req_val) begin
                    req_addr_d = ADDR_WIDTH'(upstream.req_addr);
                    req_data_d = DATA_WIDTH'(upstream.req_data);
                    req_is_write_d = upstream.req_rw_flag;

                    if (upstream.req_rw_flag) begin
                        rsp_data_d = '0;

                        if (victim_is_dirty) begin
                            evict_aw_done_d = 1'b0;
                            evict_w_done_d = 1'b0;
                            state_d = EVICT_SUBMIT;
                        end else begin
                            if (!is_hit) begin
                                write_cache_line = '0;
                            end
                            write_cache_line[req_word_idx] =
                                DATA_WIDTH'(upstream.req_data);
                            write_cache_dirty = 1'b1;
                            write_cache_flag = 1'b1;
                            state_d = RESP;
                        end
                    end else begin
                        if (is_hit) begin
                            rsp_data_d =
                                cache[req_addr_idx].line_data[req_word_idx];
                            state_d = RESP;
                        end else if (victim_is_dirty) begin
                            evict_aw_done_d = 1'b0;
                            evict_w_done_d = 1'b0;
                            state_d = EVICT_SUBMIT;
                        end else begin
                            state_d = MISS_SUBMIT;
                        end
                    end
                end
            end

            RESP: begin
                upstream.rsp_val = 1'b1;
                if (upstream.rsp_rdy) begin
                    state_d = IDLE;
                end
            end

            EVICT_SUBMIT: begin
                m_axil_wr.awvalid = !evict_aw_done_q;
                m_axil_wr.wvalid = !evict_w_done_q;

                if (!evict_aw_done_q && m_axil_wr.awready) begin
                    evict_aw_done_d = 1'b1;
                end
                if (!evict_w_done_q && m_axil_wr.wready) begin
                    evict_w_done_d = 1'b1;
                end

                if ((evict_aw_done_q || m_axil_wr.awready)
                        && (evict_w_done_q || m_axil_wr.wready)) begin
                    state_d = EVICT_WAIT;
                end
            end

            EVICT_WAIT: begin
                m_axil_wr.bready = 1'b1;

                if (m_axil_wr.bvalid) begin
                    evict_aw_done_d = 1'b0;
                    evict_w_done_d = 1'b0;

                    if (req_is_write_q) begin
                        write_cache_line = '0;
                        write_cache_line[pending_word_idx] = req_data_q;
                        write_cache_idx = pending_addr_idx;
                        write_cache_tag = pending_addr_tag;
                        write_cache_dirty = 1'b1;
                        write_cache_flag = 1'b1;
                        rsp_data_d = '0;
                        state_d = RESP;
                    end else begin
                        state_d = MISS_SUBMIT;
                    end
                end
            end

            MISS_SUBMIT: begin
                m_axil_rd.arvalid = 1'b1;
                if (m_axil_rd.arready) begin
                    state_d = MISS_WAIT;
                end
            end

            MISS_WAIT: begin
                m_axil_rd.rready = 1'b1;
                if (m_axil_rd.rvalid) begin
                    write_cache_line = LINE_WIDTH'(m_axil_rd.rdata);
                    write_cache_idx = pending_addr_idx;
                    write_cache_tag = pending_addr_tag;
                    write_cache_dirty = 1'b0;
                    write_cache_flag = 1'b1;
                    rsp_data_d = m_axil_rd.rdata[
                        pending_word_idx * DATA_WIDTH +: DATA_WIDTH
                    ];
                    state_d = RESP;
                end
            end

            default: begin
                state_d = IDLE;
                evict_aw_done_d = 1'b0;
                evict_w_done_d = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            rsp_data_q <= '0;
            req_addr_q <= '0;
            req_data_q <= '0;
            req_is_write_q <= 1'b0;
            evict_aw_done_q <= 1'b0;
            evict_w_done_q <= 1'b0;

            for (int unsigned i = 0; i < ROW_CNT; i++) begin
                cache[i].line_valid <= 1'b0;
                cache[i].line_dirty <= 1'b0;
            end
        end else begin
            state_q <= state_d;
            rsp_data_q <= rsp_data_d;
            req_addr_q <= req_addr_d;
            req_data_q <= req_data_d;
            req_is_write_q <= req_is_write_d;
            evict_aw_done_q <= evict_aw_done_d;
            evict_w_done_q <= evict_w_done_d;

            if (write_cache_flag) begin
                cache[write_cache_idx].line_valid <= 1'b1;
                cache[write_cache_idx].line_dirty <= write_cache_dirty;
                cache[write_cache_idx].line_tag <= write_cache_tag;
                cache[write_cache_idx].line_data <= write_cache_line;
            end
        end
    end

endmodule
/* verilator lint_on DECLFILENAME */
