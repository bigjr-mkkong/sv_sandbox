{% do unit_test(
    module_name = "n21_coh_cache2bus_arbiter",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/coh_bus_arbiter_tb.py") %}
module n21_coh_cache2bus_arbiter #(
    parameter int unsigned SLV_CNT = 2,
    parameter int unsigned ADDR_WIDTH = config_pkg::ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = config_pkg::DATA_WIDTH
) (
    input logic clk_i,
    input logic rst_ni,

    coh_cache2bus_req.if_sink slvs_i[SLV_CNT],
    coh_cache2bus_req.if_src  mst_o
);

    typedef enum logic {
        IDLE,
        RESP
    } state_e;

    localparam int unsigned MASK_WIDTH = SLV_CNT > 1 ? $clog2(SLV_CNT) : 1;

    logic [MASK_WIDTH-1:0] act_mask_q;
    state_e state_q, state_d;

    logic goto_next;

    // Interface-array members require constant indices in Verilator. Bridge
    // them to packed vectors so the active source can be selected at runtime.
    logic [SLV_CNT-1:0]                 slv_req_val;
    logic [SLV_CNT-1:0][1:0]            slv_bus_op;
    logic [SLV_CNT-1:0][ADDR_WIDTH-1:0] slv_req_addr;
    logic [SLV_CNT-1:0]                 slv_req_rdy;
    logic [SLV_CNT-1:0]                 slv_rsp_val;
    logic [SLV_CNT-1:0]                 slv_rsp_shared;
    logic [SLV_CNT-1:0]                 slv_rsp_rdy;

    for (genvar i = 0; i < SLV_CNT; i++) begin : gen_slv_bridge
        assign slv_req_val[i] = slvs_i[i].req_val;
        assign slv_bus_op[i] = slvs_i[i].bus_op;
        assign slv_req_addr[i] = slvs_i[i].req_addr;
        assign slvs_i[i].req_rdy = slv_req_rdy[i];

        assign slvs_i[i].rsp_val = slv_rsp_val[i];
        assign slvs_i[i].rsp_shared = slv_rsp_shared[i];
        assign slv_rsp_rdy[i] = slvs_i[i].rsp_rdy;
    end

    always_comb begin
        state_d = state_q;

        mst_o.req_val  = 1'b0;
        mst_o.bus_op   = config_pkg::BusNOP;
        mst_o.req_addr = '0;
        mst_o.req_src  = act_mask_q;
        mst_o.rsp_rdy  = 1'b0;
        goto_next = 0;

        slv_req_rdy = '0;
        slv_rsp_val = '0;
        slv_rsp_shared = '0;

        case (state_q)

            IDLE: begin
                mst_o.req_val = slv_req_val[act_mask_q];
                mst_o.bus_op = config_pkg::coh_bus_op'(
                    slv_bus_op[act_mask_q]
                );
                mst_o.req_addr = slv_req_addr[act_mask_q];
                slv_req_rdy[act_mask_q] = mst_o.req_rdy;

                if (!slv_req_val[act_mask_q]) begin
                    goto_next = 1;
                end

                else if (slv_req_val[act_mask_q] && mst_o.req_rdy) begin
                    state_d = RESP;
                end
            end

            RESP: begin
                slv_rsp_val[act_mask_q] = mst_o.rsp_val;
                slv_rsp_shared[act_mask_q] = mst_o.rsp_shared;
                mst_o.rsp_rdy = slv_rsp_rdy[act_mask_q];

                if (mst_o.rsp_val && slv_rsp_rdy[act_mask_q]) begin
                    state_d = IDLE;
                    goto_next = 1;
                end
            end

        endcase
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            act_mask_q <= '0;
            state_q <= IDLE;
        end else begin
            if (goto_next) begin
                act_mask_q <= (act_mask_q == MASK_WIDTH'(SLV_CNT-1))
                    ? '0 : act_mask_q + 1'b1;
            end
            state_q <= state_d;
        end
    end

endmodule
