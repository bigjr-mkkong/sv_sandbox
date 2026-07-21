`timescale 1ns / 1ps

module main_module #(
    parameter int unsigned DATA_WIDTH = 8
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    output logic [DATA_WIDTH-1:0] m_axis_tx_tdata_o,
    output logic                  m_axis_tx_tvalid_o,
    input  logic                  m_axis_tx_tready_i
);

    logic [DATA_WIDTH-1:0] data_r;
    logic [DATA_WIDTH-1:0] data_next;

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            data_r <= DATA_WIDTH'(8'h41);
        end else begin
            data_r <= data_next;
        end
    end

    always_comb begin
        m_axis_tx_tdata_o = data_r;
        m_axis_tx_tvalid_o = 1'b1;

        data_next = data_r;
        if (m_axis_tx_tready_i) begin
            data_next = data_r >= DATA_WIDTH'(8'h5a)
                ? DATA_WIDTH'(8'h41)
                : data_r + DATA_WIDTH'(1);
        end
    end

endmodule
