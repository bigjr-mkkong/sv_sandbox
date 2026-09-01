`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNDRIVEN */
module cache_coherency_global_unit_test;
    localparam int unsigned L1_CACHE_CNT = 4;
    localparam int unsigned ADDR_WIDTH = 64;
    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned SRC_WIDTH = $clog2(L1_CACHE_CNT);

    logic clk_i;
    logic rst_ni;

    logic                  cache_req_val;
    logic [1:0]            cache_req_bus_op;
    logic [ADDR_WIDTH-1:0] cache_req_addr;
    logic [SRC_WIDTH-1:0]  cache_req_src;
    logic                  cache_req_rdy;
    logic                  cache_rsp_val;
    logic                  cache_rsp_shared;
    logic                  cache_rsp_rdy;

    logic [L1_CACHE_CNT-1:0]                 bus_req_val;
    logic [L1_CACHE_CNT-1:0][1:0]            bus_req_op;
    logic [L1_CACHE_CNT-1:0][ADDR_WIDTH-1:0] bus_req_addr;
    logic [L1_CACHE_CNT-1:0]                 bus_req_rdy;
    logic [L1_CACHE_CNT-1:0]                 bus_rsp_val;
    logic [L1_CACHE_CNT-1:0]                 bus_rsp_shared;
    logic [L1_CACHE_CNT-1:0]                 bus_rsp_rdy;
    logic [L1_CACHE_CNT*16-1:0]              pseudo_replier_delay_cfg;
    logic [L1_CACHE_CNT-1:0]                 pseudo_replier_resp_cfg;

    coh_cache2bus_req #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SRC_WIDTH(SRC_WIDTH)
    ) cache_req();

    coh_bus2cache_req #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) bus_op[L1_CACHE_CNT]();

    assign cache_req.req_val = cache_req_val;
    assign cache_req.bus_op = config_pkg::coh_bus_op'(cache_req_bus_op);
    assign cache_req.req_addr = cache_req_addr;
    assign cache_req.req_src = cache_req_src;
    assign cache_req_rdy = cache_req.req_rdy;
    assign cache_rsp_val = cache_req.rsp_val;
    assign cache_rsp_shared = cache_req.rsp_shared;
    assign cache_req.rsp_rdy = cache_rsp_rdy;

    for (genvar i = 0; i < L1_CACHE_CNT; i++) begin : gen_flatten_bus
        assign bus_req_val[i] = bus_op[i].req_val;
        assign bus_req_op[i] = bus_op[i].bus_op;
        assign bus_req_addr[i] = bus_op[i].req_addr;
        assign bus_req_rdy[i] = bus_op[i].req_rdy;

        assign bus_rsp_val[i] = bus_op[i].rsp_val;
        assign bus_rsp_shared[i] = bus_op[i].rsp_shared;
        assign bus_rsp_rdy[i] = bus_op[i].rsp_rdy;
    end

    cache_coherency_global #(
        .L1_CACHE_CNT(L1_CACHE_CNT),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .cache_req(cache_req),
        .bus_op(bus_op)
    );

    typedef enum logic[1:0] {
        IDLE,
        HOLD,
        REPLY
    } state_e;

    /*
    * Generate L1_CACHE_CNT number of FSM replier for each bus_op output from
    * cache_coherency_global
    */
    for (genvar i = 0; i < L1_CACHE_CNT; i++) begin : gen_pseudo_replier
        state_e state_d, state_q;
        logic [15:0] hold_counter_d, hold_counter_q;

        always_comb begin
            state_d = state_q;
            hold_counter_d = hold_counter_q;

            bus_op[i].req_rdy = 1'b0;
            bus_op[i].rsp_val = 1'b0;
            bus_op[i].rsp_shared = pseudo_replier_resp_cfg[i];

            unique case (state_q)
                IDLE: begin
                    bus_op[i].req_rdy = 1'b1;
                    if (bus_op[i].req_val) begin
                        hold_counter_d = pseudo_replier_delay_cfg[i*16 +: 16];
                        if (pseudo_replier_delay_cfg[i*16 +: 16] == 0) begin
                            state_d = REPLY;
                        end else begin
                            state_d = HOLD;
                        end
                    end
                end

                HOLD: begin
                    hold_counter_d = hold_counter_q - 1'b1;
                    if (hold_counter_q == 16'd1) begin
                        state_d = REPLY;
                    end
                end

                REPLY: begin
                    bus_op[i].rsp_val = 1'b1;
                    if (bus_op[i].rsp_rdy) begin
                        hold_counter_d = '0;
                        state_d = IDLE;
                    end
                end

                default: begin
                    hold_counter_d = '0;
                    state_d = IDLE;
                end
            endcase
        end

        always_ff @(posedge clk_i) begin
            if (!rst_ni) begin
                state_q <= IDLE;
                hold_counter_q <= '0;
            end else begin
                state_q <= state_d;
                hold_counter_q <= hold_counter_d;
            end
        end
    end
endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on DECLFILENAME */
