`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
import config_pkg::*;

/*
 * Blocking responder for coherence requests broadcast by another cache.
 * BusRd preserves shared copies, downgrades exclusive copies, and flushes a
 * modified copy before downgrading it. BusRdX flushes before invalidating;
 * BusUpgr only invalidates. The pre-change hit result is held as rsp_shared
 * until the response is accepted.
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
    output logic [INDEX_BITS-1:0]       lookup_idx_o,
    output logic [TAG_WIDTH-1:0]        lookup_tag_o,
    input  logic                        lookup_hit_i,
    input  coh_state                    lookup_coh_i,
    input  logic [LINE_WIDTH-1:0]       lookup_data_i,

    output logic                        llc_req_val_o,
    input  logic                        llc_req_rdy_i,
    output logic                        llc_req_is_write_o,
    output logic [ADDR_WIDTH-1:0]       llc_req_addr_o,
    output logic [LINE_WIDTH-1:0]       llc_req_data_o,
    input  logic                        llc_rsp_val_i,
    output logic                        llc_rsp_rdy_o,

    cache_commit_if.producer remote_commit
);
    typedef enum logic [2:0] {
        IDLE,
        LLC_SUBMIT,
        LLC_WAIT,
        REMOTE_COMMIT,
        RESP
    } state_e;

    state_e state_d, state_q;
    logic [ADDR_WIDTH-1:0] req_addr_d, req_addr_q;
    logic lookup_hit_d, lookup_hit_q;
    logic [LINE_WIDTH-1:0] lookup_data_d, lookup_data_q;
    coh_state remote_coh_state_d, remote_coh_state_q;

    logic [INDEX_BITS-1:0] incoming_idx;
    logic [TAG_WIDTH-1:0] incoming_tag;

    assign incoming_idx = INDEX_BITS'(
        bus2cache_req.req_addr >> OFFSET_WIDTH
    );
    assign incoming_tag = TAG_WIDTH'(
        bus2cache_req.req_addr >> (OFFSET_WIDTH + INDEX_BITS)
    );

    assign lookup_idx_o = state_q == IDLE
        ? incoming_idx : INDEX_BITS'(req_addr_q >> OFFSET_WIDTH);
    assign lookup_tag_o = state_q == IDLE
        ? incoming_tag
        : TAG_WIDTH'(req_addr_q >> (OFFSET_WIDTH + INDEX_BITS));

    always_comb begin
        state_d = state_q;
        req_addr_d = req_addr_q;
        lookup_hit_d = lookup_hit_q;
        lookup_data_d = lookup_data_q;
        remote_coh_state_d = remote_coh_state_q;

        bus2cache_req.req_rdy = 1'b0;
        bus2cache_req.rsp_val = 1'b0;
        bus2cache_req.rsp_shared = lookup_hit_q;

        idx_in_use_o = state_q != IDLE;
        active_idx_o = lookup_idx_o;

        llc_req_val_o = 1'b0;
        llc_req_is_write_o = 1'b1;
        llc_req_addr_o = {
            req_addr_q[ADDR_WIDTH-1:OFFSET_WIDTH],
            {OFFSET_WIDTH{1'b0}}
        };
        llc_req_data_o = lookup_data_q;
        llc_rsp_rdy_o = 1'b0;

        remote_commit.val = 1'b0;
        remote_commit.index = INDEX_BITS'(
            req_addr_q >> OFFSET_WIDTH
        );
        remote_commit.coh = remote_coh_state_q;
        remote_commit.tag_we = 1'b0;
        remote_commit.tag = '0;
        remote_commit.data_we = 1'b0;
        remote_commit.data = '0;

        unique case (state_q)
            IDLE: begin
                bus2cache_req.req_rdy = idx_avail_i;
                if (bus2cache_req.req_val && bus2cache_req.req_rdy) begin
                    req_addr_d = bus2cache_req.req_addr;
                    lookup_hit_d = lookup_hit_i;
                    lookup_data_d = lookup_data_i;

                    if (!lookup_hit_i) begin
                        state_d = RESP;
                    end else if (bus2cache_req.bus_op == BusRd) begin
                        remote_coh_state_d = COH_Shared;
                        if (lookup_coh_i == COH_Modified) begin
                            state_d = LLC_SUBMIT;
                        end else if (lookup_coh_i == COH_Exclusive) begin
                            state_d = REMOTE_COMMIT;
                        end else begin
                            state_d = RESP;
                        end
                    end else if (bus2cache_req.bus_op == BusRdX) begin
                        remote_coh_state_d = COH_Invalid;
                        state_d = LLC_SUBMIT;
                    end else if (bus2cache_req.bus_op == BusUpgr) begin
                        remote_coh_state_d = COH_Invalid;
                        state_d = REMOTE_COMMIT;
                    end else begin
                        state_d = RESP;
                    end
                end
            end

            LLC_SUBMIT: begin
                llc_req_val_o = 1'b1;
                if (llc_req_rdy_i) begin
                    state_d = LLC_WAIT;
                end
            end

            LLC_WAIT: begin
                llc_rsp_rdy_o = 1'b1;
                if (llc_rsp_val_i) begin
                    state_d = REMOTE_COMMIT;
                end
            end

            REMOTE_COMMIT: begin
                remote_commit.val = 1'b1;
                if (remote_commit.rdy) begin
                    state_d = RESP;
                end
            end

            RESP: begin
                bus2cache_req.rsp_val = 1'b1;
                if (bus2cache_req.rsp_rdy) begin
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
            lookup_hit_q <= 1'b0;
            lookup_data_q <= '0;
            remote_coh_state_q <= COH_Invalid;
        end else begin
            state_q <= state_d;
            req_addr_q <= req_addr_d;
            lookup_hit_q <= lookup_hit_d;
            lookup_data_q <= lookup_data_d;
            remote_coh_state_q <= remote_coh_state_d;
        end
    end

{% if not RENDER_OPTION.SYNTH %}
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        state_q == IDLE && bus2cache_req.req_val
            && bus2cache_req.req_rdy
        |-> bus2cache_req.bus_op != BusNOP
    ) else $error("BusNOP must not be broadcast to a snoop responder");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        llc_req_val_o |-> llc_req_is_write_o
    ) else $error("a snoop responder may only write to the LLC");
{% endif %}

endmodule
/* verilator lint_on DECLFILENAME */
