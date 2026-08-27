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

    config_pkg::coh_state req_coh;
    config_pkg::coh_state new_coh_state;
    config_pkg::coh_bus_op coh_bus_req_op;

    logic coh_bus_req_rdy;
    logic coh_bus_rsp_val;
    logic coh_bus_rsp_shared;

    logic       bus_pending_q;
    logic [7:0] bus_delay_q;
    logic       bus_shared_q;

    assign req_coh = config_pkg::coh_state'(req_coh_i);
    assign new_coh_state_o = new_coh_state;
    assign coh_bus_req_op_o = coh_bus_req_op;

    // Blocking one-entry responder. Configuration is captured with the
    // request, then the response is held until the DUT acknowledges it.
    assign coh_bus_req_rdy = !bus_pending_q;
    assign coh_bus_rsp_val = bus_pending_q && (bus_delay_q == '0);
    assign coh_bus_rsp_shared = bus_shared_q;
    assign bus_busy_o = bus_pending_q;

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            bus_pending_q <= 1'b0;
            bus_delay_q <= '0;
            bus_shared_q <= 1'b0;
        end else begin
            if (coh_bus_req_val_o && coh_bus_req_rdy) begin
                bus_pending_q <= 1'b1;
                bus_delay_q <= bus_rsp_delay_cycles;
                bus_shared_q <= bus_rsp_shared;
            end else if (bus_pending_q && (bus_delay_q != '0)) begin
                bus_delay_q <= bus_delay_q - 1'b1;
            end else if (coh_bus_rsp_val && coh_bus_rsp_rdy_o) begin
                bus_pending_q <= 1'b0;
            end
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
