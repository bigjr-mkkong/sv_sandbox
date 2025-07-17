
module top_module_tb
    import config_pkg::*;
    import dv_pkg::*;
    ;

top_module_runner top_module_runner ();

int val = 0;

initial begin
    $dumpfile( "dump.vcd" );
    $dumpvars(0);
    $display( "Begin simulation." );
    $urandom(100);
    $timeformat( -3, 3, "ms", 0);

    top_module_runner.reset();

    // repeat (2) begin
    //     top_module_runner.send(0, 0, 0);
    // end

    top_module_runner.send(1, 0, 12);
    top_module_runner.send(1, 0, 15);
    top_module_runner.send(0, 0, 7);

    $display( "End simulation." );
    $finish;
end

endmodule
