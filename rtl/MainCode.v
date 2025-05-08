//============================================================
//  MainCode.v   (2025‑05‑06 重新整理：ModeSel 直接驱动 TimerCoreLogic)
//============================================================
module MainCode ( 
    input  CLK_50MHz,   // 50 MHz 系统时钟
    input  rst_n,       // 低有效全局复位
    input  StartStop,   // 翻转运行/暂停
    input  ModeSel,     // 0=普通计数  1=倒计时 (02:00)

    output [6:0] HexMSBH,  // MSB 高位 7‑Seg
    output [6:0] HexMSBL,  // MSB 低位 7‑Seg
    output [6:0] HexLSBH,  // LSB 高位 7‑Seg
    output [6:0] HexLSBL,  // LSB 低位 7‑Seg
    output        DOT      // 闪烁小数点
);

    //------------------------
    // 1. 时钟分频 (50 MHz → 100 Hz / 1 Hz)
    //------------------------
    wire clk_100Hz;
    wire clk_1Hz;

    ClockDivider clk_div_inst (
        .CLK_50MHz (CLK_50MHz),
        .rst_n     (rst_n),
        .CLK_100Hz (clk_100Hz),
        .CLK_1Hz   (clk_1Hz)
    );

    //------------------------
    // 2. 根据 ModeSel 选择工作时钟
    //------------------------
    // wire work_clk = (ModeSel == 1'b0) ? clk_100Hz : clk_1Hz;  // A=100 Hz，B=1 Hz
    wire work_clk = CLK_50MHz;

    //------------------------
    // 3. 计数核心
    //------------------------
    wire [7:0] lsb_binary;
    wire [7:0] msb_binary;

    TimerCoreLogic timer_inst (
        .clk         (work_clk),
        .rst_n       (rst_n),
        .StartStop   (StartStop),
        .ModeSel     (ModeSel),     // ★ 直接传入 ★
        .LSBbinaryout(lsb_binary),
        .MSBbinaryout(msb_binary)
    );

    //------------------------
    // 4. 七段译码显示
    //------------------------
    SevenSegEncoder display_encoder (
        .LSBBinary (lsb_binary),
        .MSBBinary (msb_binary),
        .ModeSel   (ModeSel),
        .HexMSBH   (HexMSBH),
        .HexMSBL   (HexMSBL),
        .HexLSBH   (HexLSBH),
        .HexLSBL   (HexLSBL)
    );

    //------------------------
    // 5. DOT 闪烁：100 Hz 时钟直接作分频
    //------------------------
    assign DOT = clk_100Hz;

endmodule
