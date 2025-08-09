module top_module
    import config_pkg::*;
#(
    parameter DATAW = 32
) (
    input  logic         clk_i,
    input  logic         rst_ni,

    input  wire logic               rxd,
    output wire logic               txd
    
);

{% if UART0.exist == True %}

    localparam PRE_VAL = {{UART0.PRE_W}}'d{{UART0.PRE_VAL}};

    logic uart0_rxd, uart0_txd, uart0_tx_busy, uart0_rx_busy, uart0_rx_overrun_error, uart0_rx_frame_error;
    taxi_axis_if #(.DATA_W({{UART0.AXI_DATAW}})) uart0_m_axis_rx();
    taxi_axis_if #(.DATA_W({{UART0.AXI_DATAW}})) uart0_s_axis_tx();

    logic [{{UART0.PRE_W}}-1: 0]uart0_prescale;

    assign uart0_prescale = PRE_VAL;

    taxi_uart #(
        .PRE_W({{UART0.PRE_W}})
    ) 
    taxi_uart_inst0 (
        .clk(clk_i)
        ,.rst(~rst_ni)
        ,.s_axis_tx(uart0_m_axis_rx)
        ,.m_axis_rx(uart0_s_axis_tx)
        ,.rxd(uart0_rxd)
        ,.txd(uart0_txd)
        ,.tx_busy(uart0_tx_busy)
        ,.rx_busy(uart0_rx_busy)
        ,.rx_overrun_error(uart0_rx_overrun_error)
        ,.rx_frame_error(uart0_rx_frame_error)
        ,.prescale(uart0_prescale)
    );

    assign uart0_rxd = rxd;
    assign txd = uart0_txd;

{% endif %}

main_module #(
    .DATAW(8)
) main_module_inst (
    .clk_i(clk_i)
    ,.rst_ni(rst_ni)

{% if UART0.exist == True %}
    ,.s_axis_tx(uart0_s_axis_tx)
    ,.m_axis_rx(uart0_m_axis_rx)

    ,.tx_busy(uart0_tx_busy)
    ,.rx_busy(uart0_rx_busy)
    ,.rx_overrun_error(uart0_rx_overrun_error)
    ,.rx_frame_error(uart0_rx_frame_error)
{% endif %}

);

endmodule
