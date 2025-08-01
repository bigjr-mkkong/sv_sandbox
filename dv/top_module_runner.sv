import config_pkg::*;

module top_module_runner;

logic clk_i;
logic rst_ni;

localparam realtime ClockPeriod = 6ms;
localparam DATAW = 32;

logic rsp_val;
logic [DATAW-1: 0]rsp_data;
logic rsp_rdy;

logic uart0_rxd, uart0_txd, uart0_tx_busy, uart0_rx_busy, uart0_rx_overrun_error, uart0_rx_frame_error, uart0_prescale;

initial begin
    clk_i = 0;
    forever begin
        #(ClockPeriod/2);
        clk_i = !clk_i;
    end
end

taxi_axis_if #(.DATA_W(32)) uart0_m_axis_rx();
taxi_axis_if #(.DATA_W(32)) uart0_s_axis_tx();

taxi_uart #(
    .PRE_W(32)
) 
taxi_uart_inst0 (
    .clk(clk_i),
    .rst(rst_ni),
    .s_axis_tx(uart0_s_axis_tx),
    .m_axis_rx(uart0_m_axis_rx),
    .rxd(uart0_rxd),
    .txd(uart0_txd),
    .tx_busy(uart0_tx_busy),
    .rx_busy(uart0_rx_busy),
    .rx_overrun_error(uart0_rx_overrun_error),
    .rx_frame_error(uart0_rx_frame_error),
    .prescale(uart0_prescale)
);

top_module #(
    .DATAW(DATAW)
    ) topmod_inst (
    .clk_i,
    .rst_ni,

    .s_axis_tx(uart0_s_axis_tx),
    .m_axis_rx(uart0_m_axis_rx),
    .rxd(uart0_rxd),
    .txd(uart0_txd),

    .tx_busy(uart0_tx_busy),
    .rx_busy(uart0_rx_busy),
    .rx_overrun_error(uart0_rx_overrun_error),
    .rx_frame_error(uart0_rx_frame_error),
    .prescale(uart0_prescale)
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
    repeat (100) @(posedge clk_i);
endtask


endmodule
