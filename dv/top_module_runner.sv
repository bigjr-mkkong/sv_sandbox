`timescale 1ns / 1ps

module top_module_runner;

    localparam realtime CLOCK_PERIOD = 1s / config_pkg::CLOCK_FREQUENCY_HZ;

    logic clk_i = 1'b0;
    logic rst_ni;
    logic uart_rxd_i;
    logic uart_txd_o;

    always #(CLOCK_PERIOD / 2) clk_i = !clk_i;

    top_module dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .rxd_i(uart_rxd_i),
        .txd_o(uart_txd_o)
    );

    task automatic reset;
        uart_rxd_i = 1'b1;
        rst_ni = 1'b0;
        repeat (10) @(posedge clk_i);
        rst_ni = 1'b1;
    endtask

    task automatic expect_uart_byte(input logic [dv_pkg::UART_DATA_BITS-1:0] expected);
        @(negedge uart_txd_o);
        repeat (int'(dut.UART_PRESCALE) / 2) @(posedge clk_i);
        assert (uart_txd_o == 1'b0) else $error("Invalid UART start bit");

        for (int bit_index = 0; bit_index < dv_pkg::UART_DATA_BITS; bit_index++) begin
            repeat (int'(dut.UART_PRESCALE)) @(posedge clk_i);
            assert (uart_txd_o == expected[bit_index])
                else $error("UART bit %0d mismatch", bit_index);
        end

        repeat (int'(dut.UART_PRESCALE)) @(posedge clk_i);
        assert (uart_txd_o == 1'b1) else $error("Invalid UART stop bit");
    endtask

endmodule
