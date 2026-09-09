`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
import config_pkg::*;

interface cache_commit_if #(
    parameter int unsigned INDEX_BITS    = 8,
    parameter int unsigned TAG_WIDTH     = 50,
    parameter int unsigned DATA_WIDTH    = 64,
    parameter int unsigned DATA_PER_LINE = 8
) ();
    logic                                      val;
    logic                                      rdy;
    logic [INDEX_BITS-1:0]                     index;
    coh_state                                  coh;
    logic                                      tag_we;
    logic [TAG_WIDTH-1:0]                      tag;
    logic                                      data_we;
    logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] data;

    modport producer (
        output val,
        input  rdy,
        output index,
        output coh,
        output tag_we,
        output tag,
        output data_we,
        output data
    );

    modport consumer (
        input  val,
        output rdy,
        input  index,
        input  coh,
        input  tag_we,
        input  tag,
        input  data_we,
        input  data
    );
endinterface

interface cache_snoop_if #(
    parameter int unsigned INDEX_BITS    = 8,
    parameter int unsigned TAG_WIDTH     = 50,
    parameter int unsigned DATA_WIDTH    = 64,
    parameter int unsigned DATA_PER_LINE = 8
) ();
    logic                                      req_val;
    logic                                      req_rdy;
    logic [INDEX_BITS-1:0]                     idx;
    logic [TAG_WIDTH-1:0]                      tag;
    logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] rsp_data;
    logic [TAG_WIDTH-1:0]                      rsp_tag;
    logic                                      rsp_hit;
    coh_state                                  rsp_coh;
    logic                                      rsp_val;
    logic                                      rsp_rdy;

    modport producer (
        output req_val,
        input  req_rdy,
        output idx,
        output tag,
        input  rsp_data,
        input  rsp_tag,
        input  rsp_hit,
        input  rsp_coh,
        input  rsp_val,
        output rsp_rdy
    );

    modport consumer (
        input  req_val,
        output req_rdy,
        input  idx,
        input  tag,
        output rsp_data,
        output rsp_tag,
        output rsp_hit,
        output rsp_coh,
        output rsp_val,
        input  rsp_rdy
    );
endinterface

/*
 * Globally blocking cache-storage manager.
 *
 * A write handshake is its execution event: the selected state/tag/data
 * update occurs on that edge. Reads occupy the manager until their registered
 * response is consumed. Arbitration priority is remote write, remote read,
 * main write, then main read. An active read is never preempted.
 */
{% do unit_test(
    module_name = "cache_committer",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/cache_committer_tb.py") %}
module cache_committer #(
    parameter int unsigned ROW_CNT       = 256,
    parameter int unsigned INDEX_BITS    = 8,
    parameter int unsigned TAG_WIDTH     = 50,
    parameter int unsigned DATA_WIDTH    = 64,
    parameter int unsigned DATA_PER_LINE = 8
) (
    input logic clk_i,
    input logic rst_ni,
    output logic reset_fin_o,

    input  logic [INDEX_BITS-1:0] coh_probe_idx_i,
    output coh_state              coh_probe_o,

    cache_commit_if.consumer remote_commit,
    cache_commit_if.consumer main_commit,
    cache_snoop_if.consumer  remote_snoop,
    cache_snoop_if.consumer  main_snoop
);
    localparam int unsigned LINE_WIDTH = DATA_WIDTH * DATA_PER_LINE;

    typedef enum logic [1:0] {
        IDLE,
        READ_CAPTURE,
        READ_RESP
    } state_e;

    typedef enum logic {
        REMOTE_OWNER,
        MAIN_OWNER
    } read_owner_e;

    state_e state_d, state_q;
    read_owner_e read_owner_d, read_owner_q;

    logic selected_v;
    logic selected_write;
    logic selected_tag_we;
    logic selected_data_we;
    logic [INDEX_BITS-1:0] selected_index;
    logic [TAG_WIDTH-1:0] selected_tag;
    coh_state selected_coh;
    logic [LINE_WIDTH-1:0] selected_data;
    read_owner_e selected_read_owner;

    logic access_fire;
    logic write_fire;
    logic read_fire;
    logic tag_bank_v;
    logic data_bank_v;
    logic [63:0] tag_bank_data_i;
    logic [63:0] tag_bank_data_o;
    logic [DATA_PER_LINE-1:0][63:0] data_bank_data_o;

    logic [INDEX_BITS-1:0] read_index_d, read_index_q;
    logic [TAG_WIDTH-1:0] read_requested_tag_d, read_requested_tag_q;
    logic [TAG_WIDTH-1:0] rsp_tag_d, rsp_tag_q;
    logic rsp_hit_d, rsp_hit_q;
    coh_state rsp_coh_d, rsp_coh_q;
    logic [LINE_WIDTH-1:0] rsp_data_d, rsp_data_q;

    logic reset_fin_q;
    logic [INDEX_BITS-1:0] reset_idx_q;

    coh_state coh_array [ROW_CNT-1:0];

{% if not RENDER_OPTION.SYNTH %}
    typedef struct packed {
        coh_state                                  coh;
        logic [TAG_WIDTH-1:0]                     tag;
        logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] data;
    } observed_cache_line_t;

    // Verification-only row view, updated by the same execution event and
    // write enables as the physical storage. It never drives cache responses.
    observed_cache_line_t pseudo_cache [ROW_CNT-1:0];
{% endif %}

    always_comb begin
        selected_v = 1'b0;
        selected_write = 1'b0;
        selected_tag_we = 1'b0;
        selected_data_we = 1'b0;
        selected_index = '0;
        selected_tag = '0;
        selected_coh = COH_Invalid;
        selected_data = '0;
        selected_read_owner = REMOTE_OWNER;

        remote_commit.rdy = 1'b0;
        remote_snoop.req_rdy = 1'b0;
        main_commit.rdy = 1'b0;
        main_snoop.req_rdy = 1'b0;

        if (reset_fin_o && state_q == IDLE) begin
            if (remote_commit.val) begin
                selected_v = 1'b1;
                selected_write = 1'b1;
                selected_tag_we = remote_commit.tag_we;
                selected_data_we = remote_commit.data_we;
                selected_index = remote_commit.index;
                selected_tag = remote_commit.tag;
                selected_coh = remote_commit.coh;
                selected_data = remote_commit.data;
                remote_commit.rdy = 1'b1;
            end else if (remote_snoop.req_val) begin
                selected_v = 1'b1;
                selected_index = remote_snoop.idx;
                selected_tag = remote_snoop.tag;
                selected_read_owner = REMOTE_OWNER;
                remote_snoop.req_rdy = 1'b1;
            end else if (main_commit.val) begin
                selected_v = 1'b1;
                selected_write = 1'b1;
                selected_tag_we = main_commit.tag_we;
                selected_data_we = main_commit.data_we;
                selected_index = main_commit.index;
                selected_tag = main_commit.tag;
                selected_coh = main_commit.coh;
                selected_data = main_commit.data;
                main_commit.rdy = 1'b1;
            end else if (main_snoop.req_val) begin
                selected_v = 1'b1;
                selected_index = main_snoop.idx;
                selected_tag = main_snoop.tag;
                selected_read_owner = MAIN_OWNER;
                main_snoop.req_rdy = 1'b1;
            end
        end
    end

    assign access_fire = selected_v && state_q == IDLE;
    assign write_fire = access_fire && selected_write;
    assign read_fire = access_fire && !selected_write;
    assign tag_bank_v = read_fire || (write_fire && selected_tag_we);
    assign data_bank_v = read_fire || (write_fire && selected_data_we);
    assign tag_bank_data_i = 64'(selected_tag);

    cache_bank tag_bank (
        .clk_i,
        .reset_i(!rst_ni),
        .v_i(tag_bank_v),
        .w_i(write_fire),
        .addr_i(selected_index),
        .data_i(tag_bank_data_i),
        .data_o(tag_bank_data_o)
    );

    for (genvar word = 0; word < DATA_PER_LINE; word++) begin : gen_data_bank
        cache_bank data_bank (
            .clk_i,
            .reset_i(!rst_ni),
            .v_i(data_bank_v),
            .w_i(write_fire),
            .addr_i(selected_index),
            .data_i(selected_data[word*DATA_WIDTH +: DATA_WIDTH]),
            .data_o(data_bank_data_o[word])
        );
    end

    always_comb begin
        state_d = state_q;
        read_owner_d = read_owner_q;
        read_index_d = read_index_q;
        read_requested_tag_d = read_requested_tag_q;
        rsp_tag_d = rsp_tag_q;
        rsp_hit_d = rsp_hit_q;
        rsp_coh_d = rsp_coh_q;
        rsp_data_d = rsp_data_q;

        if (read_fire) begin
            read_owner_d = selected_read_owner;
            read_index_d = selected_index;
            read_requested_tag_d = selected_tag;
            state_d = READ_CAPTURE;
        end

        if (state_q == READ_CAPTURE) begin
            rsp_tag_d = tag_bank_data_o[TAG_WIDTH-1:0];
            rsp_coh_d = coh_array[read_index_q];
            rsp_data_d = data_bank_data_o;
            rsp_hit_d = coh_array[read_index_q] != COH_Invalid
                && tag_bank_data_o[TAG_WIDTH-1:0]
                    == read_requested_tag_q;
            state_d = READ_RESP;
        end

        if (state_q == READ_RESP) begin
            if (read_owner_q == REMOTE_OWNER
                    && remote_snoop.rsp_rdy) begin
                state_d = IDLE;
            end else if (read_owner_q == MAIN_OWNER
                         && main_snoop.rsp_rdy) begin
                state_d = IDLE;
            end
        end
    end

    assign remote_snoop.rsp_val = state_q == READ_RESP
        && read_owner_q == REMOTE_OWNER;
    assign main_snoop.rsp_val = state_q == READ_RESP
        && read_owner_q == MAIN_OWNER;

    assign remote_snoop.rsp_tag = rsp_tag_q;
    assign remote_snoop.rsp_hit = rsp_hit_q;
    assign remote_snoop.rsp_coh = rsp_coh_q;
    assign remote_snoop.rsp_data = rsp_data_q;
    assign main_snoop.rsp_tag = rsp_tag_q;
    assign main_snoop.rsp_hit = rsp_hit_q;
    assign main_snoop.rsp_coh = rsp_coh_q;
    assign main_snoop.rsp_data = rsp_data_q;

    assign reset_fin_o = rst_ni && reset_fin_q;
    assign coh_probe_o = reset_fin_o
        ? coh_array[coh_probe_idx_i] : COH_Invalid;

    // Invalidate one row per cycle, then allow normal cache traffic. Keep
    // initialization and commits together so coh_array has a single writer.
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            reset_fin_q <= 1'b0;
            reset_idx_q <= '0;
        end else if (!reset_fin_q) begin
            coh_array[reset_idx_q] <= COH_Invalid;
            if (reset_idx_q == INDEX_BITS'(ROW_CNT-1)) begin
                reset_fin_q <= 1'b1;
            end else begin
                reset_idx_q <= reset_idx_q + 1'b1;
            end
        end else if (write_fire) begin
            coh_array[selected_index] <= selected_coh;
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            read_owner_q <= REMOTE_OWNER;
            read_index_q <= '0;
            read_requested_tag_q <= '0;
            rsp_tag_q <= '0;
            rsp_hit_q <= 1'b0;
            rsp_coh_q <= COH_Invalid;
            rsp_data_q <= '0;
{% if not RENDER_OPTION.SYNTH %}
            for (int unsigned i = 0; i < ROW_CNT; i++) begin
                // Tag/data are deterministic for inspection, but invalid
                // rows do not imply initialized physical SRAM contents.
                pseudo_cache[i] <= '{coh: COH_Invalid, default: '0};
            end
{% endif %}
        end else begin
            state_q <= state_d;
            read_owner_q <= read_owner_d;
            read_index_q <= read_index_d;
            read_requested_tag_q <= read_requested_tag_d;
            rsp_tag_q <= rsp_tag_d;
            rsp_hit_q <= rsp_hit_d;
            rsp_coh_q <= rsp_coh_d;
            rsp_data_q <= rsp_data_d;

            if (write_fire) begin
{% if not RENDER_OPTION.SYNTH %}
                pseudo_cache[selected_index].coh <= selected_coh;
                if (selected_tag_we) begin
                    pseudo_cache[selected_index].tag <= selected_tag;
                end
                if (selected_data_we) begin
                    pseudo_cache[selected_index].data <= selected_data;
                end
{% endif %}
            end
        end
    end

{% if not RENDER_OPTION.SYNTH %}
    initial begin
        assert (ROW_CNT == 256)
            else $error("cache_bank requires exactly 256 rows");
        assert (INDEX_BITS == 8)
            else $error("cache_bank requires an eight-bit index");
        assert (TAG_WIDTH <= 64)
            else $error("the cache tag must fit in its 64-bit bank");
        assert (DATA_WIDTH == 64)
            else $error("cache_bank has a fixed 64-bit data width");
        assert (DATA_PER_LINE == 8)
            else $error("the cache committer requires eight data banks");
    end

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        remote_snoop.rsp_val && !remote_snoop.rsp_rdy
        |=> remote_snoop.rsp_val
            && $stable(remote_snoop.rsp_tag)
            && $stable(remote_snoop.rsp_hit)
            && $stable(remote_snoop.rsp_coh)
            && $stable(remote_snoop.rsp_data)
    ) else $error("remote cache lookup response changed under backpressure");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        main_snoop.rsp_val && !main_snoop.rsp_rdy
        |=> main_snoop.rsp_val
            && $stable(main_snoop.rsp_tag)
            && $stable(main_snoop.rsp_hit)
            && $stable(main_snoop.rsp_coh)
            && $stable(main_snoop.rsp_data)
    ) else $error("main cache lookup response changed under backpressure");

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        reset_fin_o && remote_commit.val && main_commit.val && state_q == IDLE
        |-> remote_commit.rdy && !main_commit.rdy
    ) else $error("remote commit did not win cache-bank arbitration");
{% endif %}
endmodule
/* verilator lint_on DECLFILENAME */
