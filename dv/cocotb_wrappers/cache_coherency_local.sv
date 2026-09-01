`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNDRIVEN */
module cache_coherency_local_unit_test;
    localparam int unsigned ADDR_WIDTH = 64;

    logic clk_i;
    logic rst_ni;

    logic                  req_val_i;
    logic                  req_is_write_i;
    logic                  req_is_hit_i;
    logic [ADDR_WIDTH-1:0] req_addr_i;
    logic [1:0]            req_coh_i;
    logic                  req_rdy_o;

    logic       rsp_rdy_i;
    logic [1:0] new_coh_state_o;
    logic       rsp_val_o;

    // Cocotb configuration and visibility for the pseudo coherence bus.
    logic [7:0] bus_rsp_delay_cycles;
    logic       bus_rsp_shared;
    logic       bus_busy_o;
    logic [1:0] coh_bus_req_op_o;
    logic [ADDR_WIDTH-1:0] coh_bus_req_addr_o;
    logic                  coh_bus_req_val_o;
    logic                  coh_bus_rsp_rdy_o;
    coh_bus_op bus_op_out_q, bus_op_out_d;

    config_pkg::coh_state req_coh;
    config_pkg::coh_state new_coh_state;
    config_pkg::coh_bus_op coh_bus_req_op;

    logic coh_bus_req_rdy;
    logic coh_bus_rsp_val;
    logic coh_bus_rsp_shared;

    typedef enum logic [1:0] {
        BUS_IDLE,
        BUS_HOLD,
        BUS_REPLY
    } bus_state_e;

    bus_state_e bus_state_d, bus_state_q;
    logic [7:0] bus_delay_d, bus_delay_q;
    logic       bus_shared_d, bus_shared_q;

    assign req_coh = config_pkg::coh_state'(req_coh_i);
    assign new_coh_state_o = new_coh_state;
    assign coh_bus_req_op_o = coh_bus_req_op;

    assign bus_busy_o = bus_state_q != BUS_IDLE;

    // Blocking pseudo-bus peer. Delay zero replies in the cycle immediately
    // after request acceptance; delay N waits N complete cycles. A reply stays
    // valid, with a stable shared bit, until the DUT accepts it.
    always_comb begin
        bus_state_d = bus_state_q;
        bus_delay_d = bus_delay_q;
        bus_shared_d = bus_shared_q;

        coh_bus_req_rdy = 1'b0;
        coh_bus_rsp_val = 1'b0;
        coh_bus_rsp_shared = bus_shared_q;
        bus_op_out_d = bus_op_out_q;

        unique case (bus_state_q)
            BUS_IDLE: begin
                coh_bus_req_rdy = 1'b1;
                if (coh_bus_req_val_o && coh_bus_req_rdy) begin
                    bus_op_out_d = coh_bus_req_op;
                    bus_delay_d = bus_rsp_delay_cycles;
                    bus_shared_d = bus_rsp_shared;
                    if (bus_rsp_delay_cycles == '0) begin
                        bus_state_d = BUS_REPLY;
                    end else begin
                        bus_state_d = BUS_HOLD;
                    end
                end
            end

            BUS_HOLD: begin
                if (bus_delay_q == 8'd1) begin
                    bus_delay_d = '0;
                    bus_state_d = BUS_REPLY;
                end else begin
                    bus_delay_d = bus_delay_q - 1'b1;
                end
            end

            BUS_REPLY: begin
                coh_bus_rsp_val = 1'b1;
                if (coh_bus_rsp_rdy_o) begin
                    bus_delay_d = '0;
                    bus_state_d = BUS_IDLE;
                end
            end

            default: begin
                bus_delay_d = '0;
                bus_shared_d = 1'b0;
                bus_state_d = BUS_IDLE;
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            bus_state_q <= BUS_IDLE;
            bus_delay_q <= '0;
            bus_shared_q <= 1'b0;
            bus_op_out_q <= BusNOP;
        end else begin
            bus_state_q <= bus_state_d;
            bus_delay_q <= bus_delay_d;
            bus_shared_q <= bus_shared_d;
            bus_op_out_q <= bus_op_out_d;
        end
    end

    cache_coherency_local #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .req_val_i(req_val_i),
        .req_is_write_i(req_is_write_i),
        .req_is_hit_i(req_is_hit_i),
        .req_addr_i(req_addr_i),
        .req_coh_i(req_coh),
        .req_rdy_o(req_rdy_o),

        .rsp_rdy_i(rsp_rdy_i),
        .new_coh_state_o(new_coh_state),
        .rsp_val_o(rsp_val_o),

        .coh_bus_req_rdy_i(coh_bus_req_rdy),
        .coh_bus_req_op_o(coh_bus_req_op),
        .coh_bus_req_addr_o(coh_bus_req_addr_o),
        .coh_bus_req_val_o(coh_bus_req_val_o),

        .coh_bus_rsp_val_i(coh_bus_rsp_val),
        .coh_bus_shared_i(coh_bus_rsp_shared),
        .coh_bus_rsp_rdy_o(coh_bus_rsp_rdy_o)
    );

endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on DECLFILENAME */
