import config_pkg::*;

module top_module_runner;

logic clk_i;
logic rst_ni;

localparam realtime ClockPeriod = 21ns; // 48mhz
localparam DATAW = 32;

logic rsp_val;
logic [DATAW-1: 0]rsp_data;
logic rsp_rdy;

logic uart0_rxd, uart0_txd;

initial begin
    clk_i = 0;
    forever begin
        #(ClockPeriod/2);
        clk_i = !clk_i;
    end
end


top_module #(
    .DATAW(DATAW)
    ) topmod_inst (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .rxd(uart0_rxd),
    .txd(uart0_txd)
);

task automatic tle_killer(int tle_thres);
    repeat(tle_thres) @(posedge clk_i);
    $display("Simulation timed out\n");
    $finish;
endtask;

task automatic reset;
    rst_ni = 0;
    repeat (10) @(posedge clk_i);
    rst_ni = 1;
endtask

task automatic tick_valid;
    rsp_val = 1;
    @(posedge clk_i);
    rsp_val = 0;
endtask

task automatic wait_output;
    while(!rsp_rdy);
    $info("read out: %h\n", rsp_data);
endtask

task automatic wait_end;
    repeat (2000) @(posedge clk_i);
endtask


endmodule
