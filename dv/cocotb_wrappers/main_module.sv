`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
module main_module_unit_test (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic ready_i,
    output logic valid_o,
    output logic [config_pkg::MAIN_DATA_WIDTH-1:0] data_o
);
    main_module #(.DATA_WIDTH(config_pkg::MAIN_DATA_WIDTH)) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .m_axis_tx_tdata_o(data_o),
        .m_axis_tx_tvalid_o(valid_o),
        .m_axis_tx_tready_i(ready_i)
    );
endmodule
/* verilator lint_on DECLFILENAME */
