module Reverser (
    input  [7:0] RevIn,   // two‑digit BCD
    input        ModeSel, // 0 = 直通, 1 = 倒置
    output reg [7:0] RevOut
);

parameter bcd_0  = 4'b0000;
parameter bcd_5  = 4'b0101;
parameter bcd_6  = 4'b0110;
parameter bcd_10 = 4'b1010;   // ★ 修改：4 位 1010 (10)

// reg [3:0] UnitsResult;
// reg [3:0] TensResult;

// /* ---------- 反转值计算 ---------- */
// always @* begin
//     /* ★ 逻辑更新：显式处理 0‑59 的“60 – x” 反转 */
//     if (RevIn == 8'b0000_0000) begin
//         UnitsResult = bcd_0;          // 0 ↔ 0
//         TensResult  = bcd_0;
//     end
//     else if (RevIn[3:0] != bcd_0) begin
//         // 非整十：60 - x  等价于 10 - units, 5 - tens
//         UnitsResult = bcd_10 - RevIn[3:0];
//         TensResult  = bcd_5  - RevIn[7:4];
//     end
//     else begin
//         // 整十：units 为 0，tens 用 6 - tens
//         UnitsResult = bcd_0;
//         TensResult  = bcd_6 - RevIn[7:4];
//     end
// end

// /* ---------- RevOut 选择 ---------- */
// always @* begin
//     if (!ModeSel)
//         RevOut = RevIn;                   // 直通
//     else
//         RevOut = {TensResult, UnitsResult}; // 倒置
// end

assign RevOut = (~ModeSel)? RevIn : 8'd60 - RevIn;

endmodule
