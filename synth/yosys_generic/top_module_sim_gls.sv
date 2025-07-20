
module top_module_sim_gls#(
    parameter DATAW = 32,
    parameter ERRW = 2
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input   logic req_val_i,
    input   logic req_comm_i,
    input   logic [DATAW-1: 0]req_data_i,
    output  logic req_rdy_o,

    output  logic rsp_val_o,
    output  logic [ERRW-1: 0]rsp_state_o,
    output  logic [DATAW-1: 0]rsp_data_o,
    input   logic rsp_rdy_i
);

top_module #(
    .DATAW(DATAW),
    .ERRW(ERRW)
    ) top_module (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .req_val_i(req_val_i),
    .req_comm_i(req_comm_i),
    .req_data_i(req_data_i),
    .req_rdy_o(req_rdy_o),

    .rsp_val_o(rsp_val_o),
    .rsp_state_o(rsp_state_o),
    .rsp_data_o(rsp_data_o),
    .rsp_rdy_i(rsp_rdy_i)
);

endmodule
