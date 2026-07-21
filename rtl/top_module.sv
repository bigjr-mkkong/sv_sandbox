`timescale 1ns / 1ps

module top_module (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic rxd_i,
    output logic txd_o
);

    logic [config_pkg::MAIN_DATA_WIDTH-1:0] main_tx_tdata_o;
    logic                                   main_tx_tvalid_o;
    logic                                   main_tx_tready_i;

    main_module #(
        .DATA_WIDTH(config_pkg::MAIN_DATA_WIDTH)
    ) main_module_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .m_axis_tx_tdata_o(main_tx_tdata_o),
        .m_axis_tx_tvalid_o(main_tx_tvalid_o),
        .m_axis_tx_tready_i(main_tx_tready_i)
    );

{% if UART0.ENABLE %}
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

    assign uart_tx_axis.tdata = {{ UART0.AXI_DATAW }}'(main_tx_tdata_o);
    assign uart_tx_axis.tvalid = main_tx_tvalid_o;
    assign main_tx_tready_i = uart_tx_axis.tready;
    assign uart_rx_axis.tready = 1'b1;
{% else %}
    // Keep the UART output in its idle state when this instance is disabled.
    assign txd_o = 1'b1;

    // An absent transport applies backpressure so the main retains its
    // current output instead of silently discarding transfers.
    assign main_tx_tready_i = 1'b0;

    // Preserve the same public interface for board wrappers and consume the
    // disconnected transport signals for lint purposes.
    wire _unused_ok = &{1'b0, rxd_i, main_tx_tdata_o, main_tx_tvalid_o};
{% endif %}

endmodule
