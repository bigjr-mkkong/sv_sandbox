`timescale 1ns/1ps

module SevenSegEncoder_tb();

// Testbench信号定义
reg [7:0] LSBBinary;
reg [7:0] MSBBinary;
reg ModeSel;
wire [6:0] HexMSBH;
wire [6:0] HexMSBL;
wire [6:0] HexLSBH;
wire [6:0] HexLSBL;

// 实例化待测模块
SevenSegEncoder uut (
    .LSBBinary(LSBBinary),
    .MSBBinary(MSBBinary),
    .ModeSel(ModeSel),
    .HexMSBH(HexMSBH),
    .HexMSBL(HexMSBL),
    .HexLSBH(HexLSBH),
    .HexLSBL(HexLSBL)
);

// 测试过程
initial begin
    // 初始化
    LSBBinary = 8'h00;   // 00
    MSBBinary = 8'h00;   // 00
    ModeSel = 0;         // 正常模式
    #20;

    LSBBinary = 8'h45;   // 45
    MSBBinary = 8'h23;   // 23
    ModeSel = 0;
    #20;

    // 切换到反转模式
    LSBBinary = 8'h45;   // 45 -> 54
    MSBBinary = 8'h23;   // 23 -> 76
    ModeSel = 1;
    #20;

    // 再换一组
    LSBBinary = 8'h09;   // 09
    MSBBinary = 8'h87;   // 87
    ModeSel = 1;
    #20;

    // 再回到正常模式
    LSBBinary = 8'h12;   // 12
    MSBBinary = 8'h34;   // 34
    ModeSel = 0;
    #20;

    // 结束仿真
    $stop;
end

endmodule
