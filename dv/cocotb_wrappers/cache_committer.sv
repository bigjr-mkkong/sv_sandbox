`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNDRIVEN */
module cache_committer_unit_test;
    localparam int unsigned ROW_CNT = 4;
    localparam int unsigned INDEX_BITS = 2;
    localparam int unsigned TAG_WIDTH = 4;
    localparam int unsigned DATA_WIDTH = 8;
    localparam int unsigned DATA_PER_LINE = 2;
    localparam int unsigned LINE_WIDTH = DATA_WIDTH * DATA_PER_LINE;

    logic clk_i;
    logic rst_ni;

    logic [INDEX_BITS-1:0] main_lookup_idx_i;
    logic [TAG_WIDTH-1:0] main_lookup_tag_i;
    logic main_lookup_result_hit_o;
    logic [1:0] main_lookup_result_coh_o;
    logic [TAG_WIDTH-1:0] main_lookup_result_tag_o;
    logic [LINE_WIDTH-1:0] main_lookup_result_data_o;

    logic [INDEX_BITS-1:0] snoop_lookup_idx_i;
    logic [TAG_WIDTH-1:0] snoop_lookup_tag_i;
    logic snoop_lookup_result_hit_o;
    logic [1:0] snoop_lookup_result_coh_o;
    logic [LINE_WIDTH-1:0] snoop_lookup_result_data_o;

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

    coh_state main_lookup_result_coh;
    coh_state snoop_lookup_result_coh;

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

    assign main_lookup_result_coh_o = main_lookup_result_coh;
    assign snoop_lookup_result_coh_o = snoop_lookup_result_coh;

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

    cache_committer #(
        .ROW_CNT(ROW_CNT),
        .INDEX_BITS(INDEX_BITS),
        .TAG_WIDTH(TAG_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_PER_LINE(DATA_PER_LINE)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .main_lookup_idx_i(main_lookup_idx_i),
        .main_lookup_tag_i(main_lookup_tag_i),
        .main_lookup_result_hit_o(main_lookup_result_hit_o),
        .main_lookup_result_coh_o(main_lookup_result_coh),
        .main_lookup_result_tag_o(main_lookup_result_tag_o),
        .main_lookup_result_data_o(main_lookup_result_data_o),
        .snoop_lookup_idx_i(snoop_lookup_idx_i),
        .snoop_lookup_tag_i(snoop_lookup_tag_i),
        .snoop_lookup_result_hit_o(snoop_lookup_result_hit_o),
        .snoop_lookup_result_coh_o(snoop_lookup_result_coh),
        .snoop_lookup_result_data_o(snoop_lookup_result_data_o),
        .remote_commit(remote_commit),
        .main_commit(main_commit)
    );
endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on DECLFILENAME */
