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
 * Top-level interface for a blocking, direct-mapped L1 cache.
 */
{% do unit_test(
    module_name = "simple_cache_1rw",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/1rw_simple_cache_tb.py",
    rtl_dependencies = [
        "MESI_protocol.sv",
        "cache_coherency.sv",
        "cache_bank.sv",
        "cache_committer.sv",
        "cache_coherency_bus_responder.sv",
        "LLC_committer.sv"
    ]) %}
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

    typedef enum logic [3:0] {
        IDLE,
        LOOKUP_SUBMIT,
        LOOKUP_WAIT,
        RESP,
        COH_SUBMIT,
        COH_WAIT,
        MISS_SUBMIT,
        MISS_WAIT,
        EVICT_SUBMIT,
        EVICT_WAIT
    } state_e;

    state_e state_d, state_q;
    logic [DATA_WIDTH-1:0] rsp_data_d, rsp_data_q;
    logic [ADDR_WIDTH-1:0] req_addr_d, req_addr_q;
    logic [DATA_WIDTH-1:0] req_data_d, req_data_q;
    logic req_is_write_d, req_is_write_q;
    coh_state result_coh_d, result_coh_q;

    /*
     * Cache COH serialization switch flag. A state-changing snoop accepted
     * while a local coherence decision is in flight makes that decision stale.
     * Hold the flag until the stale response is consumed, then retry the same
     * upstream request from the cacheline state left by the snoop.
     */
    logic coh_serialization_switch_q;
    logic local_req_legal;

    logic [ADDR_WIDTH-1:0] target_addr;
    logic [TAG_WIDTH-1:0] target_addr_tag;
    logic [INDEX_BITS-1:0] target_addr_idx;
    logic [ADDR_WIDTH-1:0] target_line_addr;
    logic [ADDR_WIDTH-1:0] victim_line_addr;

    logic target_is_hit;
    // logic victim_modified;
    coh_state target_coh;

    logic coh_req_val_i, coh_req_rdy_o;
    logic coh_rsp_rdy_i, coh_rsp_val_o;
    logic local_coh_commit;
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

    cache_commit_if #(
        .INDEX_BITS(INDEX_BITS),
        .TAG_WIDTH(TAG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) remote_commit();

    cache_commit_if #(
        .INDEX_BITS(INDEX_BITS),
        .TAG_WIDTH(TAG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) main_commit();

    cache_snoop_if #(
        .INDEX_BITS(INDEX_BITS),
        .TAG_WIDTH(TAG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) remote_snoop();

    cache_snoop_if #(
        .INDEX_BITS(INDEX_BITS),
        .TAG_WIDTH(TAG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) main_snoop();

    logic main_lookup_result_hit_d, main_lookup_result_hit_q;
    logic [TAG_WIDTH-1:0]
        main_lookup_result_tag_d, main_lookup_result_tag_q;
    logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0]
        main_lookup_result_data_d, main_lookup_result_data_q;
    coh_state main_live_coh;
    logic cache_reset_fin;

    logic responder_idx_avail;
    logic snoop_idx_in_use;
    logic [INDEX_BITS-1:0] snoop_active_idx;
    logic [INDEX_BITS-1:0] incoming_snoop_idx;
    logic main_idx_in_use;
    logic upstream_idx_avail;
    logic snoop_req_handshake;
    logic same_idx_snoop_accepting;
    logic same_idx_snoop_active;
    logic remote_commit_fire;
    logic remote_commit_changes_target_idx;
    logic local_commit_unblocked;

    //I gave it 4bits to keep CACHE_ID, shoule be enough
    assign cache2bus_req.req_src = CACHE_ID;
    assign incoming_snoop_idx = INDEX_BITS'(
        bus2cache_req.req_addr >> OFFSET_WIDTH
    );
    assign snoop_req_handshake = bus2cache_req.req_val
        && bus2cache_req.req_rdy;
    assign same_idx_snoop_accepting = snoop_req_handshake
        && incoming_snoop_idx == target_addr_idx;
    assign same_idx_snoop_active = snoop_idx_in_use
        && snoop_active_idx == target_addr_idx;
    assign remote_commit_fire = remote_commit.val && remote_commit.rdy;
    assign remote_commit_changes_target_idx = remote_commit_fire
        && remote_commit.index == target_addr_idx;
    assign local_req_legal = !coh_serialization_switch_q
        && !remote_commit_changes_target_idx;
    assign local_commit_unblocked = !same_idx_snoop_accepting
        && !same_idx_snoop_active;

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
        .local_coh_commit_o(local_coh_commit),
        .coh_bus_req_rdy_i(cache2bus_req.req_rdy),
        .coh_bus_req_op_o(cache2bus_req.bus_op),
        .coh_bus_req_addr_o(cache2bus_req.req_addr),
        .coh_bus_req_val_o(cache2bus_req.req_val),
        .coh_bus_rsp_val_i(cache2bus_req.rsp_val),
        .coh_bus_shared_i(cache2bus_req.rsp_shared),
        .coh_bus_rsp_rdy_o(cache2bus_req.rsp_rdy)
    );

    /*
     * Respond to global BusRd, BusRdX, and BusUpgr snoops. BusRd maps valid
     * copies to Shared and flushes only Modified data. BusRdX flushes before
     * invalidating; BusUpgr invalidates without a flush. LLC flushes share
     * LLC_committer with the primary cache path.
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
        .idx_avail_i(responder_idx_avail),
        .idx_in_use_o(snoop_idx_in_use),
        .active_idx_o(snoop_active_idx),
        .remote_snoop(remote_snoop),
        .llc_req_val_o(coh_llc_req_val),
        .llc_req_rdy_i(coh_llc_req_rdy),
        .llc_req_is_write_o(coh_llc_req_is_write),
        .llc_req_addr_o(coh_llc_req_addr),
        .llc_req_data_o(coh_llc_req_data),
        .llc_rsp_val_i(coh_llc_rsp_val),
        .llc_rsp_rdy_o(coh_llc_rsp_rdy),
        .remote_commit(remote_commit)
    );

    /*
     * Own the cache storage and serialize all tag/data accesses. A write-ready
     * handshake is the physical update edge. Synchronous reads are held until
     * their selected consumer accepts the response.
     */
    cache_committer #(
        .ROW_CNT(ROW_CNT),
        .INDEX_BITS(INDEX_BITS),
        .TAG_WIDTH(TAG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) cache_committer_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .reset_fin_o(cache_reset_fin),
        .coh_probe_idx_i(target_addr_idx),
        .coh_probe_o(main_live_coh),
        .remote_commit(remote_commit),
        .main_commit(main_commit),
        .remote_snoop(remote_snoop),
        .main_snoop(main_snoop)
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
        .coh_rsp_data_o(),
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
        {target_addr_tag, target_addr_idx} = {
            TAG_WIDTH'(target_addr >> (OFFSET_WIDTH + INDEX_BITS)),
            INDEX_BITS'(target_addr >> OFFSET_WIDTH)
        };

        target_line_addr = {
            target_addr_tag,
            target_addr_idx,
            {OFFSET_WIDTH{1'b0}}
        };
    end

    always_comb begin
        victim_line_addr = {
            main_lookup_result_tag_q,
            target_addr_idx,
            {OFFSET_WIDTH{1'b0}}
        };

        target_is_hit = main_lookup_result_hit_q
            && main_live_coh != COH_Invalid;
        // LOOKUP_WAIT decides eviction before the current response is latched.
        // victim_modified = !main_snoop.rsp_hit
        //     && main_snoop.rsp_coh == COH_Modified;
        target_coh = target_is_hit ? main_live_coh : COH_Invalid;

        main_idx_in_use = state_q inside {
            EVICT_SUBMIT,
            EVICT_WAIT,
            MISS_SUBMIT,
            MISS_WAIT
        };
        responder_idx_avail = cache_reset_fin && (!main_idx_in_use
            || incoming_snoop_idx != target_addr_idx);
        upstream_idx_avail = (
            !snoop_idx_in_use || target_addr_idx != snoop_active_idx
        ) && !(
            bus2cache_req.req_val
            && responder_idx_avail
            && target_addr_idx == incoming_snoop_idx
        );
    end

    // A refill always writes the latched request's tag. tag_we gates its use.
    assign main_commit.tag = req_addr_q[OFFSET_WIDTH + INDEX_BITS +: TAG_WIDTH];

    // Prepare write data independently of coherence/arbitration readiness.
    // Only val && rdy && data_we writes data; the payload is unused otherwise.
    always_comb begin
        main_commit.data = state_q == MISS_WAIT
            ? main_llc_rsp_data : main_lookup_result_data_q;
        if (req_is_write_q) begin
            main_commit.data[
                req_addr_q[BYTE_OFFSET_WIDTH +: WORD_INDEX_WIDTH]
            ] = req_data_q;
        end
    end

    // Prepare the response before its completion conditions are resolved.
    // Only the source, latched word offset and request type affect the data.
    // RESP freezes rsp_data_q below, including while upstream is stalled.
    always_comb begin
        rsp_data_d = state_q == MISS_WAIT
            ? main_llc_rsp_data[
                req_addr_q[BYTE_OFFSET_WIDTH +: WORD_INDEX_WIDTH]
                    * DATA_WIDTH +: DATA_WIDTH
            ]
            : main_lookup_result_data_q[
                req_addr_q[BYTE_OFFSET_WIDTH +: WORD_INDEX_WIDTH]
            ];
        if (req_is_write_q) begin
            rsp_data_d = '0;
        end
    end

    always_comb begin
        state_d = state_q;
        req_addr_d = req_addr_q;
        req_data_d = req_data_q;
        req_is_write_d = req_is_write_q;
        result_coh_d = result_coh_q;
        main_lookup_result_hit_d = main_lookup_result_hit_q;
        main_lookup_result_tag_d = main_lookup_result_tag_q;
        main_lookup_result_data_d = main_lookup_result_data_q;
        coh_req_val_i = 1'b0;
        coh_rsp_rdy_i = 1'b0;

        main_snoop.req_val = 1'b0;
        main_snoop.idx = target_addr_idx;
        main_snoop.tag = target_addr_tag;
        main_snoop.rsp_rdy = 1'b0;

        upstream.req_rdy = 1'b0;
        upstream.rsp_val = 1'b0;
        upstream.rsp_data = rsp_data_q;

        main_llc_req_val = 1'b0;
        main_llc_req_is_write = 1'b0;
        main_llc_req_addr = target_line_addr;
        main_llc_req_data = main_lookup_result_data_q;
        main_llc_rsp_rdy = 1'b0;

        main_commit.val = 1'b0;
        main_commit.index = '0;
        main_commit.coh = COH_Invalid;
        main_commit.tag_we = 1'b0;
        main_commit.data_we = 1'b0;

        unique case (state_q)
            IDLE: begin
                upstream.req_rdy = cache_reset_fin && upstream_idx_avail;
                if (upstream.req_val && upstream.req_rdy) begin
                    req_addr_d = ADDR_WIDTH'(upstream.req_addr);
                    req_data_d = DATA_WIDTH'(upstream.req_data);
                    req_is_write_d = upstream.req_rw_flag;

                    main_snoop.req_val = upstream_idx_avail;
                    state_d = (main_snoop.req_val && main_snoop.req_rdy)?LOOKUP_WAIT:LOOKUP_SUBMIT;
                end
            end

            LOOKUP_SUBMIT: begin
                main_snoop.req_val = upstream_idx_avail;
                if (main_snoop.req_val && main_snoop.req_rdy) begin
                    state_d = LOOKUP_WAIT;
                end
            end

            LOOKUP_WAIT: begin
                main_snoop.rsp_rdy = 1'b1;
                if (main_snoop.rsp_val) begin
                    main_lookup_result_hit_d = main_snoop.rsp_hit;
                    main_lookup_result_tag_d = main_snoop.rsp_tag;
                    main_lookup_result_data_d = main_snoop.rsp_data;
                    if (!main_snoop.rsp_hit && main_snoop.rsp_coh == COH_Modified) begin //if victim has been modified
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
                main_llc_req_data = main_lookup_result_data_q;
                if (main_llc_req_rdy) begin
                    state_d = EVICT_WAIT;
                end
            end

            EVICT_WAIT: begin
                if (main_llc_rsp_val) begin
                    main_commit.val = 1'b1;
                    main_commit.index = target_addr_idx;
                    main_commit.coh = COH_Invalid;
                    main_llc_rsp_rdy = main_commit.rdy;
                    if (main_commit.rdy) begin
                        state_d = COH_SUBMIT;
                    end
                end
            end

            COH_SUBMIT, COH_WAIT: begin
                if (state_q == COH_SUBMIT) begin
                    // A retry waits for the conflicting snoop to release
                    // the index and make its coherence update visible.
                    coh_req_val_i = upstream_idx_avail;
                    if (coh_req_val_i && coh_req_rdy_o) begin
                        state_d = COH_WAIT;
                    end
                end

                // BusNOP can return a completed decision on the request
                // edge. Both paths use the same snoop and commit guards.
                if ((state_q == COH_WAIT
                        || (coh_req_val_i && coh_req_rdy_o))
                        && coh_rsp_val_o && local_commit_unblocked) begin
                    if (!local_req_legal) begin
                        /*
                         * The cache COH serialization switch discards this
                         * stale decision. Consuming the response resets the
                         * local controller before the request is resubmitted.
                         */
                        coh_rsp_rdy_i = 1'b1;
                        state_d = COH_SUBMIT;
                    end else if (!target_is_hit) begin
                        result_coh_d = local_result_coh;
                        coh_rsp_rdy_i = 1'b1;
                        state_d = MISS_SUBMIT;
                    end else if (req_is_write_q) begin
                        result_coh_d = local_result_coh;
                        main_commit.val = 1'b1;
                        main_commit.index = target_addr_idx;
                        main_commit.coh = local_result_coh;
                        main_commit.data_we = 1'b1;
                        coh_rsp_rdy_i = main_commit.rdy;
                        if (main_commit.rdy) begin
                            state_d = RESP;
                        end
                    end else if (local_coh_commit) begin
                        result_coh_d = local_result_coh;
                        main_commit.val = 1'b1;
                        main_commit.index = target_addr_idx;
                        main_commit.coh = local_result_coh;
                        coh_rsp_rdy_i = main_commit.rdy;
                        if (main_commit.rdy) begin
                            state_d = RESP;
                        end
                    end else begin
                        result_coh_d = local_result_coh;
                        coh_rsp_rdy_i = 1'b1;
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
                    main_commit.val = 1'b1;
                    main_commit.index = target_addr_idx;
                    main_commit.coh = result_coh_q;
                    main_commit.tag_we = 1'b1;
                    main_commit.data_we = 1'b1;

                    main_llc_rsp_rdy = main_commit.rdy;
                    if (main_commit.rdy) begin
                        state_d = RESP;
                    end
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
            req_addr_q <= '0;
            req_data_q <= '0;
            req_is_write_q <= 1'b0;
            result_coh_q <= COH_Invalid;
            main_lookup_result_hit_q <= 1'b0;
            main_lookup_result_tag_q <= '0;
            main_lookup_result_data_q <= '0;
            coh_serialization_switch_q <= 1'b0;

        end else begin
            state_q <= state_d;
            if (state_q != RESP) begin
                rsp_data_q <= rsp_data_d;
            end
            req_addr_q <= req_addr_d;
            req_data_q <= req_data_d;
            req_is_write_q <= req_is_write_d;
            result_coh_q <= result_coh_d;
            main_lookup_result_hit_q <= main_lookup_result_hit_d;
            main_lookup_result_tag_q <= main_lookup_result_tag_d;
            main_lookup_result_data_q <= main_lookup_result_data_d;
            /*
             * Latch the cache COH serialization switch only at a completed
             * snoop handshake. Keeping this update sequential avoids a ready
             * path from feeding back through the shared LLC arbitration.
             */
            if (state_q == IDLE) begin
                coh_serialization_switch_q <= 1'b0;
            end else if (state_q == COH_WAIT
                         && remote_commit_changes_target_idx) begin
                coh_serialization_switch_q <= 1'b1;
            end else if (state_q == COH_WAIT
                         && coh_rsp_val_o
                         && coh_rsp_rdy_i
                         && coh_serialization_switch_q) begin
                coh_serialization_switch_q <= 1'b0;
            end
        end
    end

{% if not RENDER_OPTION.SYNTH %}
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        main_commit.val |-> local_req_legal
    ) else $error("an invalidated local coherence result reached the cache bank");
{% endif %}

endmodule
/* verilator lint_on DECLFILENAME */
