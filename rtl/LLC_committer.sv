`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */

/*
 * Blocking owner and transaction manager for the shared, line-wide LLC port.
 * Coherence requests have priority whenever both producers are pending.
 */
{% do unit_test(
    module_name = "LLC_committer",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/LLC_committer_tb.py") %}
module LLC_committer #(
    parameter int unsigned ADDR_WIDTH = 64,
    parameter int unsigned LINE_WIDTH = 512
) (
    input logic clk_i,
    input logic rst_ni,

    input  logic                  coh_req_val_i,
    output logic                  coh_req_rdy_o,
    input  logic                  coh_req_is_write_i,
    input  logic [ADDR_WIDTH-1:0] coh_req_addr_i,
    input  logic [LINE_WIDTH-1:0] coh_req_data_i,
    output logic                  coh_rsp_val_o,
    input  logic                  coh_rsp_rdy_i,
    output logic [LINE_WIDTH-1:0] coh_rsp_data_o,

    input  logic                  cache_req_val_i,
    output logic                  cache_req_rdy_o,
    input  logic                  cache_req_is_write_i,
    input  logic [ADDR_WIDTH-1:0] cache_req_addr_i,
    input  logic [LINE_WIDTH-1:0] cache_req_data_i,
    output logic                  cache_rsp_val_o,
    input  logic                  cache_rsp_rdy_i,
    output logic [LINE_WIDTH-1:0] cache_rsp_data_o,

    taxi_axil_if.wr_mst m_axil_wr,
    taxi_axil_if.rd_mst m_axil_rd
);

    typedef enum logic [1:0] {
        COMMIT,
        SUBMIT,
        WAIT,
        RESP
    } state_e;

    typedef enum logic {
        OWNER_CACHE,
        OWNER_COH
    } owner_e;

    state_e state_d, state_q;
    owner_e owner_d, owner_q;
    logic req_is_write_d, req_is_write_q;
    logic [ADDR_WIDTH-1:0] req_addr_d, req_addr_q;
    logic [LINE_WIDTH-1:0] req_data_d, req_data_q;
    logic [LINE_WIDTH-1:0] rsp_data_d, rsp_data_q;
    logic aw_done_d, aw_done_q;
    logic w_done_d, w_done_q;

    always_comb begin
        state_d = state_q;
        owner_d = owner_q;
        req_is_write_d = req_is_write_q;
        req_addr_d = req_addr_q;
        req_data_d = req_data_q;
        rsp_data_d = rsp_data_q;
        aw_done_d = aw_done_q;
        w_done_d = w_done_q;

        coh_req_rdy_o = 1'b0;
        coh_rsp_val_o = 1'b0;
        coh_rsp_data_o = rsp_data_q;
        cache_req_rdy_o = 1'b0;
        cache_rsp_val_o = 1'b0;
        cache_rsp_data_o = rsp_data_q;

        m_axil_wr.awaddr = req_addr_q;
        m_axil_wr.awprot = '0;
        m_axil_wr.awuser = '0;
        m_axil_wr.awvalid = 1'b0;
        m_axil_wr.wdata = req_data_q;
        m_axil_wr.wstrb = '1;
        m_axil_wr.wuser = '0;
        m_axil_wr.wvalid = 1'b0;
        m_axil_wr.bready = 1'b0;

        m_axil_rd.araddr = req_addr_q;
        m_axil_rd.arprot = '0;
        m_axil_rd.aruser = '0;
        m_axil_rd.arvalid = 1'b0;
        m_axil_rd.rready = 1'b0;

        unique case (state_q)
            COMMIT: begin
                aw_done_d = 1'b0;
                w_done_d = 1'b0;

                // A producer owns a request only after valid && ready. Ready
                // may be combinational; valid and its payload must be held by
                // a losing producer until a later arbitration opportunity.
                coh_req_rdy_o = 1'b1;
                cache_req_rdy_o = !coh_req_val_i;

                if (coh_req_val_i && coh_req_rdy_o) begin
                    owner_d = OWNER_COH;
                    req_is_write_d = coh_req_is_write_i;
                    req_addr_d = coh_req_addr_i;
                    req_data_d = coh_req_data_i;
                    state_d = SUBMIT;
                end else if (cache_req_val_i && cache_req_rdy_o) begin
                    owner_d = OWNER_CACHE;
                    req_is_write_d = cache_req_is_write_i;
                    req_addr_d = cache_req_addr_i;
                    req_data_d = cache_req_data_i;
                    state_d = SUBMIT;
                end
            end

            SUBMIT: begin
                if (req_is_write_q) begin
                    m_axil_wr.awvalid = !aw_done_q;
                    m_axil_wr.wvalid = !w_done_q;

                    if (m_axil_wr.awvalid && m_axil_wr.awready) begin
                        aw_done_d = 1'b1;
                    end
                    if (m_axil_wr.wvalid && m_axil_wr.wready) begin
                        w_done_d = 1'b1;
                    end
                    if ((aw_done_q || m_axil_wr.awready)
                            && (w_done_q || m_axil_wr.wready)) begin
                        state_d = WAIT;
                    end
                end else begin
                    m_axil_rd.arvalid = 1'b1;
                    if (m_axil_rd.arready) begin
                        state_d = WAIT;
                    end
                end
            end

            WAIT: begin
                if (req_is_write_q) begin
                    m_axil_wr.bready = 1'b1;
                    if (m_axil_wr.bvalid) begin
                        rsp_data_d = '0;
                        state_d = RESP;
                    end
                end else begin
                    m_axil_rd.rready = 1'b1;
                    if (m_axil_rd.rvalid) begin
                        rsp_data_d = LINE_WIDTH'(m_axil_rd.rdata);
                        state_d = RESP;
                    end
                end
            end

            RESP: begin
                if (owner_q == OWNER_COH) begin
                    coh_rsp_val_o = 1'b1;
                    if (coh_rsp_rdy_i) begin
                        state_d = COMMIT;
                    end
                end else begin
                    cache_rsp_val_o = 1'b1;
                    if (cache_rsp_rdy_i) begin
                        state_d = COMMIT;
                    end
                end
            end

            default: begin
                state_d = COMMIT;
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state_q <= COMMIT;
            owner_q <= OWNER_CACHE;
            req_is_write_q <= 1'b0;
            req_addr_q <= '0;
            req_data_q <= '0;
            rsp_data_q <= '0;
            aw_done_q <= 1'b0;
            w_done_q <= 1'b0;
        end else begin
            state_q <= state_d;
            owner_q <= owner_d;
            req_is_write_q <= req_is_write_d;
            req_addr_q <= req_addr_d;
            req_data_q <= req_data_d;
            rsp_data_q <= rsp_data_d;
            aw_done_q <= aw_done_d;
            w_done_q <= w_done_d;
        end
    end

{% if not RENDER_OPTION.SYNTH %}
    always_ff @(posedge clk_i) begin
        if (rst_ni && m_axil_rd.rvalid && m_axil_rd.rready) begin
            assert (m_axil_rd.rresp == 2'b00)
                else $error("LLC read returned a non-OKAY AXI response");
        end
        if (rst_ni && m_axil_wr.bvalid && m_axil_wr.bready) begin
            assert (m_axil_wr.bresp == 2'b00)
                else $error("LLC write returned a non-OKAY AXI response");
        end
    end
{% endif %}

endmodule
/* verilator lint_on DECLFILENAME */
