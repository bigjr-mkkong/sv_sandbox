`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNDRIVEN */
/* verilator lint_off UNUSEDSIGNAL */
module LLC_committer_unit_test;
    localparam int unsigned TEST_ADDR_WIDTH = 64;
    localparam int unsigned TEST_DATA_WIDTH = 64;
    localparam int unsigned TEST_DATA_PER_LINE = 8;
    localparam int unsigned TEST_LINE_WIDTH
        = TEST_DATA_WIDTH * TEST_DATA_PER_LINE;

    logic clk_i;
    logic rst_ni;

    logic                  coh_req_val_i;
    logic                  coh_req_rdy_o;
    logic                  coh_req_is_write_i;
    logic [TEST_ADDR_WIDTH-1:0] coh_req_addr_i;
    logic [TEST_LINE_WIDTH-1:0] coh_req_data_i;
    logic                  coh_rsp_val_o;
    logic                  coh_rsp_rdy_i;
    logic [TEST_LINE_WIDTH-1:0] coh_rsp_data_o;

    logic                  cache_req_val_i;
    logic                  cache_req_rdy_o;
    logic                  cache_req_is_write_i;
    logic [TEST_ADDR_WIDTH-1:0] cache_req_addr_i;
    logic [TEST_LINE_WIDTH-1:0] cache_req_data_i;
    logic                  cache_rsp_val_o;
    logic                  cache_rsp_rdy_i;
    logic [TEST_LINE_WIDTH-1:0] cache_rsp_data_o;

    logic [31:0]           dram_read_count_o;
    logic [31:0]           dram_write_count_o;
    logic [TEST_ADDR_WIDTH-1:0] dram_last_read_addr_o;
    logic [TEST_ADDR_WIDTH-1:0] dram_last_write_addr_o;
    logic [TEST_LINE_WIDTH-1:0] dram_last_write_data_o;

    taxi_axil_if #(
        .DATA_W(TEST_LINE_WIDTH),
        .ADDR_W(TEST_ADDR_WIDTH)
    ) m_axil();

    /* Passive visibility into transactions accepted by the real test DRAM. */
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            dram_read_count_o <= '0;
            dram_write_count_o <= '0;
            dram_last_read_addr_o <= '0;
            dram_last_write_addr_o <= '0;
            dram_last_write_data_o <= '0;
        end else begin
            if (m_axil.arvalid && m_axil.arready) begin
                dram_read_count_o <= dram_read_count_o + 1'b1;
                dram_last_read_addr_o <= m_axil.araddr;
            end
            if (m_axil.awvalid && m_axil.awready
                    && m_axil.wvalid && m_axil.wready) begin
                dram_write_count_o <= dram_write_count_o + 1'b1;
                dram_last_write_addr_o <= m_axil.awaddr;
                dram_last_write_data_o <= m_axil.wdata;
            end
        end
    end

    dumb_dram_1rw #(
        .ADDR_WIDTH(TEST_ADDR_WIDTH),
        .DATA_WIDTH(TEST_DATA_WIDTH),
        .DATA_PER_LINE(TEST_DATA_PER_LINE)
    ) dram (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .s_axil_wr(m_axil),
        .s_axil_rd(m_axil)
    );

    LLC_committer #(
        .ADDR_WIDTH(TEST_ADDR_WIDTH),
        .LINE_WIDTH(TEST_LINE_WIDTH)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .coh_req_val_i(coh_req_val_i),
        .coh_req_rdy_o(coh_req_rdy_o),
        .coh_req_is_write_i(coh_req_is_write_i),
        .coh_req_addr_i(coh_req_addr_i),
        .coh_req_data_i(coh_req_data_i),
        .coh_rsp_val_o(coh_rsp_val_o),
        .coh_rsp_rdy_i(coh_rsp_rdy_i),
        .coh_rsp_data_o(coh_rsp_data_o),
        .cache_req_val_i(cache_req_val_i),
        .cache_req_rdy_o(cache_req_rdy_o),
        .cache_req_is_write_i(cache_req_is_write_i),
        .cache_req_addr_i(cache_req_addr_i),
        .cache_req_data_i(cache_req_data_i),
        .cache_rsp_val_o(cache_rsp_val_o),
        .cache_rsp_rdy_i(cache_rsp_rdy_i),
        .cache_rsp_data_o(cache_rsp_data_o),
        .m_axil_wr(m_axil),
        .m_axil_rd(m_axil)
    );
endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on UNDRIVEN */
/* verilator lint_on DECLFILENAME */
