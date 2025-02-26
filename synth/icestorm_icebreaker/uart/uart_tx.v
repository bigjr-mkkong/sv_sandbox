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
