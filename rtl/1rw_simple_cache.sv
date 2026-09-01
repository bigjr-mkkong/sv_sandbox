`timescale 1ns / 1ps

/*
 * Blocking, direct-mapped, write-back MESI cache.
 *
 * The synchronous upstream request interface transfers one DATA_WIDTH word.
 * The downstream AXI-Lite interface transfers one complete cache line. MESI
 * state is the sole source of validity and dirty information.
 */

/* verilator lint_off DECLFILENAME */
import config_pkg::*;

/*
 * Interface boundary for the cache-local snoop responder.
 *
 * The datapath, LLC request, and cache-commit connections are deliberately
 * exposed here so the responder can be implemented without restructuring the
 * cache. Until then it backpressures every incoming snoop request.
 */
module cache_coherency_bus_responder #(
    parameter int unsigned ADDR_WIDTH   = 64,
    parameter int unsigned LINE_WIDTH   = 512,
    parameter int unsigned OFFSET_WIDTH = 6,
    parameter int unsigned INDEX_BITS   = 8,
    parameter int unsigned TAG_WIDTH    = 50
) (
    input logic clk_i,
    input logic rst_ni,

    coh_bus2cache_req.if_sink bus2cache_req,

    input  logic                        idx_avail_i,
    output logic                        idx_in_use_o,
    output logic [INDEX_BITS-1:0]       active_idx_o,
    output logic [INDEX_BITS-1:0]       lookup_idx_o,//
    output logic [TAG_WIDTH-1:0]        lookup_tag_o,//
    input  logic                        lookup_hit_i,
    input  coh_state                    lookup_coh_i,
    input  logic [LINE_WIDTH-1:0]       lookup_data_i,

    output logic                        llc_req_val_o,
    input  logic                        llc_req_rdy_i,
    output logic                        llc_req_is_write_o,
    output logic [ADDR_WIDTH-1:0]       llc_req_addr_o,
    output logic [LINE_WIDTH-1:0]       llc_req_data_o,
    input  logic                        llc_rsp_val_i,
    input  logic [LINE_WIDTH-1:0]       llc_rsp_data_i,
    output logic                        llc_rsp_rdy_o,

    output logic                        commit_val_o,
    input  logic                        commit_rdy_i,
    output logic [INDEX_BITS-1:0]       commit_idx_o,
    output coh_state                    commit_coh_o
);
    assign lookup_idx_o = INDEX_BITS'(
        bus2cache_req.req_addr >> OFFSET_WIDTH
    );
    assign lookup_tag_o = TAG_WIDTH'(
        bus2cache_req.req_addr >> (OFFSET_WIDTH + INDEX_BITS)
    );

    assign bus2cache_req.req_rdy = 1'b0;
    assign bus2cache_req.rsp_val = 1'b0;
    assign bus2cache_req.rsp_shared = 1'b0;

    assign idx_in_use_o = 1'b0;
    assign active_idx_o = lookup_idx_o;
    assign llc_req_val_o = 1'b0;
    assign llc_req_is_write_o = 1'b1;
    assign llc_req_addr_o = '0;
    assign llc_req_data_o = '0;
    assign llc_rsp_rdy_o = 1'b0;
    assign commit_val_o = 1'b0;
    assign commit_idx_o = '0;
    assign commit_coh_o = COH_Invalid;

    wire _unused_ok = &{
        1'b0,
        clk_i,
        rst_ni,
        bus2cache_req.req_val,
        bus2cache_req.bus_op,
        bus2cache_req.rsp_rdy,
        idx_avail_i,
        lookup_hit_i,
        lookup_coh_i,
        lookup_data_i,
        llc_req_rdy_i,
        llc_rsp_val_i,
        llc_rsp_data_i,
        commit_rdy_i
    };

endmodule


/*
 * Top-level interface for a blocking, direct-mapped L1 cache.
 */
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
    parameter int unsigned DATA_PER_LINE  = 8,
    parameter int unsigned CACHE_ID       = 0
) (
    input logic clk_i,
    input logic rst_ni,

    // Word-wide request/response interface for an upstream requester, such as a CPU.
    upstream_if.if_sink upstream,

    // Line-wide AXI-Lite connection from this L1 cache to the downstream LLC.
    taxi_axil_if.wr_mst m_axil_wr,
    taxi_axil_if.rd_mst m_axil_rd,

    // Coherence request source and remote-snoop request sink.
    coh_cache2bus_req.if_src cache2bus_req,
    coh_bus2cache_req.if_sink bus2cache_req
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
        coh_state                                  coh;
        logic [TAG_WIDTH-1:0]                      line_tag;
        logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] line_data;
    } cache_line_t;

    typedef struct packed {
        logic                                      valid;
        logic [INDEX_BITS-1:0]                    index;
        coh_state                                  coh;
        logic                                      tag_we;
        logic [TAG_WIDTH-1:0]                     tag;
        logic                                      data_we;
        logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] data;
    } cache_commit_req_t;

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
    logic req_is_write_d, req_is_write_q;
    coh_state result_coh_d, result_coh_q;

    logic [ADDR_WIDTH-1:0] target_addr;
    logic [TAG_WIDTH-1:0] target_addr_tag;
    logic [INDEX_BITS-1:0] target_addr_idx;
    logic [WORD_INDEX_WIDTH-1:0] target_word_idx;
    logic [ADDR_WIDTH-1:0] target_line_addr;
    logic [ADDR_WIDTH-1:0] victim_line_addr;

    logic target_is_hit;
    logic victim_modified;
    coh_state target_coh;

    logic coh_req_val_i, coh_req_rdy_o;
    logic coh_rsp_rdy_i, coh_rsp_val_o;
    coh_state local_result_coh;

    logic main_llc_req_val;
    logic main_llc_req_rdy;
    logic main_llc_req_is_write;
    logic [ADDR_WIDTH-1:0] main_llc_req_addr;
    logic [LINE_WIDTH-1:0] main_llc_req_data;
    logic main_llc_rsp_val;
    logic main_llc_rsp_rdy;
    logic [LINE_WIDTH-1:0] main_llc_rsp_data;

    logic coh_llc_req_val;
    logic coh_llc_req_rdy;
    logic coh_llc_req_is_write;
    logic [ADDR_WIDTH-1:0] coh_llc_req_addr;
    logic [LINE_WIDTH-1:0] coh_llc_req_data;
    logic coh_llc_rsp_val;
    logic coh_llc_rsp_rdy;
    logic [LINE_WIDTH-1:0] coh_llc_rsp_data;

    cache_commit_req_t main_commit;
    cache_commit_req_t coh_commit;
    logic main_commit_rdy;
    logic coh_commit_rdy;
    logic cache_write_flag;
    logic [INDEX_BITS-1:0] cache_write_idx;
    coh_state cache_write_coh;
    logic cache_write_tag_we;
    logic [TAG_WIDTH-1:0] cache_write_tag;
    logic cache_write_data_we;
    logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] cache_write_data;

    logic snoop_idx_avail;
    logic snoop_idx_in_use;
    logic [INDEX_BITS-1:0] snoop_active_idx;
    logic [INDEX_BITS-1:0] snoop_lookup_idx;
    logic [TAG_WIDTH-1:0] snoop_lookup_tag;
    logic snoop_lookup_hit;
    coh_state snoop_lookup_coh;
    logic [LINE_WIDTH-1:0] snoop_lookup_data;
    logic main_idx_in_use;
    logic upstream_idx_avail;
    logic snoop_commit_val;
    logic [INDEX_BITS-1:0] snoop_commit_idx;
    coh_state snoop_commit_coh;

    assign cache2bus_req.req_src = $bits(cache2bus_req.req_src)'(CACHE_ID);

    /*
     * Resolve the MESI transition for the active upstream request. Requests
     * that require global coherence traffic are forwarded through the
     * cache-to-bus interface before the resulting local state is returned.
     */
    cache_coherency_local #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) coh_local_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .req_val_i(coh_req_val_i),
        .req_is_write_i(req_is_write_q),
        .req_is_hit_i(target_is_hit),
        .req_addr_i(target_line_addr),
        .req_coh_i(target_coh),
        .req_rdy_o(coh_req_rdy_o),
        .rsp_rdy_i(coh_rsp_rdy_i),
        .new_coh_state_o(local_result_coh),
        .rsp_val_o(coh_rsp_val_o),
        .coh_bus_req_rdy_i(cache2bus_req.req_rdy),
        .coh_bus_req_op_o(cache2bus_req.bus_op),
        .coh_bus_req_addr_o(cache2bus_req.req_addr),
        .coh_bus_req_val_o(cache2bus_req.req_val),
        .coh_bus_rsp_val_i(cache2bus_req.rsp_val),
        .coh_bus_shared_i(cache2bus_req.rsp_shared),
        .coh_bus_rsp_rdy_o(cache2bus_req.rsp_rdy)
    );

    /*
     * Respond to global BusRd, BusRdX, and BusUpgr snoops. The responder
     * looks up the addressed line and may leave it unchanged, change its MESI
     * state, or write a modified copy back to the LLC before changing state.
     * LLC writebacks are submitted through LLC_committer.
     */
    cache_coherency_bus_responder #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .OFFSET_WIDTH(OFFSET_WIDTH),
        .INDEX_BITS(INDEX_BITS),
        .TAG_WIDTH(TAG_WIDTH)
    ) coh_bus_responder_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .bus2cache_req(bus2cache_req),
        .idx_avail_i(snoop_idx_avail),
        .idx_in_use_o(snoop_idx_in_use),
        .active_idx_o(snoop_active_idx),
        .lookup_idx_o(snoop_lookup_idx),
        .lookup_tag_o(snoop_lookup_tag),
        .lookup_hit_i(snoop_lookup_hit),
        .lookup_coh_i(snoop_lookup_coh),
        .lookup_data_i(snoop_lookup_data),
        .llc_req_val_o(coh_llc_req_val),
        .llc_req_rdy_i(coh_llc_req_rdy),
        .llc_req_is_write_o(coh_llc_req_is_write),
        .llc_req_addr_o(coh_llc_req_addr),
        .llc_req_data_o(coh_llc_req_data),
        .llc_rsp_val_i(coh_llc_rsp_val),
        .llc_rsp_data_i(coh_llc_rsp_data),
        .llc_rsp_rdy_o(coh_llc_rsp_rdy),
        .commit_val_o(snoop_commit_val),
        .commit_rdy_i(coh_commit_rdy),
        .commit_idx_o(snoop_commit_idx),
        .commit_coh_o(snoop_commit_coh)
    );

    /*
     * Serialize the primary cache path and the snoop-responder path onto the
     * single line-wide LLC interface. A coherence request wins when both
     * sources are valid in the same arbitration cycle. The selected request
     * remains the sole owner until its response is accepted.
     */
    LLC_committer #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .LINE_WIDTH(LINE_WIDTH)
    ) llc_committer_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .coh_req_val_i(coh_llc_req_val),
        .coh_req_rdy_o(coh_llc_req_rdy),
        .coh_req_is_write_i(coh_llc_req_is_write),
        .coh_req_addr_i(coh_llc_req_addr),
        .coh_req_data_i(coh_llc_req_data),
        .coh_rsp_val_o(coh_llc_rsp_val),
        .coh_rsp_rdy_i(coh_llc_rsp_rdy),
        .coh_rsp_data_o(coh_llc_rsp_data),
        .cache_req_val_i(main_llc_req_val),
        .cache_req_rdy_o(main_llc_req_rdy),
        .cache_req_is_write_i(main_llc_req_is_write),
        .cache_req_addr_i(main_llc_req_addr),
        .cache_req_data_i(main_llc_req_data),
        .cache_rsp_val_o(main_llc_rsp_val),
        .cache_rsp_rdy_i(main_llc_rsp_rdy),
        .cache_rsp_data_o(main_llc_rsp_data),
        .m_axil_wr(m_axil_wr),
        .m_axil_rd(m_axil_rd)
    );

    always_comb begin
        target_addr = state_q == IDLE
            ? ADDR_WIDTH'(upstream.req_addr) : req_addr_q;
        {target_addr_tag, target_addr_idx, target_word_idx} = {
            TAG_WIDTH'(target_addr >> (OFFSET_WIDTH + INDEX_BITS)),
            INDEX_BITS'(target_addr >> OFFSET_WIDTH),
            WORD_INDEX_WIDTH'(target_addr >> BYTE_OFFSET_WIDTH)
        };

        target_line_addr = {
            target_addr_tag,
            target_addr_idx,
            {OFFSET_WIDTH{1'b0}}
        };
        victim_line_addr = {
            cache[target_addr_idx].line_tag,
            target_addr_idx,
            {OFFSET_WIDTH{1'b0}}
        };

        target_is_hit = cache[target_addr_idx].coh != COH_Invalid
            && cache[target_addr_idx].line_tag == target_addr_tag;
        victim_modified = !target_is_hit
            && cache[target_addr_idx].coh == COH_Modified;
        target_coh = target_is_hit
            ? cache[target_addr_idx].coh : COH_Invalid;

        snoop_lookup_hit = cache[snoop_lookup_idx].coh != COH_Invalid
            && cache[snoop_lookup_idx].line_tag == snoop_lookup_tag;
        snoop_lookup_coh = snoop_lookup_hit
            ? cache[snoop_lookup_idx].coh : COH_Invalid;
        snoop_lookup_data = cache[snoop_lookup_idx].line_data;

        main_idx_in_use = state_q inside {
            EVICT_SUBMIT,
            EVICT_WAIT,
            MISS_SUBMIT,
            MISS_WAIT
        } || (state_q == COH_WAIT && coh_rsp_val_o);
        snoop_idx_avail = !main_idx_in_use
            || snoop_lookup_idx != target_addr_idx;
        upstream_idx_avail = !snoop_idx_in_use
            || target_addr_idx != snoop_active_idx;
    end

    always_comb begin
        state_d = state_q;
        rsp_data_d = rsp_data_q;
        req_addr_d = req_addr_q;
        req_data_d = req_data_q;
        req_is_write_d = req_is_write_q;
        result_coh_d = result_coh_q;

        coh_req_val_i = 1'b0;
        coh_rsp_rdy_i = 1'b0;

        upstream.req_rdy = 1'b0;
        upstream.rsp_val = 1'b0;
        upstream.rsp_data = rsp_data_q;

        main_llc_req_val = 1'b0;
        main_llc_req_is_write = 1'b0;
        main_llc_req_addr = target_line_addr;
        main_llc_req_data = cache[target_addr_idx].line_data;
        main_llc_rsp_rdy = 1'b0;

        main_commit = '0;

        unique case (state_q)
            IDLE: begin
                upstream.req_rdy = upstream_idx_avail;
                if (upstream.req_val && upstream.req_rdy) begin
                    req_addr_d = ADDR_WIDTH'(upstream.req_addr);
                    req_data_d = DATA_WIDTH'(upstream.req_data);
                    req_is_write_d = upstream.req_rw_flag;

                    if (victim_modified) begin
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
                main_llc_req_val = 1'b1;
                main_llc_req_is_write = 1'b1;
                main_llc_req_addr = victim_line_addr;
                main_llc_req_data = cache[target_addr_idx].line_data;
                if (main_llc_req_rdy) begin
                    state_d = EVICT_WAIT;
                end
            end

            EVICT_WAIT: begin
                if (main_llc_rsp_val) begin
                    main_commit.valid = 1'b1;
                    main_commit.index = target_addr_idx;
                    main_commit.coh = COH_Invalid;
                    main_llc_rsp_rdy = main_commit_rdy;
                    if (main_commit_rdy) begin
                        state_d = COH_SUBMIT;
                    end
                end
            end

            COH_SUBMIT: begin
                coh_req_val_i = 1'b1;
                if (coh_req_rdy_o) begin
                    state_d = COH_WAIT;
                end
            end

            COH_WAIT: begin
                if (coh_rsp_val_o) begin
                    result_coh_d = local_result_coh;

                    if (!target_is_hit) begin
                        coh_rsp_rdy_i = 1'b1;
                        state_d = MISS_SUBMIT;
                    end else if (req_is_write_q) begin
                        main_commit.valid = 1'b1;
                        main_commit.index = target_addr_idx;
                        main_commit.coh = local_result_coh;
                        main_commit.data_we = 1'b1;
                        main_commit.data = cache[target_addr_idx].line_data;
                        main_commit.data[target_word_idx] = req_data_q;
                        coh_rsp_rdy_i = main_commit_rdy;
                        if (main_commit_rdy) begin
                            rsp_data_d = '0;
                            state_d = RESP;
                        end
                    end else begin
                        coh_rsp_rdy_i = 1'b1;
                        rsp_data_d = cache[target_addr_idx].line_data[
                            target_word_idx
                        ];
                        state_d = RESP;
                    end
                end
            end

            MISS_SUBMIT: begin
                main_llc_req_val = 1'b1;
                main_llc_req_addr = target_line_addr;
                if (main_llc_req_rdy) begin
                    state_d = MISS_WAIT;
                end
            end

            MISS_WAIT: begin
                if (main_llc_rsp_val) begin
                    main_commit.valid = 1'b1;
                    main_commit.index = target_addr_idx;
                    main_commit.coh = result_coh_q;
                    main_commit.tag_we = 1'b1;
                    main_commit.tag = target_addr_tag;
                    main_commit.data_we = 1'b1;
                    main_commit.data = main_llc_rsp_data;

                    if (req_is_write_q) begin
                        main_commit.data[target_word_idx] = req_data_q;
                    end

                    main_llc_rsp_rdy = main_commit_rdy;
                    if (main_commit_rdy) begin
                        rsp_data_d = req_is_write_q ? '0
                            : main_llc_rsp_data[
                                target_word_idx * DATA_WIDTH +: DATA_WIDTH
                            ];
                        state_d = RESP;
                    end
                end
            end

            default: begin
                state_d = IDLE;
            end
        endcase
    end

    always_comb begin
        coh_commit = '0;
        coh_commit.valid = snoop_commit_val;
        coh_commit.index = snoop_commit_idx;
        coh_commit.coh = snoop_commit_coh;

        main_commit_rdy = 1'b0;
        coh_commit_rdy = 1'b0;
        cache_write_flag = 1'b0;
        cache_write_idx = '0;
        cache_write_coh = COH_Invalid;
        cache_write_tag_we = 1'b0;
        cache_write_tag = '0;
        cache_write_data_we = 1'b0;
        cache_write_data = '0;

        if (coh_commit.valid) begin
            coh_commit_rdy = 1'b1;
            cache_write_flag = 1'b1;
            cache_write_idx = coh_commit.index;
            cache_write_coh = coh_commit.coh;
        end else if (main_commit.valid) begin
            main_commit_rdy = 1'b1;
            cache_write_flag = 1'b1;
            cache_write_idx = main_commit.index;
            cache_write_coh = main_commit.coh;
            cache_write_tag_we = main_commit.tag_we;
            cache_write_tag = main_commit.tag;
            cache_write_data_we = main_commit.data_we;
            cache_write_data = main_commit.data;
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            rsp_data_q <= '0;
            req_addr_q <= '0;
            req_data_q <= '0;
            req_is_write_q <= 1'b0;
            result_coh_q <= COH_Invalid;

            for (int unsigned i = 0; i < ROW_CNT; i++) begin
                cache[i].coh <= COH_Invalid;
            end
        end else begin
            state_q <= state_d;
            rsp_data_q <= rsp_data_d;
            req_addr_q <= req_addr_d;
            req_data_q <= req_data_d;
            req_is_write_q <= req_is_write_d;
            result_coh_q <= result_coh_d;

            if (cache_write_flag) begin
                cache[cache_write_idx].coh <= cache_write_coh;
                if (cache_write_tag_we) begin
                    cache[cache_write_idx].line_tag <= cache_write_tag;
                end
                if (cache_write_data_we) begin
                    cache[cache_write_idx].line_data <= cache_write_data;
                end
            end
        end
    end

endmodule

/*
 * Blocking owner and transaction manager for the shared, line-wide LLC port.
 * Coherence requests have priority whenever both producers are pending.
 */
{% do unit_test(
    module_name = "LLC_committer",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/LLC_committer_tb.py") %}
module LLC_committer #(
    parameter int unsigned ADDR_WIDTH = 64,
    parameter int unsigned LINE_WIDTH = 512
) (
    input logic clk_i,
    input logic rst_ni,

    input  logic                  coh_req_val_i,
    output logic                  coh_req_rdy_o,
    input  logic                  coh_req_is_write_i,
    input  logic [ADDR_WIDTH-1:0] coh_req_addr_i,
    input  logic [LINE_WIDTH-1:0] coh_req_data_i,
    output logic                  coh_rsp_val_o,
    input  logic                  coh_rsp_rdy_i,
    output logic [LINE_WIDTH-1:0] coh_rsp_data_o,

    input  logic                  cache_req_val_i,
    output logic                  cache_req_rdy_o,
    input  logic                  cache_req_is_write_i,
    input  logic [ADDR_WIDTH-1:0] cache_req_addr_i,
    input  logic [LINE_WIDTH-1:0] cache_req_data_i,
    output logic                  cache_rsp_val_o,
    input  logic                  cache_rsp_rdy_i,
    output logic [LINE_WIDTH-1:0] cache_rsp_data_o,

    taxi_axil_if.wr_mst m_axil_wr,
    taxi_axil_if.rd_mst m_axil_rd
);

    typedef enum logic [1:0] {
        COMMIT,
        SUBMIT,
        WAIT,
        RESP
    } state_e;

    typedef enum logic {
        OWNER_CACHE,
        OWNER_COH
    } owner_e;

    state_e state_d, state_q;
    owner_e owner_d, owner_q;
    logic req_is_write_d, req_is_write_q;
    logic [ADDR_WIDTH-1:0] req_addr_d, req_addr_q;
    logic [LINE_WIDTH-1:0] req_data_d, req_data_q;
    logic [LINE_WIDTH-1:0] rsp_data_d, rsp_data_q;
    logic aw_done_d, aw_done_q;
    logic w_done_d, w_done_q;

    always_comb begin
        state_d = state_q;
        owner_d = owner_q;
        req_is_write_d = req_is_write_q;
        req_addr_d = req_addr_q;
        req_data_d = req_data_q;
        rsp_data_d = rsp_data_q;
        aw_done_d = aw_done_q;
        w_done_d = w_done_q;

        coh_req_rdy_o = 1'b0;
        coh_rsp_val_o = 1'b0;
        coh_rsp_data_o = rsp_data_q;
        cache_req_rdy_o = 1'b0;
        cache_rsp_val_o = 1'b0;
        cache_rsp_data_o = rsp_data_q;

        m_axil_wr.awaddr = req_addr_q;
        m_axil_wr.awprot = '0;
        m_axil_wr.awuser = '0;
        m_axil_wr.awvalid = 1'b0;
        m_axil_wr.wdata = req_data_q;
        m_axil_wr.wstrb = '1;
        m_axil_wr.wuser = '0;
        m_axil_wr.wvalid = 1'b0;
        m_axil_wr.bready = 1'b0;

        m_axil_rd.araddr = req_addr_q;
        m_axil_rd.arprot = '0;
        m_axil_rd.aruser = '0;
        m_axil_rd.arvalid = 1'b0;
        m_axil_rd.rready = 1'b0;

        unique case (state_q)
            COMMIT: begin
                aw_done_d = 1'b0;
                w_done_d = 1'b0;

                // A producer owns a request only after valid && ready. Ready
                // may be combinational; valid and its payload must be held by
                // a losing producer until a later arbitration opportunity.
                coh_req_rdy_o = 1'b1;
                cache_req_rdy_o = !coh_req_val_i;

                if (coh_req_val_i && coh_req_rdy_o) begin
                    owner_d = OWNER_COH;
                    req_is_write_d = coh_req_is_write_i;
                    req_addr_d = coh_req_addr_i;
                    req_data_d = coh_req_data_i;
                    state_d = SUBMIT;
                end else if (cache_req_val_i && cache_req_rdy_o) begin
                    owner_d = OWNER_CACHE;
                    req_is_write_d = cache_req_is_write_i;
                    req_addr_d = cache_req_addr_i;
                    req_data_d = cache_req_data_i;
                    state_d = SUBMIT;
                end
            end

            SUBMIT: begin
                if (req_is_write_q) begin
                    m_axil_wr.awvalid = !aw_done_q;
                    m_axil_wr.wvalid = !w_done_q;

                    if (m_axil_wr.awvalid && m_axil_wr.awready) begin
                        aw_done_d = 1'b1;
                    end
                    if (m_axil_wr.wvalid && m_axil_wr.wready) begin
                        w_done_d = 1'b1;
                    end
                    if ((aw_done_q || m_axil_wr.awready)
                            && (w_done_q || m_axil_wr.wready)) begin
                        state_d = WAIT;
                    end
                end else begin
                    m_axil_rd.arvalid = 1'b1;
                    if (m_axil_rd.arready) begin
                        state_d = WAIT;
                    end
                end
            end

            WAIT: begin
                if (req_is_write_q) begin
                    m_axil_wr.bready = 1'b1;
                    if (m_axil_wr.bvalid) begin
                        rsp_data_d = '0;
                        state_d = RESP;
                    end
                end else begin
                    m_axil_rd.rready = 1'b1;
                    if (m_axil_rd.rvalid) begin
                        rsp_data_d = LINE_WIDTH'(m_axil_rd.rdata);
                        state_d = RESP;
                    end
                end
            end

            RESP: begin
                if (owner_q == OWNER_COH) begin
                    coh_rsp_val_o = 1'b1;
                    if (coh_rsp_rdy_i) begin
                        state_d = COMMIT;
                    end
                end else begin
                    cache_rsp_val_o = 1'b1;
                    if (cache_rsp_rdy_i) begin
                        state_d = COMMIT;
                    end
                end
            end

            default: begin
                state_d = COMMIT;
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state_q <= COMMIT;
            owner_q <= OWNER_CACHE;
            req_is_write_q <= 1'b0;
            req_addr_q <= '0;
            req_data_q <= '0;
            rsp_data_q <= '0;
            aw_done_q <= 1'b0;
            w_done_q <= 1'b0;
        end else begin
            state_q <= state_d;
            owner_q <= owner_d;
            req_is_write_q <= req_is_write_d;
            req_addr_q <= req_addr_d;
            req_data_q <= req_data_d;
            rsp_data_q <= rsp_data_d;
            aw_done_q <= aw_done_d;
            w_done_q <= w_done_d;
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk_i) begin
        if (rst_ni && m_axil_rd.rvalid && m_axil_rd.rready) begin
            assert (m_axil_rd.rresp == 2'b00)
                else $error("LLC read returned a non-OKAY AXI response");
        end
        if (rst_ni && m_axil_wr.bvalid && m_axil_wr.bready) begin
            assert (m_axil_wr.bresp == 2'b00)
                else $error("LLC write returned a non-OKAY AXI response");
        end
    end
`endif

endmodule
/* verilator lint_on DECLFILENAME */
