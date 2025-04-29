`timescale 1ns/1ps

module TimerCoreLogic_tb();

// 测试信号定义
reg clk;
reg rst_n;
reg StartStop;
reg [7:0] LSB_reset_val;
reg [7:0] MSB_reset_val;
wire [7:0] LSBbinaryout;
wire [7:0] MSBbinaryout;

// 实例化待测模块
TimerCoreLogic uut (
    .clk(clk),
    .rst_n(rst_n),
    .StartStop(StartStop),
    .LSBbinaryout(LSBbinaryout),
    .MSBbinaryout(MSBbinaryout),
    .LSB_reset_val(LSB_reset_val),
    .MSB_reset_val(MSB_reset_val)
);

// 生成模拟时钟（比如 10MHz，周期100ns，便于仿真观察）
initial begin
    clk = 0;
    forever #50 clk = ~clk; // 100ns周期 = 10MHz
end

// 仿真过程
initial begin
    // 初始状态
    rst_n = 0;
    StartStop = 0;
    LSB_reset_val = 8'd0;
    MSB_reset_val = 8'd2; // 比如模拟 Mode B（02:00）

    #200;       // 复位一段时间
    rst_n = 1;  // 解除复位

    #200;       // 等待稳定
    // StartStop按键触发 -> 开始计数
    press_StartStop();

    #5000;      // 运行一段时间

    // 再次StartStop按键触发 -> 暂停
    press_StartStop();

    #3000;      // 暂停期间观察计数器是否停止

    // 再次StartStop按键触发 -> 继续计数
    press_StartStop();

    #5000;      // 再次运行

    // 最后复位
    rst_n = 0;
    #200;
    rst_n = 1;

    #2000;      // 观察复位后回到初始值

    $stop;
end

// 子程序：模拟按一下StartStop按钮（上升沿触发）
task press_StartStop;
begin
    StartStop = 1;
    #100;
    StartStop = 0;
end
endtask

endmodule
