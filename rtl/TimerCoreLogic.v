//============================================================
//  TimerCoreLogic.v  (接口已改：由 ModeSel 决定复位值)
//============================================================
module TimerCoreLogic (
    input        clk,          // 100 Hz 或 1 Hz
    input        rst_n,        // 低有效复位
    input        StartStop,    // 翻转运行/暂停
    input        ModeSel,      // 0: 正计时   1: 倒计 2:00→0:00

    output [7:0] LSBbinaryout, // 0‑59
    output [7:0] MSBbinaryout
);
    /* -------- 常量 -------- */
    localparam [7:0] LSB_RESET_VAL = 8'd0;   // 两种模式 LSB 均为 0
    localparam [7:0] MSB_RESET_A   = 8'd0;   // Mode A 初值
    localparam [7:0] MSB_RESET_B   = 8'd58;  // Mode B 初值 (BCD 0x58)

    /* -------- 根据 ModeSel 生成当前复位值 -------- */
    wire [7:0] msb_reset_val = ModeSel ? MSB_RESET_B : MSB_RESET_A;

    /* -------- Start/Stop 边沿检测 -------- */
    reg running, prev_StartStop;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running        <= 1'b0;
            prev_StartStop <= 1'b0;
        end else begin
            prev_StartStop <= StartStop;
            if (~prev_StartStop & StartStop)
                running <= ~running;   // 翻转
        end
    end

    /* -------- LSB / MSB 计数控制 -------- */
    /* -------- LSB / MSB 计数控制 -------- */
    reg reset_pc_lsb, inc_pc_lsb;
    reg reset_pc_msb, inc_pc_msb;
    // reg carry_latched;                      // 仅 Mode B 用

    wire [7:0] pc_lsb_out;
    wire [7:0] pc_msb_out;

    // -------- 当前模式的 LSB 最大值 --------
    // ModeSel == 0 --> CountUp
    // ModeSel == 1 --> CountDown(60)
    wire [7:0] LSB_MAX = ModeSel ? 8'd59 : 8'd99;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reset_pc_lsb  <= 1'b1;
            reset_pc_msb  <= 1'b1;
            inc_pc_lsb    <= 1'b0;
            inc_pc_msb    <= 1'b0;
            // carry_latched <= 1'b0;
        end else begin
            /* 默认不动作 */
            reset_pc_lsb  <= 1'b0;
            reset_pc_msb  <= 1'b0;
            inc_pc_lsb    <= 1'b0;
            inc_pc_msb    <= 1'b0;

            if (running) begin
                //========================================================
                // 1) MSB 借/进位逻辑
                //========================================================
                if (ModeSel) begin
                    // -------- Mode B：59 或 0 借位（去抖）--------
                    // if ((pc_lsb_out == 8'd59 || pc_lsb_out == 8'd0) && !carry_latched) begin
                    //     inc_pc_msb    <= 1'b1;   // MSB +1 == 分钟 −1
                    //     carry_latched <= 1'b1;
                    // end
                    if ((pc_lsb_out == 8'd58)) begin
                        inc_pc_msb    <= 1'b1;   // MSB +1 == 分钟 −1
                        // carry_latched <= 1'b1;
                    end
                end else begin
                    // -------- Mode A：99 进位 --------
                    if (pc_lsb_out == 8'd99) begin
                        inc_pc_msb <= 1'b1;
                    end
                end

                //========================================================
                // 2) LSB 自增 / 回绕
                //========================================================
                if (pc_lsb_out == LSB_MAX) begin
                    reset_pc_lsb <= 1'b1;        // 回到 0
                end else begin
                    inc_pc_lsb <= 1'b1;
                end

                //========================================================
                // 3) 离开边界解除去抖锁存 (Mode B)
                //========================================================
                // if (ModeSel && pc_lsb_out != 8'd0 && pc_lsb_out != 8'd59)
                //     carry_latched <= 1'b0;

                //========================================================
                // 4) Mode B 计到 60:00 → 自动回到 58:00
                //========================================================
                if (ModeSel &&
                    pc_msb_out == (MSB_RESET_B + 8'd2) &&
                    pc_lsb_out == LSB_RESET_VAL) begin
                    reset_pc_lsb  <= 1'b1;
                    reset_pc_msb  <= 1'b1;
                    // carry_latched <= 1'b0;
                end
            end
        end
    end

    /* -------- ProgramCounter 实例 -------- */
    ProgramCounter PC_LSB (
        .clk     (clk),
        .ResetVal(LSB_RESET_VAL),
        .LoadVal (8'd0),
        .reset   (reset_pc_lsb),
        .load    (1'b0),
        .inc     (inc_pc_lsb),
        .PCoutput(pc_lsb_out)
    );

    ProgramCounter PC_MSB (
        .clk     (clk),
        // .ResetVal(msb_reset_val),   // 依 ModeSel 变化
        .ResetVal(LSB_RESET_VAL),   // 依 ModeSel 变化
        .LoadVal (8'd0),
        .reset   (reset_pc_msb),
        .load    (1'b0),
        .inc     (inc_pc_msb),
        .PCoutput(pc_msb_out)
    );

    /* -------- 输出 -------- */
    assign LSBbinaryout = pc_lsb_out;
    assign MSBbinaryout = pc_msb_out;
endmodule
