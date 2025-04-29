// ClockDivider模块
// 功能：将50MHz输入时钟分频为100Hz和1Hz输出
// 注意：接口必须保持不变，内部逻辑完成分频功能

module ClockDivider (

    input CLK_50MHz,         // 50MHz时钟输入（来自FPGA板）
    input rst_n,             // 低电平有效的复位信号

    output reg CLK_100Hz,    // 分频输出的100Hz时钟
    output reg CLK_1Hz       // 分频输出的1Hz时钟

);

// 定义内部寄存器用于计数
reg [31:0] counter_100Hz;
reg [31:0] counter_1Hz;

// 定义分频系数参数
// 50MHz -> 100Hz 需要除以 50_000_000 / (2*100) = 250,000
parameter DIVISOR_100Hz = 250_000;     

// 50MHz -> 1Hz 需要除以 50_000_000 / (2*1) = 25,000,000
parameter DIVISOR_1Hz   = 25_000_000;

// 使用同步时序逻辑：在50MHz时钟上升沿或rst_n下降沿时触发
always @(posedge CLK_50MHz or negedge rst_n) begin
    if (!rst_n) begin
        // 复位时将所有计数器和输出时钟清零
        counter_100Hz <= 0;
        counter_1Hz <= 0;
        CLK_100Hz <= 0;
        CLK_1Hz <= 0;
    end else begin
        // 处理100Hz分频
        if (counter_100Hz >= DIVISOR_100Hz - 1) begin
            counter_100Hz <= 0;         // 达到分频值后计数器清零
            CLK_100Hz <= ~CLK_100Hz;    // 翻转输出时钟
        end else begin
            counter_100Hz <= counter_100Hz + 1; // 正常递增计数
        end

        // 处理1Hz分频
        if (counter_1Hz >= DIVISOR_1Hz - 1) begin
            counter_1Hz <= 0;           // 达到分频值后计数器清零
            CLK_1Hz <= ~CLK_1Hz;         // 翻转输出时钟
        end else begin
            counter_1Hz <= counter_1Hz + 1; // 正常递增计数
        end
    end
end

endmodule
