module top_module#(
    parameter DATA_BITS = 32,
    localparam DATA_WIDTH = $clog2(DATA_BITS),
    parameter MEM_SIZE = 2**7,
    localparam ADDR_WIDTH = $clog2(MEM_SIZE)
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input logic req_val_i,
    input logic req_typ_i, //0 is read, 1 is write
    input logic [ADDR_WIDTH-1: 0]req_addr_i,
    input logic [DATA_WIDTH-1: 0]req_data_i,
    output logic req_rdy_o,

    output logic rsp_val_o,
    output logic [DATA_WIDTH-1: 0]rsp_data_o,
    input logic rsp_rdy_i
);

mem #(
    .DATA_BITS(DATA_BITS),
    .MEM_SIZE(MEM_SIZE)
    )memblk(
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.req_val_i(req_val_i),
        .req_typ_i(req_typ_i),
		.req_addr_i(req_addr_i),
		.req_data_i(req_data_i),
		.req_rdy_o(req_rdy_o),

		.rsp_val_o(rsp_val_o),
		.rsp_data_o(rsp_data_o),
		.rsp_rdy_i(rsp_rdy_i)
    );

endmodule
