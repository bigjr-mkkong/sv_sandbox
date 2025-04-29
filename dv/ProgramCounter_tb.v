`timescale 1ns/1ps

module ProgramCounter_tb();

// Testbench信号定义
reg clk;
reg reset;
reg load;
reg inc;
reg [7:0] ResetVal;
reg [7:0] LoadVal;
wire [7:0] PCoutput;

// 实例化待测模块
ProgramCounter uut (
    .clk(clk),
    .ResetVal(ResetVal),
    .LoadVal(LoadVal),
    .reset(reset),
    .load(load),
    .inc(inc),
    .PCoutput(PCoutput)
);

// 生成时钟信号（周期10ns，100MHz，够快方便测试）
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// 仿真过程
initial begin
    // 初始化
    reset = 0;
    load = 0;
    inc = 0;
    ResetVal = 8'd55;
    LoadVal = 8'd77;

    // 起始保持一段时间
    #20;

    // 测试reset
    reset = 1;
    #10;
    reset = 0;

    #20;

    // 测试load
    load = 1;
    #10;  // 在下一个时钟沿加载
    load = 0;

    #20;

    // 测试inc
    inc = 1;
    #100; // 连续增加几次
    inc = 0;

    #20;

    // 测试reset优先级（在load和inc活跃时触发reset）
    load = 1;
    inc = 1;
    #10;
    reset = 1;
    #10;
    reset = 0;
    load = 0;
    inc = 0;

    #50;

    // 结束仿真
    $stop;
end

endmodule
