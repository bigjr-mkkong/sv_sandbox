
module top_module_sim_gls#(
    parameter DATA_WIDTH = 32,
    parameter MAX_CAPACITY = 2 ** 4
    ) (
    input logic clk_i,
    input logic rst_ni,
    input logic req_val_i,
    input logic [1:0]req_typ_i, // 1:read, 2:write
    input logic [DATA_WIDTH-1: 0]data_i,
    output logic req_rdy_o,

    output logic rsp_val_o,
    output logic [DATA_WIDTH-1: 0]data_o,
    input logic rsp_rdy_i
);

fifo_test#(
    .DATA_WIDTH(DATA_WIDTH),
    .MAX_CAPACITY(MAX_CAPACITY)
    ) FIFO_test_mod  (
		.clk_i (clk_i),
		.rst_ni (rst_ni),

		.req_val_i (req_val_i),
		.req_typ_i (req_typ_i),
		.data_i (data_i),
		.req_rdy_o (req_rdy_o),

		.rsp_val_o (rsp_val_o),
		.data_o (data_o),
        .err_o (_),
		.rsp_rdy_i (rsp_rdy_i)
    );

endmodule
