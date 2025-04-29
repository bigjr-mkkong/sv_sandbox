module TimerCoreLogic (
    input        clk,             // Clock Signal (100Hz or 1Hz)
    input        rst_n,           // Active-LOW reset signal
    input        StartStop,       // 控制运行/暂停

    // 模式复位值（Mode A: MSB=0,LSB=0；Mode B: MSB=2,LSB=0）
    input  [7:0] LSB_reset_val,
    input  [7:0] MSB_reset_val,

    // 对外输出
    output [7:0] LSBbinaryout,
    output [7:0] MSBbinaryout
);

    //—— 内部状态 ——//
    reg        running;
    reg        prev_StartStop;

    // LSB 控制信号
    reg        reset_pc_lsb;
    reg        inc_pc_lsb;

    // MSB 控制信号
    reg        reset_pc_msb;
    reg        inc_pc_msb;

     //—— 从两个 ProgramCounter 拿到的原始二进制输出 ——//
     wire [7:0] pc_lsb_out;
     wire [7:0] pc_msb_out;

    //—— 新增：倒计时模式下用的寄存器 ——//
    wire       modeB = (MSB_reset_val != 8'd0); // 只要 MSB_reset_val≠0 就当倒计时
    reg  [7:0] count_lsb, count_msb;

    //—— StartStop 上升沿检测 ——//
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running        <= 1'b0;
            prev_StartStop <= 1'b0;
        end else begin
            prev_StartStop <= StartStop;
            if (~prev_StartStop & StartStop) begin
                running <= ~running;
            end
        end
    end

    //—— LSB/MSB 计数 & 回绕 & 进位 ——//
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时拉高 reset，让 PC 回到复位值
            reset_pc_lsb <= 1'b1;
            reset_pc_msb <= 1'b1;
            // 计数脉冲清 0
            inc_pc_lsb   <= 1'b0;
            inc_pc_msb   <= 1'b0;
        end else begin
            // 默认不复位
            reset_pc_lsb <= 1'b0;
            reset_pc_msb <= 1'b0;
            // 默认不计数
            inc_pc_lsb   <= 1'b0;
            inc_pc_msb   <= 1'b0;

            if (running) begin
                if (pc_lsb_out == 8'd99) begin
                    // LSB 到 99 → 本周期复位 LSB，下周期回到 LSB_reset_val
                    reset_pc_lsb <= 1'b1;
                    // 同期为 MSB 产生 +1 脉冲
                    inc_pc_msb   <= 1'b1;
                end else begin
                    // 普通模式：LSB 每周期 +1，MSB 保持不动
                    inc_pc_lsb <= 1'b1;
                end
            end
        end
    end

    //—— 实例化 LSB ProgramCounter ——//
    ProgramCounter PC_LSB (
        .clk     (clk),
        .ResetVal(LSB_reset_val),
        .LoadVal (8'd0),        // 本项目不使用 Load
        .reset   (reset_pc_lsb),
        .load    (1'b0),
        .inc     (inc_pc_lsb),
        .PCoutput( pc_lsb_out )
    );

    //—— 实例化 MSB ProgramCounter ——//
    ProgramCounter PC_MSB (
        .clk     (clk),
        .ResetVal(MSB_reset_val),
        .LoadVal (8'd0),
        .reset   (reset_pc_msb),
        .load    (1'b0),
        .inc     (inc_pc_msb),
        .PCoutput( pc_msb_out )
    );

    //—— 对外输出 ——//
    assign LSBbinaryout = pc_lsb_out;
    assign MSBbinaryout = pc_msb_out;

endmodule
