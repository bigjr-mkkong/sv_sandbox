`timescale 1ns/1ps

module Reverser_tb();

// Testbench信号定义
reg [7:0] RevIn;
reg ModeSel;
wire [7:0] RevOut;

// 实例化待测模块
Reverser uut (
    .RevIn(RevIn),
    .ModeSel(ModeSel),
    .RevOut(RevOut)
);

// 测试过程
initial begin
    // 初始输入
    RevIn = 8'h00;    // 00
    ModeSel = 0;      // Normal mode
    #20;
    
    RevIn = 8'h23;    // 23
    ModeSel = 0;
    #20;
    
    RevIn = 8'h45;    // 45
    ModeSel = 0;
    #20;
    
    // 开始测试反转模式
    RevIn = 8'h23;    // 23 -> 76
    ModeSel = 1;      
    #20;
    
    RevIn = 8'h09;    // 09 -> 90
    ModeSel = 1;
    #20;
    
    RevIn = 8'h87;    // 87 -> 12
    ModeSel = 1;
    #20;

    // 结束仿真
    $stop;
end

endmodule
