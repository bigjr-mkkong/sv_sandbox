`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
module MESI_judger_unit_test;
    logic begin_judge;
    logic req_is_write_i;
    logic [1:0] current_coh_i;
    logic [1:0] next_coh_no_shared_o;
    logic [1:0] next_coh_shared_o;
    logic [1:0] coh_bus_op_o;

    config_pkg::coh_state current_coh;
    config_pkg::coh_state next_coh[2];
    config_pkg::coh_bus_op coh_bus_op;

    assign current_coh = config_pkg::coh_state'(current_coh_i);
    assign next_coh_no_shared_o = next_coh[0];
    assign next_coh_shared_o = next_coh[1];
    assign coh_bus_op_o = coh_bus_op;

    MESI_judger dut (
        .begin_judge(begin_judge),
        .req_is_write_i(req_is_write_i),
        .current_coh_i(current_coh),
        .next_coh_o(next_coh),
        .coh_bus_op_o(coh_bus_op)
    );
endmodule
/* verilator lint_on DECLFILENAME */
