module top_module
    import config_pkg::*;
#(
    parameter DATAW = 32,
    parameter PRE_W = 16
) (
    input  logic         clk_i,
    input  logic         rst_ni,

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
    //uart interface
    input  wire logic               rxd,
    output wire logic               txd,
    //uart status
    output wire logic               tx_busy,
    output wire logic               rx_busy,
    output wire logic               rx_overrun_error,
    output wire logic               rx_frame_error,
    //uart configuration
    input  wire logic [PRE_W-1:0]   prescale
//====================================================


    
);



endmodule
