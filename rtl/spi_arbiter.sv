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

    // Interface array indices must be constant; mux the selected request.
    assign mst_o.req_val = rst_ni && state_q == IDLE
        && (curr_idx_q ? slvs_i[1].req_val : slvs_i[0].req_val);
    assign mst_o.req_we = curr_idx_q ? slvs_i[1].req_we : slvs_i[0].req_we;
    assign mst_o.req_addr = curr_idx_q ? slvs_i[1].req_addr : slvs_i[0].req_addr;
    assign mst_o.req_wdata = curr_idx_q ? slvs_i[1].req_wdata : slvs_i[0].req_wdata;

    // spi_master has no response-ready port: capture its pulse unconditionally in WAIT.
    assign mst_o.rsp_rdy = rst_ni && state_q == WAIT;

    for (genvar i = 0; i < 2; i++) begin : source_ports
        assign slvs_i[i].req_rdy = rst_ni && state_q == IDLE
            && curr_idx_q == i && mst_o.req_rdy;
        assign slvs_i[i].rsp_val = rst_ni && state_q == RESP && curr_idx_q == i;
        assign slvs_i[i].rsp_rdata = rsp_data_buff_q;
    end

    always_comb begin
        state_d = state_q;
        curr_idx_d = curr_idx_q;
        rsp_data_buff_d = rsp_data_buff_q;

        case (state_q)
            IDLE: begin
                if (mst_o.req_val) begin
                    if (mst_o.req_rdy)
                        state_d = WAIT;
                end else if (curr_idx_q ? slvs_i[0].req_val : slvs_i[1].req_val) begin
                    curr_idx_d = !curr_idx_q;
                end
            end

            WAIT: begin
                if (mst_o.rsp_val) begin
                    rsp_data_buff_d = mst_o.rsp_rdata;
                    state_d = RESP;
                end
            end

            RESP: begin
                if (curr_idx_q ? slvs_i[1].rsp_rdy : slvs_i[0].rsp_rdy) begin
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
