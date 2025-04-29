module MainCode (

    input CLK_50MHz,         // 50MHz clock input
    input rst_n,             // Active-LOW reset signal
    input StartStop,         // A control signal to start and stop
    input ModeSel,           // A control signal to switch between two modes

    output [6:0] HexMSBH,    // MSB higher digit 7-Seg
    output [6:0] HexMSBL,    // MSB lower digit 7-Seg
    output [6:0] HexLSBH,    // LSB higher digit 7-Seg
    output [6:0] HexLSBL,    // LSB lower digit 7-Seg
    output DOT               // Flashing decimal signal
);

// 内部连线
wire clk_100Hz;
wire clk_1Hz;
wire [7:0] lsb_binary;
wire [7:0] msb_binary;

// 时钟分频器实例
ClockDivider clk_div_inst (
    .CLK_50MHz(CLK_50MHz),
    .rst_n(rst_n),
    .CLK_100Hz(clk_100Hz),
    .CLK_1Hz(clk_1Hz)
);

// 根据ModeSel选择不同的工作时钟
wire work_clk;
assign work_clk = (ModeSel == 0) ? clk_100Hz : clk_1Hz;

// 配置不同模式下的初值（重置时TimerCoreLogic使用）
wire [7:0] lsb_reset_val;
wire [7:0] msb_reset_val;

assign lsb_reset_val = (ModeSel == 0) ? 8'd0 : 8'd0;   // 两种模式LSB初值都是0
assign msb_reset_val = (ModeSel == 0) ? 8'd0 : 8'd2;   // Mode A=00, Mode B=02

// TimerCoreLogic实例
TimerCoreLogic timer_inst (
    .clk(work_clk),
    .rst_n(rst_n),
    .StartStop(StartStop),
    .LSBbinaryout(lsb_binary),
    .MSBbinaryout(msb_binary),
    .LSB_reset_val(lsb_reset_val),
    .MSB_reset_val(msb_reset_val)
);

// SevenSegEncoder实例
SevenSegEncoder display_encoder (
    .LSBBinary(lsb_binary),
    .MSBBinary(msb_binary),
    .ModeSel(ModeSel),
    .HexMSBH(HexMSBH),
    .HexMSBL(HexMSBL),
    .HexLSBH(HexLSBH),
    .HexLSBL(HexLSBL)
);

// DOT输出，小数点闪烁
assign DOT = clk_100Hz;

endmodule
