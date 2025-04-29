// ClockDivider模块的Testbench
// 功能：验证ClockDivider模块是否正确分频出100Hz和1Hz时钟

`timescale 1ns/1ps   // 定义仿真时间单位和精度（1ns单位，1ps精度）

module ClockDivider_tb();

// Testbench中的信号定义
reg CLK_50MHz;       // 测试用的50MHz输入时钟（reg型）
reg rst_n;           // 测试用的低有效复位信号
wire CLK_100Hz;      // 连接到被测模块的100Hz输出
wire CLK_1Hz;        // 连接到被测模块的1Hz输出

// 实例化待测模块ClockDivider（uut = unit under test）
ClockDivider uut (
    .CLK_50MHz(CLK_50MHz),
    .rst_n(rst_n),
    .CLK_100Hz(CLK_100Hz),
    .CLK_1Hz(CLK_1Hz)
);

// 生成50MHz时钟信号：周期20ns（50MHz）
// 用 forever+延时 方式生成
initial begin
    CLK_50MHz = 0;
    forever #10 CLK_50MHz = ~CLK_50MHz; // 每10ns翻转一次，形成20ns周期
end

// 主仿真流程
initial begin
    // 初始时复位信号拉低
    rst_n = 0;
    #100;             // 保持复位状态100ns
    rst_n = 1;        // 解除复位，模块开始正常运行

    // 等待一段时间观察分频结果
    #1_000_000_000;       // 仿真1000us（即1ms），可以观察到100Hz和1Hz翻转效果

    // 停止仿真（ModelSim中可以手动查看波形）
    $stop;
end

endmodule
