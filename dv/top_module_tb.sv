module top_module_tb
    import config_pkg::*;
    import dv_pkg::*;
    ;

top_module_runner top_module_runner ();

task automatic TLE_killer(input int tle_thres);
    $display("Simulation will terminate after %d cycles\n", tle_thres);
    top_module_runner.timeout_killer(tle_thres);
endtask

int val = 0;


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

    top_module_runner.send(0, 10);
    top_module_runner.send(0, 10);
    top_module_runner.send(0, 10);
    top_module_runner.send(0, 10);

    top_module_runner.send(1, 10);
    top_module_runner.send(1, 10);
    top_module_runner.send(1, 10);
    top_module_runner.send(1, 10);


    $display( "End simulation." );
    $finish;
end

endmodule
