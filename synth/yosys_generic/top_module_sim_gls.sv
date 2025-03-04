
module top_module_sim_gls#(
    parameter UART_DATA_WIDTH = 8
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input   logic uart_rsp_rdy_i,
    output  logic [UART_DATA_WIDTH-1: 0] uart_rsp_data_o,
    output  logic uart_rsp_val_o
);

top_module #(
    .UART_DATA_WIDTH(UART_DATA_WIDTH)
) top_module (
		.clk_i(clk_i),
		.rst_ni(rst_ni),

		.uart_rsp_rdy_i(uart_rsp_rdy_i),
		.uart_rsp_data_o(uart_rsp_data_o),
		.uart_rsp_val_o(uart_rsp_val_o),
    );

endmodule
