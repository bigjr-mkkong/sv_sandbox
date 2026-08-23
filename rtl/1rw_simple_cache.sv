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
import config_pkg::*;

{% do unit_test(
    module_name = "simple_cache_1rw",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/1rw_simple_cache_tb.py",
    rtl_dependencies = ["MESI_protocol.sv", "cache_coherency.sv"]) %}
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
    taxi_axil_if.rd_mst m_axil_rd,

    // Coherency bus
    input logic coh_bus_req_rdy_i,
    output coh_bus_op coh_bus_req_op_o,
    output logic [ADDR_WIDTH-1:0] coh_bus_req_addr_o,
    output logic coh_bus_req_val_o,

    input logic coh_bus_rsp_val_i,
    input logic coh_bus_shared_i,
    output logic coh_bus_rsp_rdy_o
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
        coh_state                                   coh;
        logic [TAG_WIDTH-1:0]                      line_tag;
        logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] line_data;
    } cache_line_t;

    typedef enum logic [2:0] {
        IDLE,
        RESP,
        COH_SUBMIT,
        COH_WAIT,
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
    logic                  req_is_hit_d, req_is_hit_q;
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
    coh_state                                 write_cache_coh;

    coh_state target_coh_d, target_coh_q;
    coh_state result_coh_d, result_coh_q;
    coh_state local_result_coh;
    logic coh_req_val_i, coh_req_rdy_o;
    logic coh_rsp_rdy_i, coh_rsp_val_o;

    cache_coherency_local #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) coh_local_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        // Cache-side blocking request/response interface.
        .req_val_i(coh_req_val_i),
        .req_is_write_i(req_is_write_q),
        .req_is_hit_i(req_is_hit_q),
        .req_addr_i(pending_line_addr),
        .req_coh_i(target_coh_q),
        .req_rdy_o(coh_req_rdy_o),

        .rsp_rdy_i(coh_rsp_rdy_i),
        .new_coh_state_o(local_result_coh),
        .rsp_val_o(coh_rsp_val_o),

        // Coherence-bus-controller blocking request/response interface.
        .coh_bus_req_rdy_i(coh_bus_req_rdy_i),
        .coh_bus_req_op_o(coh_bus_req_op_o),
        .coh_bus_req_addr_o(coh_bus_req_addr_o),
        .coh_bus_req_val_o(coh_bus_req_val_o),

        .coh_bus_rsp_val_i(coh_bus_rsp_val_i),
        .coh_bus_shared_i(coh_bus_shared_i),
        .coh_bus_rsp_rdy_o(coh_bus_rsp_rdy_o)
    );

    always_comb begin
        state_d = state_q;
        rsp_data_d = rsp_data_q;
        req_addr_d = req_addr_q;
        req_data_d = req_data_q;
        req_is_write_d = req_is_write_q;
        req_is_hit_d = req_is_hit_q;
        evict_aw_done_d = evict_aw_done_q;
        evict_w_done_d = evict_w_done_q;
        target_coh_d = target_coh_q;
        result_coh_d = result_coh_q;

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
            && cache[req_addr_idx].line_tag == req_addr_tag
            && cache[req_addr_idx].coh != COH_Invalid;
        victim_is_dirty = cache[req_addr_idx].line_valid
            && !is_hit
            && cache[req_addr_idx].line_dirty;

        write_cache_flag = 1'b0;
        write_cache_line = cache[req_addr_idx].line_data;
        write_cache_idx = req_addr_idx;
        write_cache_tag = req_addr_tag;
        write_cache_dirty = cache[req_addr_idx].line_dirty;
        write_cache_coh = cache[req_addr_idx].coh;

        coh_req_val_i = 1'b0;
        coh_rsp_rdy_i = 1'b0;

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
                    req_is_hit_d = is_hit;
                    target_coh_d = is_hit?cache[req_addr_idx].coh:COH_Invalid;

                    if (victim_is_dirty) begin
                        evict_aw_done_d = 1'b0;
                        evict_w_done_d = 1'b0;
                        state_d = EVICT_SUBMIT;
                    end else begin
                        state_d = COH_SUBMIT;
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
                    state_d = COH_SUBMIT;
                end
            end

            COH_SUBMIT: begin
                coh_req_val_i = 1'b1;
                if (coh_req_rdy_o) begin
                    state_d = COH_WAIT;
                end
            end

            COH_WAIT: begin
                coh_rsp_rdy_i = 1'b1;
                if (coh_rsp_val_o) begin
                    result_coh_d = local_result_coh;

                    if (req_is_hit_q) begin
                        if (req_is_write_q) begin
                            write_cache_line = cache[pending_addr_idx].line_data;
                            write_cache_line[pending_word_idx] = req_data_q;
                            write_cache_idx = pending_addr_idx;
                            write_cache_tag = pending_addr_tag;
                            write_cache_dirty = 1'b1;
                            write_cache_coh = local_result_coh;
                            write_cache_flag = 1'b1;
                            rsp_data_d = '0;
                        end else begin
                            rsp_data_d = cache[pending_addr_idx].line_data[
                                pending_word_idx
                            ];
                        end
                        state_d = RESP;
                    end else if (req_is_write_q) begin
                        write_cache_line = '0;
                        write_cache_line[pending_word_idx] = req_data_q;
                        write_cache_idx = pending_addr_idx;
                        write_cache_tag = pending_addr_tag;
                        write_cache_dirty = 1'b1;
                        write_cache_coh = local_result_coh;
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
                    write_cache_coh = result_coh_q;
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
            req_is_hit_q <= 1'b0;
            evict_aw_done_q <= 1'b0;
            evict_w_done_q <= 1'b0;
            target_coh_q <= COH_Invalid;
            result_coh_q <= COH_Invalid;

            for (int unsigned i = 0; i < ROW_CNT; i++) begin
                cache[i].line_valid <= 1'b0;
                cache[i].line_dirty <= 1'b0;
                cache[i].coh <= COH_Invalid;
            end
        end else begin
            state_q <= state_d;
            rsp_data_q <= rsp_data_d;
            req_addr_q <= req_addr_d;
            req_data_q <= req_data_d;
            req_is_write_q <= req_is_write_d;
            req_is_hit_q <= req_is_hit_d;
            evict_aw_done_q <= evict_aw_done_d;
            evict_w_done_q <= evict_w_done_d;
            target_coh_q <= target_coh_d;
            result_coh_q <= result_coh_d;

            if (write_cache_flag) begin
                cache[write_cache_idx].line_valid <= 1'b1;
                cache[write_cache_idx].line_dirty <= write_cache_dirty;
                cache[write_cache_idx].coh <= write_cache_coh;
                cache[write_cache_idx].line_tag <= write_cache_tag;
                cache[write_cache_idx].line_data <= write_cache_line;
            end
        end
    end

endmodule
/* verilator lint_on DECLFILENAME */
