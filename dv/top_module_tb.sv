
module top_module_tb
    import config_pkg::*;
    import dv_pkg::*;
    ;

top_module_runner top_module_runner ();

task automatic TLE_killer(int thres);
    $display("Spawned tle killer, simulation will end in %d cycls\n", thres);
    top_module_runner.tle_killer(thres);
endtask;

initial begin
    $dumpfile( "dump.vcd" );
    $dumpvars(0);
    $display( "Begin simulation." );
    $urandom(100);
    $timeformat( -3, 3, "ms", 0);

    top_module_runner.reset();

    fork
        begin
            TLE_killer(100);
        end
    join_none

    top_module_runner.wait_end();
    // repeat (4) begin
    //     top_module_runner.tick_valid();
    //     top_module_runner.wait_output();
    // end

    $display( "End simulation." );
    $finish;
end

endmodule
