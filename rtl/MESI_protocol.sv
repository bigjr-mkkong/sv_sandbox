// | Effective MESI | CPU operation | Bus operation | Final state |
// | -------------- | ------------- | ------------- | ----------- |
// | I              | Read          | BusRd         | E or S      |
// | I              | Write         | BusRdX        | M           |
// | S              | Read          | BusNOP        | S           |
// | S              | Write         | BusUpgr       | M           |
// | E              | Read          | BusNOP        | E           |
// | E              | Write         | BusNOP        | M           |
// | M              | Read          | BusNOP        | M           |
// | M              | Write         | BusNOP        | M           |

`timescale 1ns / 1ps
import config_pkg::*;

/* verilator lint_off DECLFILENAME */
{% do unit_test(
    module_name = "MESI_judger",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/MESI_protocol_tb.py") %}
module MESI_judger (
    input logic begin_judge,
    input logic req_is_write_i,
    input coh_state current_coh_i,

    //This field will return two candidates of next coh state
    //Which one will be chose depends on how bus share signal return
    output coh_state next_coh_o[2],
    output coh_bus_op coh_bus_op_o
);


    always_comb begin
        next_coh_o[0] = COH_Invalid;
        next_coh_o[1] = COH_Invalid;
        coh_bus_op_o = BusNOP;

        if (begin_judge) begin
            unique case (current_coh_i)
                COH_Invalid: begin
                    if (req_is_write_i) begin
                        next_coh_o[0] = COH_Modified;
                        next_coh_o[1] = COH_Modified;
                        coh_bus_op_o = BusRdX;
                    end else begin
                        next_coh_o[0] = COH_Exclusive;
                        next_coh_o[1] = COH_Shared;
                        coh_bus_op_o = BusRd;
                    end
                end

                COH_Shared: begin
                    if (req_is_write_i) begin
                        next_coh_o[0] = COH_Modified;
                        next_coh_o[1] = COH_Modified;
                        coh_bus_op_o = BusUpgr;
                    end else begin
                        next_coh_o[0] = COH_Shared;
                        next_coh_o[1] = COH_Shared;
                    end
                end

                COH_Exclusive: begin
                    next_coh_o[0] = req_is_write_i
                        ? COH_Modified : COH_Exclusive;
                    next_coh_o[1] = next_coh_o[0];
                end

                COH_Modified: begin
                    next_coh_o[0] = COH_Modified;
                    next_coh_o[1] = COH_Modified;
                end

                default: begin
                    next_coh_o[0] = COH_Invalid;
                    next_coh_o[1] = COH_Invalid;
                    coh_bus_op_o = BusNOP;
                end
            endcase
        end
    end

endmodule
/* verilator lint_on DECLFILENAME */
