`timescale 1ns / 1ps

module top_module_tb;

    top_module_runner runner();

    import "DPI-C" function chandle ideal_mem_create();
    import "DPI-C" function void ideal_mem_destroy(input chandle handle);
    import "DPI-C" function void ideal_mem_reset(input chandle handle);
    import "DPI-C" function void ideal_mem_write(
        input chandle handle,
        input int unsigned addr,
        input bit [15:0] data
    );
    import "DPI-C" function void ideal_mem_read(
        input chandle handle,
        input int unsigned addr,
        output bit [15:0] data
    );

    chandle memory, other_memory;
    bit [15:0] payload, read_data;

    initial begin
        $dumpfile("build/sim/dump.fst");
        $dumpvars(0, top_module_tb);
        $display("Begin RTL simulation.");

        memory = ideal_mem_create();
        other_memory = ideal_mem_create();
        assert (memory != null && other_memory != null) else $fatal(1, "Memory allocation failed");
        ideal_mem_read(memory, 32'h0001_4000, read_data);
        assert (read_data == '0) else $fatal(1, "Unwritten memory must read zero");
        payload = 16'hABCD;
        ideal_mem_write(memory, 32'h0001_4001, payload);
        ideal_mem_read(memory, 32'h0001_4000, read_data);
        assert (read_data == payload) else $fatal(1, "Memory write/read or alignment failed");
        ideal_mem_read(memory, 32'h4000, read_data);
        assert (read_data == '0) else $fatal(1, "Memory address lost its upper bits");
        ideal_mem_read(other_memory, 32'h0001_4000, read_data);
        assert (read_data == '0) else $fatal(1, "Memory instances must be independent");
        ideal_mem_reset(memory);
        ideal_mem_read(memory, 32'h0001_4000, read_data);
        assert (read_data == '0) else $fatal(1, "Memory reset failed");
        ideal_mem_destroy(memory);
        ideal_mem_destroy(other_memory);
        $display("Ideal memory DPI checks passed.");

        runner.reset();
        runner.expect_uart_byte(8'h41);
        runner.expect_uart_byte(8'h42);

        $display("RTL simulation passed.");
        $finish;
    end

endmodule
