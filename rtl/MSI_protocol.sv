// | Effective MSI  | CPU operation | Bus operation | Final state |
// | -------------- | ------------- | ------------- | ----------- |
// | I              | Read          | BusRd         | S           |
// | I              | Write         | BusRdX        | M           |
// | S              | Read          | BusNOP        | S           |
// | S              | Write         | BusUpgr       | M           |
// | M              | Read          | BusNOP        | M           |
// | M              | Write         | BusNOP        | M           |

{% if COH_PROTOCOL.MSI %}
`timescale 1ns / 1ps
import config_pkg::*;

/* verilator lint_off DECLFILENAME */
{% do unit_test(
    module_name = "MSI_judger",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/MSI_protocol_tb.py") %}
module MSI_judger (
    input logic begin_judge,
    input logic req_is_write_i,
    input coh_state current_coh_i,

    // Keep the MESI interface; MSI does not depend on the bus shared result.
    output coh_state next_coh_o[2],
    output coh_bus_op coh_bus_op_o
);
    always_comb begin
        next_coh_o[0] = COH_Invalid;
        coh_bus_op_o = BusNOP;

        if (begin_judge) begin
            unique case (current_coh_i)
                COH_Invalid: begin
                    next_coh_o[0] = req_is_write_i
                        ? COH_Modified : COH_Shared;
                    coh_bus_op_o = req_is_write_i ? BusRdX : BusRd;
                end

                COH_Shared: begin
                    next_coh_o[0] = req_is_write_i
                        ? COH_Modified : COH_Shared;
                    coh_bus_op_o = req_is_write_i ? BusUpgr : BusNOP;
                end

                COH_Modified: next_coh_o[0] = COH_Modified;

                default: begin
                    next_coh_o[0] = COH_Invalid;
                    coh_bus_op_o = BusNOP;
                end
            endcase
{% if not RENDER_OPTION.SYNTH %}
            assert (current_coh_i != COH_Exclusive)
                else $error("MSI judger received an Exclusive cache line");
{% endif %}
        end

        next_coh_o[1] = next_coh_o[0];
    end
endmodule
/* verilator lint_on DECLFILENAME */
{% endif %}
