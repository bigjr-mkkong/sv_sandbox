module Reverser (

    input [7:0] RevIn,      // The 8-bit BCD value input
    input ModeSel,          // Control signal: 0=normal, 1=reversed

    output reg [7:0] RevOut // The 8-bit BCD value output

);




always @(*) begin
    if (ModeSel == 0) begin
        RevOut = RevIn;  // 正常模式，直接输出
    end else begin
        // 反向模式：每4位单独反转
        RevOut[7:4] = 4'd9 - RevIn[7:4];  // 高4位反转
        RevOut[3:0] = 4'd9 - RevIn[3:0];  // 低4位反转
    end
end

endmodule
