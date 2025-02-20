module top_module#(
    parameter UART_DATA_WIDTH = 8
    ) (
    input   logic clk_i,
    input   logic rst_ni,
    input   logic uart_req_val_i,
    input   logic [UART_DATA_WIDTH-1: 0] uart_data_i,
    output  logic uart_req_rdy_o,

    input   logic uart_rsp_rdy_i,
    output  logic [UART_DATA_WIDTH-1: 0] uart_rsp_data_o,
    output  logic uart_rsp_val_o
);

    typedef enum logic {
        INIT = 1'b0,
        REPLY = 1'b1
    } state_t;

    state_t state_d, state_q;

    logic [UART_DATA_WIDTH-1: 0]uart_recv_buf_d;
    logic [UART_DATA_WIDTH-1: 0]uart_recv_buf_q;

    always_comb begin
        uart_req_rdy_o = 0;
        uart_rsp_val_o = 0;
        case (state_q)
            INIT:
            begin
                if (uart_req_val_i) begin
                    uart_req_rdy_o = 1;
                    uart_recv_buf_d = uart_data_i;
                    state_d = REPLY;
                end else begin
                    state_d = INIT;
                end
            end

            REPLY:
            begin
                if (uart_rsp_rdy_i) begin
                    uart_rsp_data_o = uart_recv_buf_q;
                    uart_rsp_val_o = 1;
                    state_d = INIT;
                end else begin
                    state_d = REPLY;
                end
            end

        endcase
    end
        
    always @(posedge clk_i) begin
        if (~rst_ni) begin
            state_q <= INIT;
            uart_recv_buf_q <= 0;
        end else begin
            state_q <= state_d;
            uart_recv_buf_q <= uart_recv_buf_d;
        end
    end

endmodule
