module SevenSegEncoder (
    input  [7:0] LSBBinary,   // TimerCoreLogic 输出的二进制 LSB (0‑59)
    input  [7:0] MSBBinary,   // TimerCoreLogic 输出的二进制 MSB (0‑59)
    input        ModeSel,     // 0=正计时, 1=倒计时

    output reg [6:0] HexMSBH, // MSB 十位
    output reg [6:0] HexMSBL, // MSB 个位
    output reg [6:0] HexLSBH, // LSB 十位
    output reg [6:0] HexLSBL  // LSB 个位
);

    /* ---------- 1) 二进制先转两位 BCD ---------- */
    function automatic [7:0] bin2bcd;
        input [7:0] bin;
        integer i;
        reg [15:0] sr;               // {tens, ones, bin}
        begin
            sr = 16'd0;
            sr[7:0] = bin;
            for (i = 0; i < 8; i = i + 1) begin
                if (sr[15:12] >= 5) sr[15:12] = sr[15:12] + 3;
                if (sr[11:8]  >= 5) sr[11:8]  = sr[11:8]  + 3;
                sr = sr << 1;
            end
            bin2bcd = sr[15:8];      // {tens[3:0], ones[3:0]}
        end
    endfunction

    wire [7:0] bcd_lsb_raw = bin2bcd(LSBBinary);
    wire [7:0] bcd_msb_raw = bin2bcd(MSBBinary);

    /* ---------- 2) BCD → Reverser（60‑x） ---------- */
    wire [7:0] RevLSB, RevMSB;
    // Reverser reverser_lsb (
    //     .RevIn   (bcd_lsb_raw),
    //     .ModeSel (ModeSel),
    //     .RevOut  (RevLSB)
    // );
    // Reverser reverser_msb (
    //     .RevIn   (bcd_msb_raw),
    //     .ModeSel (ModeSel),
    //     .RevOut  (RevMSB)
    // );

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
    /* ---------- 3) 选用正向或反向 BCD ---------- */
    wire [7:0] bcd_lsb = ModeSel ? RevLSB : bcd_lsb_raw;
    wire [7:0] bcd_msb = ModeSel ? RevMSB : bcd_msb_raw;

    /* ---------- 4) BCD → 7 段译码 ---------- */
    function [6:0] bcd_to_7seg;
        input [3:0] b;
        begin
            case (b)
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
                default: bcd_to_7seg = 7'b111_1111; // 全灭
            endcase
        end
    endfunction

    always @* begin
        HexLSBL = bcd_to_7seg(bcd_lsb[3:0]);  // LSB 个位
        HexLSBH = bcd_to_7seg(bcd_lsb[7:4]);  // LSB 十位
        HexMSBL = bcd_to_7seg(bcd_msb[3:0]);  // MSB 个位
        HexMSBH = bcd_to_7seg(bcd_msb[7:4]);  // MSB 十位
    end

endmodule
