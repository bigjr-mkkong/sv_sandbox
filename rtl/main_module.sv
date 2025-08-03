module main_module
#(
    parameter DATAW = 32
) (
    input logic      clk_i,
    input logic      rst_ni,

// _   _   _    ____ _____ 
//| | | | / \  |  _ \_   _|
//| | | |/ _ \ | |_) || |  
//| |_| / ___ \|  _ < | |  
// \___/_/   \_\_| \_\|_|  
//----------------------------------------------------
    //output to uart
    taxi_axis_if.src                m_axis_rx,
    //input from uart
    taxi_axis_if.snk                s_axis_tx,
    //uart state
    input wire logic               tx_busy,
    input wire logic               rx_busy,
    input wire logic               rx_overrun_error,
    input wire logic               rx_frame_error
//====================================================
);

assign m_axis_rx.tdata = 32'd114514;
assign m_axis_rx.tvalid = 1;

endmodule
