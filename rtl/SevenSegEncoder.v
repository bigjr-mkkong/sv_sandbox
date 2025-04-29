module SevenSegEncoder (
    input  [7:0] LSBBinary,   // 来自 TimerCoreLogic 的二进制 LSB
    input  [7:0] MSBBinary,   // 来自 TimerCoreLogic 的二进制 MSB
    input        ModeSel,     // 计数方向控制

    output reg [6:0] HexMSBH, // MSB 十位 7 段码
    output reg [6:0] HexMSBL, // MSB 个位 7 段码
    output reg [6:0] HexLSBH, // LSB 十位 7 段码
    output reg [6:0] HexLSBL  // LSB 个位 7 段码
);

    //—— 1) 保留 Reverser，用来升/降计数 ——//
    wire [7:0] RevLSB, RevMSB;
    Reverser reverser_lsb (
        .RevIn   (LSBBinary),
        .ModeSel (ModeSel),
        .RevOut  (RevLSB)
    );
    Reverser reverser_msb (
        .RevIn   (MSBBinary),
        .ModeSel (ModeSel),
        .RevOut  (RevMSB)
    );

    //—— 2) Double-Dabble 函数：8 位二进制 → BCD(两位) ——//
    function automatic [7:0] bin2bcd;
        input [7:0] bin;
        integer     i;
        reg   [3:0] tens, ones;
        reg  [15:0] shift_reg;  // {tens[3:0], ones[3:0], bin[7:0]}
        begin
            // 初始化
            tens      = 4'd0;
            ones      = 4'd0;
            shift_reg = {tens, ones, bin};

            // 8 次迭代
            for (i = 0; i < 8; i = i + 1) begin
                // 如果某个 BCD 位 ≥ 5，就加 3
                if (shift_reg[15:12] >= 5) 
                    shift_reg[15:12] = shift_reg[15:12] + 3;
                if (shift_reg[11:8] >= 5) 
                    shift_reg[11:8] = shift_reg[11:8] + 3;
                // 整体左移一位
                shift_reg = shift_reg << 1;
            end

            // 取出高 8 位：{十位, 个位}
            bin2bcd = shift_reg[15:8];
        end
    endfunction

    //—— 3) Seven-segment 译码（保持原来的 Lookup） ——//
    function [6:0] bcd_to_7seg;
        input [3:0] bcd;
        begin
            case (bcd)
                4'd0: bcd_to_7seg = 7'b100_0000;
                4'd1: bcd_to_7seg = 7'b111_1001;
                4'd2: bcd_to_7seg = 7'b010_0100;
                4'd3: bcd_to_7seg = 7'b011_0000;
                4'd4: bcd_to_7seg = 7'b001_1001;
                4'd5: bcd_to_7seg = 7'b001_0010;
                4'd6: bcd_to_7seg = 7'b000_0010;
                4'd7: bcd_to_7seg = 7'b111_1000;
                4'd8: bcd_to_7seg = 7'b000_0000;
                4'd9: bcd_to_7seg = 7'b001_0000;
                default: bcd_to_7seg = 7'b111_1111; // 非法 BCD → 全灭
            endcase
        end
    endfunction

    //—— 4) 把反转后的二进制先转成 BCD ——//
    wire [7:0] bcd_lsb = bin2bcd(RevLSB);
    wire [7:0] bcd_msb = bin2bcd(RevMSB);

    //—— 5) 输出到 7 段显示 ——//
    always @(*) begin
        HexLSBL = bcd_to_7seg(bcd_lsb[3:0]);  // LSB 个位
        HexLSBH = bcd_to_7seg(bcd_lsb[7:4]);  // LSB 十位
        HexMSBL = bcd_to_7seg(bcd_msb[3:0]);  // MSB 个位
        HexMSBH = bcd_to_7seg(bcd_msb[7:4]);  // MSB 十位
    end

endmodule
