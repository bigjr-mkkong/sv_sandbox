`timescale 1ns / 1ps

import config_pkg::*;
/* verilator lint_off DECLFILENAME */
{% do unit_test(
    module_name = "cache_coherency_local",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/cache_coherency_local_tb.py",
    rtl_dependencies = ["MESI_protocol.sv"]) %}
module cache_coherency_local #(
    parameter int unsigned ADDR_WIDTH = 64
) (
    input logic clk_i,
    input logic rst_ni,

    // Cache-side blocking request/response interface.
    input logic req_val_i,
    input logic req_is_write_i,
    input logic req_is_hit_i,
    input logic [ADDR_WIDTH-1:0] req_addr_i,
    input coh_state req_coh_i,
    output logic req_rdy_o,

    input logic rsp_rdy_i,
    output coh_state new_coh_state_o,
    output logic rsp_val_o,

    // Coherence-bus-controller blocking request/response interface.
    input logic coh_bus_req_rdy_i,
    output coh_bus_op coh_bus_req_op_o,
    output logic [ADDR_WIDTH-1:0] coh_bus_req_addr_o,
    output logic coh_bus_req_val_o,

    input logic coh_bus_rsp_val_i,
    input logic coh_bus_shared_i,
    output logic coh_bus_rsp_rdy_o
);


    typedef enum logic [1:0] {
        IDLE,
        RESP,
        BUS_SUBMIT,
        BUS_WAIT
    } state_e;

    state_e state_d, state_q;

    logic [ADDR_WIDTH-1:0] req_addr_d, req_addr_q;
    logic req_is_write_d, req_is_write_q;
    coh_state ret_coh_d, ret_coh_q;
    coh_state candidate_coh_d[2], candidate_coh_q[2];

    logic begin_mesi_judge;
    logic judged_is_write;
    coh_state effective_coh;
    coh_state judged_coh[2];
    coh_bus_op judged_bus_op;

    /*
     * Evaluate the MESI transition when the local request is accepted, then
     * reevaluate it in BUS_SUBMIT from the cache line's current state. The
     * second evaluation matters when an earlier snoop changes the line before
     * this request wins the shared bus.
     *
     * For example, two caches may hold the same line in S, and assume both
     * accept a word write. Each initially selects BusUpgr. If cache0 wins
     * first, its snoop invalidates cache1. Cache1 must then reevaluate its
     * pending write as Invalid-to-Modified and issue BusRdX, rather than send
     * the stale BusUpgr and apply a partial write to stale data. Capture the
     * candidate next states only when the reevaluated bus request is accepted.
     */
    assign begin_mesi_judge = (state_q == IDLE && req_val_i)
        || state_q == BUS_SUBMIT;
    assign judged_is_write = state_q == IDLE
        ? req_is_write_i : req_is_write_q;
    assign effective_coh = req_is_hit_i ? req_coh_i : COH_Invalid;

    MESI_judger mesi_judger_inst (
        .begin_judge(begin_mesi_judge),
        .req_is_write_i(judged_is_write),
        .current_coh_i(effective_coh),
        .next_coh_o(judged_coh),
        .coh_bus_op_o(judged_bus_op)
    );

    always_comb begin
        state_d = state_q;
        req_addr_d = req_addr_q;
        req_is_write_d = req_is_write_q;
        ret_coh_d = ret_coh_q;
        candidate_coh_d[0] = candidate_coh_q[0];
        candidate_coh_d[1] = candidate_coh_q[1];

        req_rdy_o = 1'b0;
        rsp_val_o = 1'b0;
        new_coh_state_o = ret_coh_q;

        coh_bus_req_val_o = 1'b0;
        coh_bus_req_op_o = BusNOP;
        coh_bus_req_addr_o = req_addr_q;
        coh_bus_rsp_rdy_o = 1'b0;

        unique case (state_q)
            IDLE: begin
                req_rdy_o = 1'b1;

                if (req_val_i) begin
                    req_addr_d = req_addr_i;
                    req_is_write_d = req_is_write_i;

                    if (judged_bus_op == BusNOP) begin
                        ret_coh_d = judged_coh[0];
                        state_d = RESP;
                    end else begin
                        state_d = BUS_SUBMIT;
                    end
                end
            end

            BUS_SUBMIT: begin
                coh_bus_req_val_o = 1'b1;
                coh_bus_req_op_o = judged_bus_op;

                if (coh_bus_req_rdy_i) begin
                    candidate_coh_d[0] = judged_coh[0];
                    candidate_coh_d[1] = judged_coh[1];
                    state_d = BUS_WAIT;
                end
            end

            BUS_WAIT: begin
                coh_bus_rsp_rdy_o = 1'b1;

                if (coh_bus_rsp_val_i) begin
                    ret_coh_d = candidate_coh_q[coh_bus_shared_i];
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
            req_addr_q <= '0;
            req_is_write_q <= 1'b0;
            ret_coh_q <= COH_Invalid;
            candidate_coh_q[0] <= COH_Invalid;
            candidate_coh_q[1] <= COH_Invalid;
        end else begin
            state_q <= state_d;
            req_addr_q <= req_addr_d;
            req_is_write_q <= req_is_write_d;
            ret_coh_q <= ret_coh_d;
            candidate_coh_q[0] <= candidate_coh_d[0];
            candidate_coh_q[1] <= candidate_coh_d[1];
        end
    end

endmodule

/* Broadcast one arbitrated coherence request and collect all snoop replies. */
{% do unit_test(
    module_name = "cache_coherency_global",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/cache_coherency_global_tb.py") %}

module cache_coherency_global #(
    parameter int unsigned L1_CACHE_CNT = 2,
    parameter int unsigned ADDR_WIDTH = config_pkg::ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = config_pkg::DATA_WIDTH
) (
    input logic clk_i,
    input logic rst_ni,
    coh_cache2bus_req.if_sink cache_req,

    coh_bus2cache_req.if_src bus_op[L1_CACHE_CNT]
);

    localparam int unsigned CACHE_IDX_WIDTH = $clog2(L1_CACHE_CNT);

    typedef enum logic [1:0] {
        IDLE,
        SCATTER,
        SCATTER_WAIT,
        RESP
    } state_e;

    state_e state_d, state_q;
    config_pkg::coh_bus_op bus_op_d, bus_op_q;
    logic [ADDR_WIDTH-1:0] req_addr_d, req_addr_q;
    logic [CACHE_IDX_WIDTH-1:0] requester_idx_d, requester_idx_q;
    logic [L1_CACHE_CNT-1:0] broadcast_accepted_d, broadcast_accepted_q;
    logic [L1_CACHE_CNT-1:0] reply_received_d, reply_received_q;
    logic synth_shared_d, synth_shared_q;

    logic [L1_CACHE_CNT-1:0] requester_mask;
    logic [L1_CACHE_CNT-1:0] bus_req_val;
    logic [L1_CACHE_CNT-1:0] bus_req_rdy;
    logic [L1_CACHE_CNT-1:0] bus_req_handshake;
    logic [L1_CACHE_CNT-1:0] bus_rsp_val;
    logic [L1_CACHE_CNT-1:0] bus_rsp_shared;
    logic [L1_CACHE_CNT-1:0] bus_rsp_rdy;
    logic [L1_CACHE_CNT-1:0] bus_rsp_handshake;

    // Encode the requester index as a one-hot mask.
    assign requester_mask = L1_CACHE_CNT'(1) << requester_idx_q;
    assign bus_req_handshake = bus_req_val & bus_req_rdy;
    assign bus_rsp_handshake = bus_rsp_val & bus_rsp_rdy;

    for (genvar i = 0; i < L1_CACHE_CNT; i++) begin : gen_bus_bridge
        assign bus_op[i].req_val = bus_req_val[i];
        assign bus_op[i].req_addr = req_addr_q;
        assign bus_op[i].bus_op = bus_op_q;
        assign bus_req_rdy[i] = bus_op[i].req_rdy;

        assign bus_rsp_val[i] = bus_op[i].rsp_val;
        assign bus_rsp_shared[i] = bus_op[i].rsp_shared;
        assign bus_op[i].rsp_rdy = bus_rsp_rdy[i];
    end

    always_comb begin
        state_d = state_q;
        bus_op_d = bus_op_q;
        req_addr_d = req_addr_q;
        requester_idx_d = requester_idx_q;
        broadcast_accepted_d = broadcast_accepted_q;
        reply_received_d = reply_received_q;
        synth_shared_d = synth_shared_q;

        cache_req.req_rdy = 1'b0;
        cache_req.rsp_val = 1'b0;
        cache_req.rsp_shared = synth_shared_q;
        bus_req_val = '0;
        bus_rsp_rdy = '0;

        unique case (state_q)
            IDLE: begin
                cache_req.req_rdy = 1'b1;
                if (cache_req.req_val) begin
                    req_addr_d = cache_req.req_addr;
                    bus_op_d = cache_req.bus_op;
                    requester_idx_d = CACHE_IDX_WIDTH'(cache_req.req_src);
                    broadcast_accepted_d = '0;
                    broadcast_accepted_d[cache_req.req_src] = 1'b1;
                    reply_received_d = '0;
                    reply_received_d[cache_req.req_src] = 1'b1;
                    synth_shared_d = 1'b0;
                    state_d = SCATTER;
                end
            end

            SCATTER: begin
                bus_req_val = ~broadcast_accepted_q;

                if (|bus_req_handshake) begin
                    broadcast_accepted_d = broadcast_accepted_q
                        | bus_req_handshake;
                    if (&(broadcast_accepted_q | bus_req_handshake)) begin
                        state_d = SCATTER_WAIT;
                    end
                end
            end

            SCATTER_WAIT: begin
                bus_rsp_rdy = ~reply_received_q;

                if (|bus_rsp_handshake) begin
                    reply_received_d = reply_received_q | bus_rsp_handshake;
                    synth_shared_d = synth_shared_q
                        | |(bus_rsp_handshake & bus_rsp_shared);
                    if (&(reply_received_q | bus_rsp_handshake)) begin
                        state_d = RESP;
                    end
                end
            end

            RESP: begin
                cache_req.rsp_val = 1'b1;
                if (cache_req.rsp_rdy) begin
                    state_d = IDLE;
                end
            end

            default: begin
                state_d = IDLE;
                broadcast_accepted_d = '0;
                reply_received_d = '0;
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            bus_op_q <= BusNOP;
            req_addr_q <= '0;
            requester_idx_q <= '0;
            broadcast_accepted_q <= '0;
            reply_received_q <= '0;
            synth_shared_q <= 1'b0;
        end else begin
            state_q <= state_d;
            bus_op_q <= bus_op_d;
            req_addr_q <= req_addr_d;
            requester_idx_q <= requester_idx_d;
            broadcast_accepted_q <= broadcast_accepted_d;
            reply_received_q <= reply_received_d;
            synth_shared_q <= synth_shared_d;
        end
    end

endmodule
/* verilator lint_on DECLFILENAME */
