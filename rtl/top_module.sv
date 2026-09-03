`timescale 1ns / 1ps

module top_module (
    input  logic clk_i,
{% if RENDER_OPTION.SYNTH %}
    input  logic                          cache0_req_val_i,
    input  logic [config_pkg::ADDR_WIDTH-1:0] cache0_req_addr_i,
    input  logic [config_pkg::DATA_WIDTH-1:0] cache0_req_data_i,
    input  logic                          cache0_req_is_write_i,
    output logic                          cache0_req_rdy_o,
    output logic                          cache0_rsp_val_o,
    output logic [config_pkg::DATA_WIDTH-1:0] cache0_rsp_data_o,
    input  logic                          cache0_rsp_rdy_i,

    input  logic                          cache1_req_val_i,
    input  logic [config_pkg::ADDR_WIDTH-1:0] cache1_req_addr_i,
    input  logic [config_pkg::DATA_WIDTH-1:0] cache1_req_data_i,
    input  logic                          cache1_req_is_write_i,
    output logic                          cache1_req_rdy_o,
    output logic                          cache1_rsp_val_o,
    output logic [config_pkg::DATA_WIDTH-1:0] cache1_rsp_data_o,
    input  logic                          cache1_rsp_rdy_i,
{% endif %}
{% if UART0 is defined and UART0.ENABLE %}
    input  logic rxd_i,
    output logic txd_o,
{% endif %}
    input  logic rst_ni
);

    main_module #(
        .ADDR_WIDTH(config_pkg::ADDR_WIDTH),
        .DATA_WIDTH(config_pkg::DATA_WIDTH)
    ) main_module_inst (
        .clk_i(clk_i),
{% if RENDER_OPTION.SYNTH %}
        .cache0_req_val_i(cache0_req_val_i),
        .cache0_req_addr_i(cache0_req_addr_i),
        .cache0_req_data_i(cache0_req_data_i),
        .cache0_req_is_write_i(cache0_req_is_write_i),
        .cache0_req_rdy_o(cache0_req_rdy_o),
        .cache0_rsp_val_o(cache0_rsp_val_o),
        .cache0_rsp_data_o(cache0_rsp_data_o),
        .cache0_rsp_rdy_i(cache0_rsp_rdy_i),
        .cache1_req_val_i(cache1_req_val_i),
        .cache1_req_addr_i(cache1_req_addr_i),
        .cache1_req_data_i(cache1_req_data_i),
        .cache1_req_is_write_i(cache1_req_is_write_i),
        .cache1_req_rdy_o(cache1_req_rdy_o),
        .cache1_rsp_val_o(cache1_rsp_val_o),
        .cache1_rsp_data_o(cache1_rsp_data_o),
        .cache1_rsp_rdy_i(cache1_rsp_rdy_i),
{% endif %}
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
    // // Keep the UART output in its idle state when this instance is disabled.
    // assign txd_o = 1'b1;

    // // Consume the otherwise unused receive pin for lint purposes.
    // wire _unused_ok = &{1'b0, rxd_i};
{% endif %}

endmodule

{% if RENDER_OPTION.SYNTH %}
/*
 * STA-only boundary wrapper. Input flops drive top_module and output flops
 * capture its responses, giving timing analysis register-to-register paths
 * across every externally visible cache channel.
 */
module timing_top (
    input  logic                             clk_i,
    input  logic                             rst_ni,
    input  logic                             cache0_req_val_i,
    input  logic [config_pkg::ADDR_WIDTH-1:0] cache0_req_addr_i,
    input  logic [config_pkg::DATA_WIDTH-1:0] cache0_req_data_i,
    input  logic                             cache0_req_is_write_i,
    output logic                             cache0_req_rdy_o,
    output logic                             cache0_rsp_val_o,
    output logic [config_pkg::DATA_WIDTH-1:0] cache0_rsp_data_o,
    input  logic                             cache0_rsp_rdy_i,

    input  logic                             cache1_req_val_i,
    input  logic [config_pkg::ADDR_WIDTH-1:0] cache1_req_addr_i,
    input  logic [config_pkg::DATA_WIDTH-1:0] cache1_req_data_i,
    input  logic                             cache1_req_is_write_i,
    output logic                             cache1_req_rdy_o,
    output logic                             cache1_rsp_val_o,
    output logic [config_pkg::DATA_WIDTH-1:0] cache1_rsp_data_o,
    input  logic                             cache1_rsp_rdy_i
);

    logic                              cache0_req_val_q;
    logic [config_pkg::ADDR_WIDTH-1:0] cache0_req_addr_q;
    logic [config_pkg::DATA_WIDTH-1:0] cache0_req_data_q;
    logic                              cache0_req_is_write_q;
    logic                              cache0_rsp_rdy_q;
    logic                              cache0_req_rdy;
    logic                              cache0_rsp_val;
    logic [config_pkg::DATA_WIDTH-1:0] cache0_rsp_data;
    logic                              cache0_req_rdy_q;
    logic                              cache0_rsp_val_q;
    logic [config_pkg::DATA_WIDTH-1:0] cache0_rsp_data_q;

    logic                              cache1_req_val_q;
    logic [config_pkg::ADDR_WIDTH-1:0] cache1_req_addr_q;
    logic [config_pkg::DATA_WIDTH-1:0] cache1_req_data_q;
    logic                              cache1_req_is_write_q;
    logic                              cache1_rsp_rdy_q;
    logic                              cache1_req_rdy;
    logic                              cache1_rsp_val;
    logic [config_pkg::DATA_WIDTH-1:0] cache1_rsp_data;
    logic                              cache1_req_rdy_q;
    logic                              cache1_rsp_val_q;
    logic [config_pkg::DATA_WIDTH-1:0] cache1_rsp_data_q;

    always_ff @(posedge clk_i) begin
        cache0_req_val_q <= cache0_req_val_i;
        cache0_req_addr_q <= cache0_req_addr_i;
        cache0_req_data_q <= cache0_req_data_i;
        cache0_req_is_write_q <= cache0_req_is_write_i;
        cache0_rsp_rdy_q <= cache0_rsp_rdy_i;

        cache1_req_val_q <= cache1_req_val_i;
        cache1_req_addr_q <= cache1_req_addr_i;
        cache1_req_data_q <= cache1_req_data_i;
        cache1_req_is_write_q <= cache1_req_is_write_i;
        cache1_rsp_rdy_q <= cache1_rsp_rdy_i;
    end

    top_module timed_dut (
        .clk_i(clk_i),
        .cache0_req_val_i(cache0_req_val_q),
        .cache0_req_addr_i(cache0_req_addr_q),
        .cache0_req_data_i(cache0_req_data_q),
        .cache0_req_is_write_i(cache0_req_is_write_q),
        .cache0_req_rdy_o(cache0_req_rdy),
        .cache0_rsp_val_o(cache0_rsp_val),
        .cache0_rsp_data_o(cache0_rsp_data),
        .cache0_rsp_rdy_i(cache0_rsp_rdy_q),
        .cache1_req_val_i(cache1_req_val_q),
        .cache1_req_addr_i(cache1_req_addr_q),
        .cache1_req_data_i(cache1_req_data_q),
        .cache1_req_is_write_i(cache1_req_is_write_q),
        .cache1_req_rdy_o(cache1_req_rdy),
        .cache1_rsp_val_o(cache1_rsp_val),
        .cache1_rsp_data_o(cache1_rsp_data),
        .cache1_rsp_rdy_i(cache1_rsp_rdy_q),
{% if UART0 is defined and UART0.ENABLE %}
        .rxd_i(1'b1),
        .txd_o(),
{% endif %}
        .rst_ni(rst_ni)
    );

    always_ff @(posedge clk_i) begin
        cache0_req_rdy_q <= cache0_req_rdy;
        cache0_rsp_val_q <= cache0_rsp_val;
        cache0_rsp_data_q <= cache0_rsp_data;
        cache1_req_rdy_q <= cache1_req_rdy;
        cache1_rsp_val_q <= cache1_rsp_val;
        cache1_rsp_data_q <= cache1_rsp_data;
    end

    assign cache0_req_rdy_o = cache0_req_rdy_q;
    assign cache0_rsp_val_o = cache0_rsp_val_q;
    assign cache0_rsp_data_o = cache0_rsp_data_q;
    assign cache1_req_rdy_o = cache1_req_rdy_q;
    assign cache1_rsp_val_o = cache1_rsp_val_q;
    assign cache1_rsp_data_o = cache1_rsp_data_q;

endmodule
{% endif %}
