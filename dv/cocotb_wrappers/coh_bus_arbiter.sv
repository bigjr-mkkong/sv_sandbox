`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNDRIVEN */
module n21_coh_cache2bus_arbiter_unit_test;
    localparam int unsigned ADDR_WIDTH = 64;
    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned SLV_CNT = 2;
    localparam int unsigned SRC_WIDTH = $clog2(SLV_CNT);

    logic clk_i;
    logic rst_ni;

    // Flatten the interface array so cocotb can address each source by index.
    logic [SLV_CNT-1:0]                 slv_req_val;
    logic [SLV_CNT-1:0][1:0]            slv_bus_op;
    logic [SLV_CNT-1:0][ADDR_WIDTH-1:0] slv_req_addr;
    logic [SLV_CNT-1:0]                 slv_req_rdy;
    logic [SLV_CNT-1:0]                 slv_rsp_val;
    logic [SLV_CNT-1:0]                 slv_rsp_shared;
    logic [SLV_CNT-1:0]                 slv_rsp_rdy;
    logic [SRC_WIDTH-1:0]               mst_req_src;

    logic mst_rsp_pending_q;
    logic mst_rsp_shared_q;
    logic [7:0] mst_rsp_delay_cycles;
    logic [7:0] mst_rsp_delay_q;

    coh_cache2bus_req #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SRC_WIDTH(SRC_WIDTH)
    ) slvs_i[SLV_CNT]();

    coh_cache2bus_req #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SRC_WIDTH(SRC_WIDTH)
    ) mst_o();

    for (genvar i = 0; i < SLV_CNT; i++) begin : gen_flatten_slvs
        assign slvs_i[i].req_val = slv_req_val[i];
        assign slvs_i[i].bus_op = config_pkg::coh_bus_op'(slv_bus_op[i]);
        assign slvs_i[i].req_addr = slv_req_addr[i];
        assign slvs_i[i].req_src = i;
        assign slv_req_rdy[i] = slvs_i[i].req_rdy;

        assign slv_rsp_val[i] = slvs_i[i].rsp_val;
        assign slv_rsp_shared[i] = slvs_i[i].rsp_shared;
        assign slvs_i[i].rsp_rdy = slv_rsp_rdy[i];
    end

    assign mst_o.req_rdy = !mst_rsp_pending_q;
    assign mst_req_src = mst_o.req_src;
    assign mst_o.rsp_val = mst_rsp_pending_q && (mst_rsp_delay_q == '0);
    assign mst_o.rsp_shared = mst_rsp_shared_q;

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            mst_rsp_pending_q <= 1'b0;
            mst_rsp_shared_q <= 1'b0;
            mst_rsp_delay_q <= '0;
        end else begin
            if (mst_o.req_val && mst_o.req_rdy) begin
                mst_rsp_pending_q <= 1'b1;
                mst_rsp_shared_q <= mst_o.bus_op[0] ^ mst_o.req_addr[0];
                mst_rsp_delay_q <= mst_rsp_delay_cycles;
            end else if (mst_rsp_pending_q && (mst_rsp_delay_q != '0)) begin
                mst_rsp_delay_q <= mst_rsp_delay_q - 1'b1;
            end else if (mst_o.rsp_val && mst_o.rsp_rdy) begin
                mst_rsp_pending_q <= 1'b0;
            end
        end
    end

    n21_coh_cache2bus_arbiter #(
        .SLV_CNT(SLV_CNT),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .slvs_i(slvs_i),
        .mst_o(mst_o)
    );
endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on DECLFILENAME */
