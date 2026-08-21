`timescale 1ns / 1ps

module top_module (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic rxd_i,
    output logic txd_o
);

    main_module #(
        .ADDR_WIDTH(config_pkg::ADDR_WIDTH),
        .DATA_WIDTH(config_pkg::DATA_WIDTH)
    ) main_module_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni)
    );

{% if UART0 is defined and UART0.ENABLE %}
    taxi_axis_if #(.DATA_W({{ UART0.AXI_DATAW }})) uart_rx_axis();
    taxi_axis_if #(.DATA_W({{ UART0.AXI_DATAW }})) uart_tx_axis();

    localparam logic [{{ UART0.PRE_W }}-1:0] UART_PRESCALE =
        {{ UART0.PRE_W }}'((config_pkg::CLOCK_FREQUENCY_HZ
            + {{ UART0.BAUD }} / 2) / {{ UART0.BAUD }});

    {{ UART0.module_name }} #(
        .PRE_W({{ UART0.PRE_W }})
    ) {{UART0.module_name + "_inst"}} (
        .clk(clk_i),
        .rst(!rst_ni),
        .s_axis_tx(uart_tx_axis),
        .m_axis_rx(uart_rx_axis),
        .rxd(rxd_i),
        .txd(txd_o),
        .tx_busy(),
        .rx_busy(),
        .rx_overrun_error(),
        .rx_frame_error(),
        .prescale(UART_PRESCALE)
    );

    // The cache-only example does not currently produce UART traffic.
    assign uart_tx_axis.tdata = '0;
    assign uart_tx_axis.tvalid = 1'b0;
    assign uart_rx_axis.tready = 1'b1;
{% else %}
    // Keep the UART output in its idle state when this instance is disabled.
    assign txd_o = 1'b1;

    // Consume the otherwise unused receive pin for lint purposes.
    wire _unused_ok = &{1'b0, rxd_i};
{% endif %}

endmodule
