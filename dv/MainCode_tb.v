`timescale 1ns/1ps

module MainCode_tb();

// Testbench信号定义
reg CLK_50MHz;
reg rst_n;
reg StartStop;
reg ModeSel;
wire [6:0] HexMSBH;
wire [6:0] HexMSBL;
wire [6:0] HexLSBH;
wire [6:0] HexLSBL;
wire DOT;

// 实例化待测模块
MainCode uut (
    .CLK_50MHz(CLK_50MHz),
    .rst_n(rst_n),
    .StartStop(StartStop),
    .ModeSel(ModeSel),
    .HexMSBH(HexMSBH),
    .HexMSBL(HexMSBL),
    .HexLSBH(HexLSBH),
    .HexLSBL(HexLSBL),
    .DOT(DOT)
);

// 生成50MHz时钟（周期20ns）
initial begin
    CLK_50MHz = 0;
    forever #10 CLK_50MHz = ~CLK_50MHz;
end

// 仿真过程
initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, MainCode_tb);

    // 初始条件
    rst_n = 0;
    StartStop = 0;
    ModeSel = 0;  // Mode A（100Hz计数）
    repeat (10) @(posedge CLK_50MHz);

    rst_n = 1;    // 解除复位
    // 启动计数
    StartStop = 1; // 上升沿触发开始
    // 运行一段时间
    repeat (200) @(posedge CLK_50MHz);

    // 切换到Mode B（倒计时2分钟）
    ModeSel = 1;
    // 再次触发启动
    StartStop = 1;
    // 继续运行一段时间
    repeat (130) @(posedge CLK_50MHz);

    // 结束仿真
    $finish;
end

endmodule
