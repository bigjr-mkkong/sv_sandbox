`timescale 1ns / 1ps

{% do unit_test(
    module_name = "two2one_spi_arbiter",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/spi_arbiter.py") %}
module two2one_spi_arbiter (
    input  wire        clk_i,
    input  wire        rst_ni,

    spi_ram_if.if_sink slvs_i[2],
    spi_ram_if.if_src  mst_o
);

    logic curr_idx_q, curr_idx_d;
    logic [7:0] rsp_data_buff_q, rsp_data_buff_d;

    typedef enum logic [1:0] { IDLE, WAIT, RESP } state_e;
    state_e state_d, state_q;

    logic [1:0] req_val, req_we, rsp_rdy;
    logic [1:0][15:0] req_addr;
    logic [1:0][7:0] req_wdata;

    assign mst_o.req_we = req_we[curr_idx_q];
    assign mst_o.req_addr = req_addr[curr_idx_q];
    assign mst_o.req_wdata = req_wdata[curr_idx_q];

    for (genvar i = 0; i < 2; i++) begin : source_ports
        assign req_val[i] = slvs_i[i].req_val;
        assign req_we[i] = slvs_i[i].req_we;
        assign req_addr[i] = slvs_i[i].req_addr;
        assign req_wdata[i] = slvs_i[i].req_wdata;
        assign rsp_rdy[i] = slvs_i[i].rsp_rdy;
        assign slvs_i[i].req_rdy = state_q == IDLE
            && curr_idx_q == i && mst_o.req_rdy;
        assign slvs_i[i].rsp_val = state_q == RESP && curr_idx_q == i;
        assign slvs_i[i].rsp_rdata = rsp_data_buff_q;
    end

    always_comb begin
        state_d = state_q;
        curr_idx_d = curr_idx_q;
        rsp_data_buff_d = rsp_data_buff_q;
        mst_o.req_val = 1'b0;
        mst_o.rsp_rdy = 1'b0;

        case (state_q)
            IDLE: begin
                mst_o.req_val = req_val[curr_idx_q];
                if (mst_o.req_val) begin
                    if (mst_o.req_rdy)
                        state_d = WAIT;
                end else if (req_val[!curr_idx_q]) begin
                    curr_idx_d = !curr_idx_q;
                end
            end

            WAIT: begin
                mst_o.rsp_rdy = 1'b1;
                if (mst_o.rsp_val) begin
                    rsp_data_buff_d = mst_o.rsp_rdata;
                    state_d = RESP;
                end
            end

            RESP: begin
                if (rsp_rdy[curr_idx_q]) begin
                    state_d = IDLE;
                    curr_idx_d = !curr_idx_q;
                end
            end

            default: state_d = IDLE;
        endcase
    end

    // Reset must also cancel the SPI master's outstanding transaction.
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            curr_idx_q <= 1'b0;
            rsp_data_buff_q <= '0;
        end else begin
            state_q <= state_d;
            curr_idx_q <= curr_idx_d;
            rsp_data_buff_q <= rsp_data_buff_d;
        end
    end

endmodule
