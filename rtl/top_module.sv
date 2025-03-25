module top_module#(
    parameter DATAW = 32
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input   logic uart_rsp_rdy_i,
    output  logic [DATAW-1: 0] uart_rsp_data_o,
    output  logic uart_rsp_val_o
);


    logic [DATAW-1: 0]uart_buf_q;
    logic [DATAW-1: 0]uart_buf_d;
    
    logic [DATAW-1: 0]send_out;

    assign uart_rsp_data_o = send_out;

    always_comb begin
        uart_rsp_val_o = 0;
        send_out = 0;
        if (uart_rsp_rdy_i) begin
            send_out = uart_buf_q;
            uart_buf_d = uart_buf_q > 32'habcd ? 32'hab40 : uart_buf_q + 1;
            uart_rsp_val_o = 1;
        end else begin
            uart_buf_d = uart_buf_q;
        end
    end
        
    always @(posedge clk_i) begin
        if (~rst_ni) begin
            uart_buf_q <= 32'hab40;
        end else begin
            uart_buf_q <= uart_buf_d;
        end
    end

endmodule
