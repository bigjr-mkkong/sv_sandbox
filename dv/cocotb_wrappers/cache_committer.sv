`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNDRIVEN */
module cache_committer_unit_test;
    localparam int unsigned ROW_CNT = 256;
    localparam int unsigned INDEX_BITS = 8;
    localparam int unsigned TAG_WIDTH = 50;
    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned DATA_PER_LINE = 8;
    localparam int unsigned LINE_WIDTH = DATA_WIDTH * DATA_PER_LINE;

    logic clk_i;
    logic rst_ni;
    logic reset_fin_o;

    logic [INDEX_BITS-1:0] coh_probe_idx_i;
    logic [1:0] coh_probe_o;

    logic remote_commit_val_i;
    logic remote_commit_rdy_o;
    logic [INDEX_BITS-1:0] remote_commit_index_i;
    logic [1:0] remote_commit_coh_i;
    logic remote_commit_tag_we_i;
    logic [TAG_WIDTH-1:0] remote_commit_tag_i;
    logic remote_commit_data_we_i;
    logic [LINE_WIDTH-1:0] remote_commit_data_i;

    logic main_commit_val_i;
    logic main_commit_rdy_o;
    logic [INDEX_BITS-1:0] main_commit_index_i;
    logic [1:0] main_commit_coh_i;
    logic main_commit_tag_we_i;
    logic [TAG_WIDTH-1:0] main_commit_tag_i;
    logic main_commit_data_we_i;
    logic [LINE_WIDTH-1:0] main_commit_data_i;

    logic remote_snoop_req_val_i;
    logic remote_snoop_req_rdy_o;
    logic [INDEX_BITS-1:0] remote_snoop_idx_i;
    logic [TAG_WIDTH-1:0] remote_snoop_tag_i;
    logic remote_snoop_rsp_val_o;
    logic remote_snoop_rsp_rdy_i;
    logic [LINE_WIDTH-1:0] remote_snoop_rsp_data_o;
    logic [TAG_WIDTH-1:0] remote_snoop_rsp_tag_o;
    logic remote_snoop_rsp_hit_o;
    logic [1:0] remote_snoop_rsp_coh_o;

    logic main_snoop_req_val_i;
    logic main_snoop_req_rdy_o;
    logic [INDEX_BITS-1:0] main_snoop_idx_i;
    logic [TAG_WIDTH-1:0] main_snoop_tag_i;
    logic main_snoop_rsp_val_o;
    logic main_snoop_rsp_rdy_i;
    logic [LINE_WIDTH-1:0] main_snoop_rsp_data_o;
    logic [TAG_WIDTH-1:0] main_snoop_rsp_tag_o;
    logic main_snoop_rsp_hit_o;
    logic [1:0] main_snoop_rsp_coh_o;

    cache_commit_if #(
        .INDEX_BITS(INDEX_BITS),
        .TAG_WIDTH(TAG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) remote_commit();

    cache_commit_if #(
        .INDEX_BITS(INDEX_BITS),
        .TAG_WIDTH(TAG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) main_commit();

    cache_snoop_if #(
        .INDEX_BITS(INDEX_BITS),
        .TAG_WIDTH(TAG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) remote_snoop();

    cache_snoop_if #(
        .INDEX_BITS(INDEX_BITS),
        .TAG_WIDTH(TAG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) main_snoop();

    assign remote_commit.val = remote_commit_val_i;
    assign remote_commit_rdy_o = remote_commit.rdy;
    assign remote_commit.index = remote_commit_index_i;
    assign remote_commit.coh = coh_state'(remote_commit_coh_i);
    assign remote_commit.tag_we = remote_commit_tag_we_i;
    assign remote_commit.tag = remote_commit_tag_i;
    assign remote_commit.data_we = remote_commit_data_we_i;
    assign remote_commit.data = remote_commit_data_i;

    assign main_commit.val = main_commit_val_i;
    assign main_commit_rdy_o = main_commit.rdy;
    assign main_commit.index = main_commit_index_i;
    assign main_commit.coh = coh_state'(main_commit_coh_i);
    assign main_commit.tag_we = main_commit_tag_we_i;
    assign main_commit.tag = main_commit_tag_i;
    assign main_commit.data_we = main_commit_data_we_i;
    assign main_commit.data = main_commit_data_i;

    assign remote_snoop.req_val = remote_snoop_req_val_i;
    assign remote_snoop_req_rdy_o = remote_snoop.req_rdy;
    assign remote_snoop.idx = remote_snoop_idx_i;
    assign remote_snoop.tag = remote_snoop_tag_i;
    assign remote_snoop_rsp_val_o = remote_snoop.rsp_val;
    assign remote_snoop.rsp_rdy = remote_snoop_rsp_rdy_i;
    assign remote_snoop_rsp_data_o = remote_snoop.rsp_data;
    assign remote_snoop_rsp_tag_o = remote_snoop.rsp_tag;
    assign remote_snoop_rsp_hit_o = remote_snoop.rsp_hit;
    assign remote_snoop_rsp_coh_o = remote_snoop.rsp_coh;

    assign main_snoop.req_val = main_snoop_req_val_i;
    assign main_snoop_req_rdy_o = main_snoop.req_rdy;
    assign main_snoop.idx = main_snoop_idx_i;
    assign main_snoop.tag = main_snoop_tag_i;
    assign main_snoop_rsp_val_o = main_snoop.rsp_val;
    assign main_snoop.rsp_rdy = main_snoop_rsp_rdy_i;
    assign main_snoop_rsp_data_o = main_snoop.rsp_data;
    assign main_snoop_rsp_tag_o = main_snoop.rsp_tag;
    assign main_snoop_rsp_hit_o = main_snoop.rsp_hit;
    assign main_snoop_rsp_coh_o = main_snoop.rsp_coh;

    coh_state coh_probe;
    assign coh_probe_o = coh_probe;

    cache_committer #(
        .ROW_CNT(ROW_CNT),
        .INDEX_BITS(INDEX_BITS),
        .TAG_WIDTH(TAG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) dut (
        .clk_i,
        .rst_ni,
        .reset_fin_o,
        .coh_probe_idx_i,
        .coh_probe_o(coh_probe),
        .remote_commit,
        .main_commit,
        .remote_snoop,
        .main_snoop
    );
endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on DECLFILENAME */
