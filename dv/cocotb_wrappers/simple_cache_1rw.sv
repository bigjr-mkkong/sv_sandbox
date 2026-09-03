`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNDRIVEN */
module simple_cache_1rw_unit_test;
    localparam int unsigned ADDR_WIDTH = 64;
    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned DATA_PER_LINE = 8;

    logic clk_i;
    logic rst_ni;

    typedef enum logic {
        TEST_CACHE2BUS,
        TEST_SNOOP
    } coherence_test_mode_e;

    typedef enum logic [1:0] {
        C2B_IDLE,
        C2B_DELAY,
        C2B_RESP
    } cache2bus_state_e;

    typedef enum logic [2:0] {
        SNOOP_IDLE,
        SNOOP_SUBMIT,
        SNOOP_READY_DELAY,
        SNOOP_WAIT,
        SNOOP_DONE
    } snoop_state_e;

    // Exactly one coherence direction is active in a test at a time.
    coherence_test_mode_e   coherence_test_mode;

    // Cache-to-bus responder configuration and visibility.
    logic                   c2b_accept_enable;
    logic [7:0]             c2b_rsp_delay_cycles;
    logic                   c2b_rsp_shared;
    logic                   c2b_check_req;
    logic [1:0]             c2b_expected_req_op;
    logic [ADDR_WIDTH-1:0]  c2b_expected_req_addr;
    logic                   c2b_busy_o;
    logic                   c2b_req_mismatch_o;
    logic [31:0]            c2b_req_count_o;
    logic [1:0]             c2b_last_req_op_o;
    logic [ADDR_WIDTH-1:0]  c2b_last_req_addr_o;

    cache2bus_state_e       c2b_state_q;
    logic [7:0]             c2b_delay_q;
    logic                   c2b_shared_q;

    // Bus-to-cache snoop source configuration and visibility.
    logic                   snoop_start;
    logic [1:0]             snoop_req_op;
    logic [ADDR_WIDTH-1:0]  snoop_req_addr;
    logic [7:0]             snoop_rsp_ready_delay_cycles;
    logic                   snoop_done_rdy;
    logic                   snoop_busy_o;
    logic                   snoop_done_o;
    logic                   snoop_rsp_shared_o;

    snoop_state_e           snoop_state_q;
    config_pkg::coh_bus_op  snoop_op_q;
    logic [ADDR_WIDTH-1:0]  snoop_addr_q;
    logic [7:0]             snoop_delay_q;
    logic                   snoop_shared_q;

    upstream_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) upstream();

    taxi_axil_if #(
        .DATA_W(DATA_WIDTH * DATA_PER_LINE),
        .ADDR_W(ADDR_WIDTH)
    ) m_axil();

    coh_cache2bus_req #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) coh_bus_req();

    coh_bus2cache_req #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) snoop_bus_req();

    // Cache-to-bus requests are accepted first, delayed, then answered. No
    // bus-to-cache snoop can be issued while this test mode owns the bus.
    assign coh_bus_req.req_rdy = coherence_test_mode == TEST_CACHE2BUS
        && c2b_accept_enable && c2b_state_q == C2B_IDLE;
    assign coh_bus_req.rsp_val = coherence_test_mode == TEST_CACHE2BUS
        && c2b_state_q == C2B_RESP;
    assign coh_bus_req.rsp_shared = c2b_shared_q;
    assign c2b_busy_o = c2b_state_q != C2B_IDLE;

    // A snoop holds its command/address through request acceptance, optionally
    // delays response readiness, then waits for the cache-local responder. The
    // local cache-to-bus request may remain pending while snoop mode is active;
    // this allows serialization-retry timing to be tested directly.
    assign snoop_bus_req.req_val = coherence_test_mode == TEST_SNOOP
        && snoop_state_q == SNOOP_SUBMIT;
    assign snoop_bus_req.bus_op = snoop_op_q;
    assign snoop_bus_req.req_addr = snoop_addr_q;
    assign snoop_bus_req.rsp_rdy = coherence_test_mode == TEST_SNOOP
        && snoop_state_q == SNOOP_WAIT;
    assign snoop_busy_o = snoop_state_q != SNOOP_IDLE;
    assign snoop_done_o = snoop_state_q == SNOOP_DONE;
    assign snoop_rsp_shared_o = snoop_shared_q;

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            c2b_state_q <= C2B_IDLE;
            c2b_delay_q <= '0;
            c2b_shared_q <= 1'b0;
            c2b_req_mismatch_o <= 1'b0;
            c2b_req_count_o <= '0;
            c2b_last_req_op_o <= config_pkg::BusNOP;
            c2b_last_req_addr_o <= '0;
        end else if (coherence_test_mode != TEST_CACHE2BUS) begin
            c2b_state_q <= C2B_IDLE;
            c2b_delay_q <= '0;
        end else begin
            unique case (c2b_state_q)
                C2B_IDLE: if (coh_bus_req.req_val
                        && coh_bus_req.req_rdy) begin
                    c2b_delay_q <= c2b_rsp_delay_cycles;
                    c2b_shared_q <= c2b_rsp_shared;
                    c2b_req_count_o <= c2b_req_count_o + 1'b1;
                    c2b_last_req_op_o <= coh_bus_req.bus_op;
                    c2b_last_req_addr_o <= coh_bus_req.req_addr;

                    if (c2b_check_req
                        && (coh_bus_req.bus_op != c2b_expected_req_op
                            || coh_bus_req.req_addr
                                != c2b_expected_req_addr)) begin
                        c2b_req_mismatch_o <= 1'b1;
                    end

                    c2b_state_q <= c2b_rsp_delay_cycles == '0
                        ? C2B_RESP : C2B_DELAY;
                end

                C2B_DELAY: begin
                    c2b_delay_q <= c2b_delay_q - 1'b1;
                    if (c2b_delay_q == 1) begin
                        c2b_state_q <= C2B_RESP;
                    end
                end

                C2B_RESP: if (coh_bus_req.rsp_rdy) begin
                    c2b_state_q <= C2B_IDLE;
                end

                default: c2b_state_q <= C2B_IDLE;
            endcase
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            snoop_state_q <= SNOOP_IDLE;
            snoop_op_q <= config_pkg::BusNOP;
            snoop_addr_q <= '0;
            snoop_delay_q <= '0;
            snoop_shared_q <= 1'b0;
        end else if (coherence_test_mode != TEST_SNOOP) begin
            snoop_state_q <= SNOOP_IDLE;
            snoop_delay_q <= '0;
        end else begin
            unique case (snoop_state_q)
                SNOOP_IDLE: if (snoop_start) begin
                    snoop_op_q <= config_pkg::coh_bus_op'(snoop_req_op);
                    snoop_addr_q <= snoop_req_addr;
                    snoop_state_q <= SNOOP_SUBMIT;
                end

                SNOOP_SUBMIT: if (snoop_bus_req.req_rdy) begin
                    snoop_delay_q <= snoop_rsp_ready_delay_cycles;
                    snoop_state_q <= snoop_rsp_ready_delay_cycles == '0
                        ? SNOOP_WAIT : SNOOP_READY_DELAY;
                end

                SNOOP_READY_DELAY: begin
                    snoop_delay_q <= snoop_delay_q - 1'b1;
                    if (snoop_delay_q == 1) begin
                        snoop_state_q <= SNOOP_WAIT;
                    end
                end

                SNOOP_WAIT: if (snoop_bus_req.rsp_val) begin
                    snoop_shared_q <= snoop_bus_req.rsp_shared;
                    snoop_state_q <= SNOOP_DONE;
                end

                SNOOP_DONE: if (snoop_done_rdy) begin
                    snoop_state_q <= SNOOP_IDLE;
                end

                default: snoop_state_q <= SNOOP_IDLE;
            endcase
        end
    end

    simple_cache_1rw #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .upstream(upstream),
        .m_axil_wr(m_axil),
        .m_axil_rd(m_axil),
        .cache2bus_req(coh_bus_req),
        .bus2cache_req(snoop_bus_req)
    );
endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on DECLFILENAME */
