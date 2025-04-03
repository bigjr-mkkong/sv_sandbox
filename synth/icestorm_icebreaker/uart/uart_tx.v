module uart_tx(
    input clk,
    input rst_n,
    input data_val_i,
    input [7:0] data_in,
    output reg data_rdy_o,
    output reg tx
);

    localparam integer BAUD_DIV = 50250000 / 115200;

    localparam STATE_IDLE = 1'b0, STATE_TX = 1'b1;

    reg state;
    reg [3:0] bit_cnt;      // Counts the 10 bits (0 to 9) in the frame
    reg [9:0] shift_reg;    // 10-bit frame: {stop, data[7:0], start}
    reg [15:0] baud_counter; // Counter for baud rate timing

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= STATE_IDLE;
            bit_cnt     <= 0;
            baud_counter<= 0;
            shift_reg   <= 10'd0;
            tx          <= 1'b1;  // Idle line state is high
            data_rdy_o  <= 1'b1;  // Ready to accept new data
        end else begin
            case (state)
                STATE_IDLE: begin
                    data_rdy_o <= 1'b1;
                    tx         <= 1'b1;
                    baud_counter <= 0;
                    bit_cnt    <= 0;
                    if (data_val_i) begin
                        shift_reg <= {1'b1, data_in, 1'b0};
                        state     <= STATE_TX;
                        data_rdy_o<= 1'b0;
                    end
                end

                STATE_TX: begin
                    data_rdy_o <= 1'b0;
                    if (baud_counter == BAUD_DIV - 1) begin
                        baud_counter <= 0;
                        // Output the LSB (start bit first)
                        tx <= shift_reg[0];
                        // Shift right; fill in with 1 (idle) at the MSB
                        shift_reg <= {1'b1, shift_reg[9:1]};
                        if (bit_cnt == 9) begin
                            // Completed transmission of all 10 bits
                            state   <= STATE_IDLE;
                            bit_cnt <= 0;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

module uart_tx32 (
    input   clk_i,
    input   rst_ni,
    input   req_val_i,
    input   [DATAW-1:0] data_i,
    output  reg req_rdy_o,
    output  reg tx
);
    localparam DATAW = 32;
    localparam UART_DATAW = 8;
    localparam  INIT	    = 3'd0,
                MSB_31_24	= 3'd1,
                MSB_23_16	= 3'd2,
                MSB_15_8	= 3'd3,
                MSB_7_0 	= 3'd4;

    reg[2:0] state_d, state_q;

    always @(posedge clk_i) begin
        if(~rst_ni) begin
            state_q <= INIT;
            data_buf_q <= 0;
        end else begin
            state_q <= state_d;
            data_buf_q <= data_buf_d;
        end
    end

    reg [DATAW-1: 0]data_buf_d, data_buf_q;
    reg [UART_DATAW-1:0]uart8_in_buf_i;
    reg uart8_data_val_i, uart8_data_rdy_o;

    uart_tx uart_tx_ins(
        .clk                (clk_i),
        .rst_n              (rst_ni),
        .data_val_i         (uart8_data_val_i),
        .data_in            (uart8_in_buf_i),
        .data_rdy_o         (uart8_data_rdy_o),
        .tx                 (TX)
    );

    always @(*) begin
        data_buf_d = data_buf_q;
        req_rdy_o = 0;
        uart8_in_buf_i = 0;
        uart8_data_val_i = 0;
        case (state_q)
            INIT: begin
                req_rdy_o = 1;
                if(req_val_i) begin
                    data_buf_d = data_i;
                    state_d = MSB_31_24;
                end else begin
                    data_buf_d = 0;
                    state_d = INIT;
                end
            end
            
            MSB_31_24: begin
                uart8_data_val_i = 1;
                if(uart8_data_rdy_o) begin
                    uart8_in_buf_i = data_buf_q[31:24];
                    state_d = MSB_23_16;
                end else begin
                    state_d = MSB_31_24;
                end
            end

            MSB_23_16: begin
                uart8_data_val_i = 1;
                if(uart8_data_rdy_o) begin
                    uart8_in_buf_i = data_buf_q[23:16];
                    state_d = MSB_15_8;
                end else begin
                    state_d = MSB_23_16;
                end
            end

            MSB_15_8: begin
                uart8_data_val_i = 1;
                if(uart8_data_rdy_o) begin
                    uart8_in_buf_i = data_buf_q[15:8];
                    state_d = MSB_7_0;
                end else begin
                    state_d = MSB_15_8;
                end
            end

            MSB_7_0: begin
                uart8_data_val_i = 1;
                if(uart8_data_rdy_o) begin
                    uart8_in_buf_i = data_buf_q[7:0];
                    state_d = INIT;
                end else begin
                    state_d = MSB_7_0;
                end
            end

            default: begin
                state_d = INIT;
            end
        endcase
        
    end

endmodule
