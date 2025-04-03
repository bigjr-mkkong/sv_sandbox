module icebreaker#(
    parameter UART_DATA_WIDTH = 8,
    parameter DATAW = 32
) (
    input  wire CLK,
    input  wire BTN_N,
    input  wire RX,
    output wire TX,
    output wire LED_GRN_N,
    output wire P1A7
);

assign LED_GRN_N = BTN_N;
assign P1A7 = BTN_N;

// icepll -i 12 -o 50
// F_PLLIN:    12.000 MHz (given)
// F_PLLOUT:   50.000 MHz (requested)
// F_PLLOUT:   50.250 MHz (achieved)

// FEEDBACK: SIMPLE
// F_PFD:   12.000 MHz
// F_VCO:  804.000 MHz

// DIVR:  0 (4'b0000)
// DIVF: 66 (7'b1000010)
// DIVQ:  4 (3'b100)

// FILTER_RANGE: 1 (3'b001)

// wire clk_50250 = CLK;
wire clk_12 = CLK;
wire clk_50250;
SB_PLL40_PAD #(
    .FEEDBACK_PATH("SIMPLE"),
    .DIVR(4'b0000),
    .DIVF(7'b1000010),
    .DIVQ(3'b100),
    .FILTER_RANGE(3'b001)
) pll (
    .LOCK(),
    .RESETB(1'b1),
    .BYPASS(1'b0),
    .PACKAGEPIN(clk_12),
    .PLLOUTGLOBAL(clk_50250)
);

    reg [DATAW-1: 0]uart_buf_o;
    wire uart_rsp_rdy_i;
    wire uart_rsp_val_o;
    // uart_tx uart (
    //     .clk(clk_50250),
    //     .rst_n(BTN_N),
    //     .data_val_i(uart_rsp_val_o),
    //     .data_in(uart_buf_o),
    //     .data_rdy_o(uart_rsp_rdy_i),
    //     .tx(TX)
    // );
    // uart_tx uart (
    //     .clk(clk_50250),
    //     .rst_n(BTN_N),
    //     .data_val_i(1),
    //     .data_in(8'hab),
    //     .data_rdy_o(_),
    //     .tx(TX)
    // );

    // uart_tx32 uart (
    //     .clk_i(clk_50250),
    //     .rst_ni(BTN_N),
    //     .req_val_i(uart_rsp_val_o),
    //     .data_i(uart_buf_o),
    //     .req_rdy_o(uart_rsp_rdy_i),
    //     .tx(TX)
    // );

    uart_tx32 uart32 (
        .clk_i(clk_50250),
        .rst_ni(BTN_N),
        .req_val_i(1),
        .data_i(32'hdeadbeef),
        .req_rdy_o(_),
        .tx(TX)
    );

    // top_module dut (
    //     .clk_i(clk_50250),
    //     .rst_ni(BTN_N),
    //     .uart_rsp_rdy_i(uart_rsp_rdy_i),
    //     .uart_rsp_data_o(uart_buf_o),
    //     .uart_rsp_val_o(uart_rsp_val_o)
    // );

endmodule
