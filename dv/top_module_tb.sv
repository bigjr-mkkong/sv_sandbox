
module top_module_tb
    import config_pkg::*;
    import dv_pkg::*;
    ;

top_module_runner top_module_runner ();

initial begin
    $dumpfile( "dump.vcd" );
    $dumpvars(0);
    $display( "Begin simulation." );
    $urandom(100);
    $timeformat( -3, 3, "ms", 0);

    top_module_runner.reset();

    repeat (4) begin
        top_module_runner.tick_valid();
        top_module_runner.wait_output();
    end

    $display( "End simulation." );
    $finish;
end

endmodule
