`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
{% do unit_test(
    module_name = "dumb_dram_1rw",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/1rw_dumb_dram_tb.py") %}
module dumb_dram_1rw #(
    parameter int unsigned ADDR_WIDTH    = 64,
    parameter int unsigned DATA_WIDTH    = 64,
    parameter int unsigned DATA_PER_LINE = 8
) (
    input logic clk_i,
    input logic rst_ni,

    // Cache-line-wide upstream AXI-Lite slave interface.
    taxi_axil_if.wr_slv s_axil_wr,
    taxi_axil_if.rd_slv s_axil_rd
);

    localparam logic [1:0] AXIL_RESP_OKAY = 2'b00;
    localparam logic [DATA_WIDTH-1:0] MAGIC_WORD = DATA_WIDTH'(114514);

    typedef enum logic [1:0] {
        IDLE,
        WRITE_RESP,
        READ_RESP
    } state_e;

    state_e state_d, state_q;

    logic write_pair_valid;
    logic write_channel_pending;

    always_comb begin
        state_d = state_q;

        s_axil_wr.awready = 1'b0;
        s_axil_wr.wready = 1'b0;
        s_axil_wr.bresp = AXIL_RESP_OKAY;
        s_axil_wr.buser = '0;
        s_axil_wr.bvalid = 1'b0;

        s_axil_rd.arready = 1'b0;
        s_axil_rd.rdata = {DATA_PER_LINE{MAGIC_WORD}};
        s_axil_rd.rresp = AXIL_RESP_OKAY;
        s_axil_rd.ruser = '0;
        s_axil_rd.rvalid = 1'b0;

        write_pair_valid = s_axil_wr.awvalid && s_axil_wr.wvalid;
        write_channel_pending = s_axil_wr.awvalid || s_axil_wr.wvalid;

        case (state_q)
            IDLE: begin
                if (write_channel_pending) begin
                    if (write_pair_valid) begin
                        s_axil_wr.awready = 1'b1;
                        s_axil_wr.wready = 1'b1;
                        state_d = WRITE_RESP;
                    end
                end else if (s_axil_rd.arvalid) begin
                    s_axil_rd.arready = 1'b1;
                    state_d = READ_RESP;
                end
            end

            WRITE_RESP: begin
                s_axil_wr.bvalid = 1'b1;
                if (s_axil_wr.bready) begin
                    state_d = IDLE;
                end
            end

            READ_RESP: begin
                s_axil_rd.rvalid = 1'b1;
                if (s_axil_rd.rready) begin
                    state_d = IDLE;
                end
            end

            default: begin
                state_d = IDLE;
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state_q <= IDLE;
        end else begin
            state_q <= state_d;
        end
    end

endmodule
/* verilator lint_on DECLFILENAME */
