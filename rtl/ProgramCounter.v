module ProgramCounter (

    input clk,                 // Clock Signal (100Hz or 1Hz)
    input [7:0] ResetVal,       // Input value to update the PC when reset is active
    input [7:0] LoadVal,        // Input value to update the PC when load is active
    input reset,                // Active-high signal to reset the PC (asynchronous)
    input load,                 // Active-high signal to load value in PC (synchronous)
    input inc,                  // Active-high signal to start counting

    output reg [7:0] PCoutput   // PC output signal in binary

);

// 异步复位逻辑
always @(posedge clk or posedge reset) begin
    if (reset) begin
        PCoutput <= ResetVal;
    end else begin
        if (load) begin
            PCoutput <= LoadVal;
        end else if (inc) begin
            PCoutput <= PCoutput + 1;
        end
    end
end

endmodule
