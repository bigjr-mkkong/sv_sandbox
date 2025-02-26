module top_module#(
    parameter UART_DATA_WIDTH = 8
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input   logic uart_rsp_rdy_i,
    output  logic [UART_DATA_WIDTH-1: 0] uart_rsp_data_o,
    output  logic uart_rsp_val_o
);


    logic [UART_DATA_WIDTH-1: 0]uart_buf_q;
    logic [UART_DATA_WIDTH-1: 0]uart_buf_d;
    
    logic [UART_DATA_WIDTH-1: 0]send_out;

    assign uart_rsp_data_o = send_out;

    always_comb begin
        uart_rsp_val_o = 0;
        send_out = 0;
        if (uart_rsp_rdy_i) begin
            send_out = uart_buf_q;
            uart_buf_d = uart_buf_q > 8'h59 ? 8'h31 : uart_buf_q + 1;
            uart_rsp_val_o = 1;
        end else begin
            uart_buf_d = uart_buf_q;
        end
    end
        
    always @(posedge clk_i) begin
        if (~rst_ni) begin
            uart_buf_q <= 8'h31;
        end else begin
            uart_buf_q <= uart_buf_d;
        end
    end

endmodule
