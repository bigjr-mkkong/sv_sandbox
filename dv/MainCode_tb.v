`timescale 1ns/1ps

module MainCode_tb;

//====================================================
// 1. 参数区
//====================================================
parameter PERIOD = 10;    // 50 MHz 时钟周期 = 10 ns*2 = 20 ns
parameter FAST_K = 100;   // 缩放系数（原等待时间 / FAST_K）

//====================================================
// 2. 信号 & 接口（保持和 MainCode.v 一致）
//====================================================
reg        CLK_50MHz = 0;
reg        rst_n     = 0;
reg        StartStop = 0;
reg        ModeSel   = 0;

wire [6:0] HexMSBH;
wire [6:0] HexMSBL;
wire [6:0] HexLSBH;
wire [6:0] HexLSBL;
wire       DOT;

//====================================================
// 3. 产生 50 MHz 时钟
//====================================================
always #(PERIOD/2) CLK_50MHz = ~CLK_50MHz;

//====================================================
// 4. 实例化 DUT
//====================================================
MainCode uut (
    .CLK_50MHz  (CLK_50MHz),
    .rst_n      (rst_n),
    .StartStop  (StartStop),
    .ModeSel    (ModeSel),
    .HexMSBH    (HexMSBH),
    .HexMSBL    (HexMSBL),
    .HexLSBH    (HexLSBH),
    .HexLSBL    (HexLSBL),
    .DOT        (DOT)
);

//====================================================
// 5. 复位 & 激励序列 (全都除以 FAST_K 加速仿真)
//====================================================
initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, MainCode_tb);
    // —— 复位——
    rst_n = 0;
    repeat(10) @(posedge CLK_50MHz);
    rst_n = 1;

    ModeSel   = 1;  
    StartStop = 1;
    repeat(1000) @(posedge CLK_50MHz);
    StartStop = 0;      // 暂停

    $finish;
end

endmodule
