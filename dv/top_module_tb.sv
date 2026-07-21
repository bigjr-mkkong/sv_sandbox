`timescale 1ns / 1ps

module top_module_tb;

    top_module_runner runner();

    initial begin
        $dumpfile("build/sim/dump.fst");
        $dumpvars(0, top_module_tb);
        $display("Begin RTL simulation.");

        runner.reset();
        runner.expect_uart_byte(8'h41);
        runner.expect_uart_byte(8'h42);

        $display("RTL simulation passed.");
        $finish;
    end

endmodule
