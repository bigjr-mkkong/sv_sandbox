
module top_module#(
    parameter clk_frac_rate = 5,
    localparam cnt_wid = $clog2(clk_frac_rate)
    ) (
    input  logic clk_i,
    input  logic rst_ni,
    output logic led_o
);

    logic [cnt_wid - 1: 0] counter;

    always @(posedge clk_i) begin
        if (~rst_ni) begin
            counter <= 0;
        end else begin
            counter <= counter + 1;
        end
    end

    assign led_o = (counter == clk_frac_rate);

endmodule
