`timescale 1ns / 1ps

import config_pkg::*;
/* verilator lint_off DECLFILENAME */
{% do unit_test(
    module_name = "cache_coherency_local",
    test_framework = "cocotb",
    use_wrapper = false,
    test_path = "dv/cocotb_benches/cache_coherency_tb.py",
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
    coh_state ret_coh_d, ret_coh_q;
    coh_state candidate_coh_d[2], candidate_coh_q[2];
    coh_bus_op coh_bus_op_d, coh_bus_op_q;

    logic begin_mesi_judge;
    coh_state effective_coh;
    coh_state judged_coh[2];
    coh_bus_op judged_bus_op;

    assign begin_mesi_judge = state_q == IDLE && req_val_i;
    assign effective_coh = req_is_hit_i ? req_coh_i : COH_Invalid;

    MESI_judger mesi_judger_inst (
        .begin_judge(begin_mesi_judge),
        .req_is_write_i(req_is_write_i),
        .current_coh_i(effective_coh),
        .next_coh_o(judged_coh),
        .coh_bus_op_o(judged_bus_op)
    );

    always_comb begin
        state_d = state_q;
        req_addr_d = req_addr_q;
        ret_coh_d = ret_coh_q;
        candidate_coh_d[0] = candidate_coh_q[0];
        candidate_coh_d[1] = candidate_coh_q[1];
        coh_bus_op_d = coh_bus_op_q;

        req_rdy_o = 1'b0;
        rsp_val_o = 1'b0;
        new_coh_state_o = ret_coh_q;

        coh_bus_req_val_o = 1'b0;
        coh_bus_req_op_o = coh_bus_op_q;
        coh_bus_req_addr_o = req_addr_q;
        coh_bus_rsp_rdy_o = 1'b0;

        unique case (state_q)
            IDLE: begin
                req_rdy_o = 1'b1;

                if (req_val_i) begin
                    req_addr_d = req_addr_i;
                    candidate_coh_d[0] = judged_coh[0];
                    candidate_coh_d[1] = judged_coh[1];
                    coh_bus_op_d = judged_bus_op;

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

                if (coh_bus_req_rdy_i) begin
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
            ret_coh_q <= COH_Invalid;
            candidate_coh_q[0] <= COH_Invalid;
            candidate_coh_q[1] <= COH_Invalid;
            coh_bus_op_q <= BusNOP;
        end else begin
            state_q <= state_d;
            req_addr_q <= req_addr_d;
            ret_coh_q <= ret_coh_d;
            candidate_coh_q[0] <= candidate_coh_d[0];
            candidate_coh_q[1] <= candidate_coh_d[1];
            coh_bus_op_q <= coh_bus_op_d;
        end
    end

endmodule


module cache_coherency_bus (
    input logic clk_i,
    input logic rst_ni,

);

    wire _unused_ok = &{1'b0, clk_i, rst_ni};

endmodule
/* verilator lint_on DECLFILENAME */
