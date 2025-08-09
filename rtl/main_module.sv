module main_module
#(
    parameter DATAW = 8
) (
    input logic      clk_i,
    input logic      rst_ni,

{% if UART0.exist == True %}
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
{% endif %}
);

    logic [DATAW-1:0]data_r, data_n, data_buf;

    always @(posedge clk_i) begin
        if (~rst_ni) begin
            data_r <= 8'h41; // 'A'
        end else begin
            data_r <= data_n;
        end
    end

    always_comb begin
        m_axis_rx.tvalid = 1;
        data_buf = (data_r >= 8'h5a)?8'h41:data_r + 1;
        data_n = (m_axis_rx.tready)?data_buf:data_r;
    end

    always_comb begin
        m_axis_rx.tdata = data_r;
    end
endmodule
