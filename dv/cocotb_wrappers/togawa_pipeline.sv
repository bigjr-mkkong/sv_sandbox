`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
module togawa_pipeline_unit_test (
    input logic clk_i,
    input logic rst_ni,
    input logic run_i,
    input logic icache_req_rdy_i,
    input logic icache_valid_enable_i,
    input logic dcache_req_enable_i,
    input logic dcache_rsp_enable_i,

    // Preload either SRAM while the pipeline is held in reset; read back
    // through the same port after execution. Addresses are byte addresses.
    input logic mem_write_i,
    input logic mem_read_i,
    input logic mem_icache_i,
    input logic [16:0] mem_addr_i,
    input logic [15:0] mem_data_i,
    output logic [15:0] mem_read_data_o,

    output logic [15:0] pc_o,
    output logic icache_req_val_o,
    output logic icache_rdy_o,
    output logic dcache_req_val_o,
    output logic dcache_req_w,
    output logic [15:0] dcache_req_addr_o,
    output logic [15:0] dcache_req_data_o,
    output logic halt
);
    import "DPI-C" function chandle ideal_mem_create();
    import "DPI-C" function void ideal_mem_destroy(input chandle handle);
    import "DPI-C" function void ideal_mem_reset(input chandle handle);
    import "DPI-C" function void ideal_mem_write(
        input chandle handle, input int unsigned addr, input bit [15:0] data);
    import "DPI-C" function void ideal_mem_read(
        input chandle handle, input int unsigned addr, output bit [15:0] data);

    chandle icache, dcache;
    logic core_rst_ni;
    logic icache_val_i, dcache_req_rdy_i, dcache_rsp_val_i, dcache_rsp_rdy_o;
    bit [15:0] icache_inst_i, read_word;
    logic [15:0] dcache_rsp_data_i;
    logic data_pending_q, data_write_q;
    logic [15:0] data_addr_q, data_word_q;

    initial begin
        icache = ideal_mem_create();
        dcache = ideal_mem_create();
        assert (icache != null && dcache != null)
            else $fatal(1, "SRAM allocation failed");
    end

    final begin
        ideal_mem_destroy(icache);
        ideal_mem_destroy(dcache);
    end

    assign core_rst_ni = rst_ni && run_i;
    assign icache_val_i = core_rst_ni && icache_valid_enable_i;
    assign dcache_req_rdy_i = core_rst_ni && dcache_req_enable_i && !data_pending_q;
    assign dcache_rsp_val_i = core_rst_ni && data_pending_q && dcache_rsp_enable_i;

    always_comb begin
        icache_inst_i = 16'd0;
        if (core_rst_ni)
            ideal_mem_read(icache, {15'd0, pc_o, 1'b0}, icache_inst_i);
    end

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            ideal_mem_reset(icache);
            ideal_mem_reset(dcache);
            data_pending_q <= 1'b0;
            data_write_q <= 1'b0;
            data_addr_q <= 16'd0;
            data_word_q <= 16'd0;
            dcache_rsp_data_i <= 16'd0;
            mem_read_data_o <= 16'd0;
        end else begin
            if (!run_i) begin
                data_pending_q <= 1'b0;
            end else begin
                if (dcache_req_val_o && dcache_req_rdy_i) begin
                    data_pending_q <= 1'b1;
                    data_write_q <= dcache_req_w;
                    data_addr_q <= dcache_req_addr_o;
                    data_word_q <= dcache_req_data_o;
                    ideal_mem_read(dcache, {16'd0, dcache_req_addr_o}, read_word);
                    dcache_rsp_data_i <= read_word;
                end
                if (dcache_rsp_val_i && dcache_rsp_rdy_o) begin
                    if (data_write_q)
                        ideal_mem_write(dcache, {16'd0, data_addr_q}, data_word_q);
                    data_pending_q <= 1'b0;
                end
            end

            if (mem_write_i) begin
                assert ((!run_i || halt) && !mem_addr_i[0])
                    else $fatal(1, "SRAM preload needs a stopped CPU and aligned address");
                ideal_mem_write(mem_icache_i ? icache : dcache,
                    {15'd0, mem_addr_i}, mem_data_i);
            end
            if (mem_read_i) begin
                ideal_mem_read(mem_icache_i ? icache : dcache,
                    {15'd0, mem_addr_i}, read_word);
                mem_read_data_o <= read_word;
            end
        end
    end

    togawa_pipeline pipeline (
        .clk_i(clk_i),
        .rst_ni(core_rst_ni),
        .icache_req_val_o(icache_req_val_o),
        .pc_o(pc_o),
        .icache_req_rdy_i(icache_req_rdy_i),
        .icache_val_i(icache_val_i),
        .icache_inst_i(icache_inst_i),
        .icache_rdy_o(icache_rdy_o),
        .dcache_req_val_o(dcache_req_val_o),
        .dcache_req_rdy_i(dcache_req_rdy_i),
        .dcache_req_w(dcache_req_w),
        .dcache_req_addr_o(dcache_req_addr_o),
        .dcache_req_data_o(dcache_req_data_o),
        .dcache_rsp_val_i(dcache_rsp_val_i),
        .dcache_rsp_data_i(dcache_rsp_data_i),
        .dcache_rsp_rdy_o(dcache_rsp_rdy_o),
        .halt(halt)
    );
endmodule
/* verilator lint_on DECLFILENAME */
