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
    logic [INDEX_BITS-1:0]                    index;
    coh_state                                  coh;
    logic                                      tag_we;
    logic [TAG_WIDTH-1:0]                     tag;
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

/*
 * Two-read, two-write cache bank. Remote and main commits complete together
 * when they address different rows. The parent cache must discard and retry a
 * stale local coherence decision before it becomes a main commit, so a
 * same-row dual commit is illegal. Remote priority is only a safety fallback
 * for that invariant violation.
 *
 * The behavioral array is the Verilator model and the generic synthesis
 * fallback. Its lookup/commit boundary is also the replacement boundary for
 * a technology-specific 2RW cache macro.
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

    input  logic [INDEX_BITS-1:0] main_lookup_idx_i,
    input  logic [TAG_WIDTH-1:0]  main_lookup_tag_i,
    output logic                  main_lookup_result_hit_o,
    output coh_state              main_lookup_result_coh_o,
    output logic [TAG_WIDTH-1:0]  main_lookup_result_tag_o,
    output logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] main_lookup_result_data_o,

    input  logic [INDEX_BITS-1:0] snoop_lookup_idx_i,
    input  logic [TAG_WIDTH-1:0]  snoop_lookup_tag_i,
    output logic                  snoop_lookup_result_hit_o,
    output coh_state              snoop_lookup_result_coh_o,
    output logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] snoop_lookup_result_data_o,

    cache_commit_if.consumer remote_commit,
    cache_commit_if.consumer main_commit
);
{% if not RENDER_OPTION.SYNTH %}
    // Below circuits only works in simulation. For real nangate45, we only
    // have 1rw sram module. Below structure need to be re-designed
    // The cache would be too large and it can't even finish synthesize
    typedef struct packed {
        coh_state                                  coh;
        logic [TAG_WIDTH-1:0]                     line_tag;
        logic [DATA_PER_LINE-1:0][DATA_WIDTH-1:0] line_data;
    } cache_line_t;

    cache_line_t cache [ROW_CNT-1:0];
    logic same_row_commit;

    always_comb begin
        main_lookup_result_hit_o = cache[main_lookup_idx_i].coh != COH_Invalid && cache[main_lookup_idx_i].line_tag == main_lookup_tag_i;
        main_lookup_result_coh_o = cache[main_lookup_idx_i].coh;
        main_lookup_result_tag_o = cache[main_lookup_idx_i].line_tag;
        main_lookup_result_data_o = cache[main_lookup_idx_i].line_data;

        snoop_lookup_result_hit_o = cache[snoop_lookup_idx_i].coh != COH_Invalid && cache[snoop_lookup_idx_i].line_tag == snoop_lookup_tag_i;
        snoop_lookup_result_coh_o = snoop_lookup_result_hit_o ? cache[snoop_lookup_idx_i].coh : COH_Invalid;
        snoop_lookup_result_data_o = cache[snoop_lookup_idx_i].line_data;

        // A 2RW bank does not serialize its independent commit ports.
        remote_commit.rdy = 1'b1;
        main_commit.rdy = 1'b1;
        same_row_commit = remote_commit.val && main_commit.val
            && remote_commit.index == main_commit.index;
    end

    // Below  cache block update is only possible in simulation
    // It's almost impossible to synthesize such a big cache
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
          for (int unsigned i = 0; i < ROW_CNT; i++) begin
              cache[i].coh <= COH_Invalid;
          end
        end else begin
            if (remote_commit.val && remote_commit.rdy) begin
                cache[remote_commit.index].coh <= remote_commit.coh;
                if (remote_commit.tag_we) begin
                    cache[remote_commit.index].line_tag <= remote_commit.tag;
                end
                if (remote_commit.data_we) begin
                    cache[remote_commit.index].line_data <= remote_commit.data;
                end
            end

            if (main_commit.val && main_commit.rdy && !same_row_commit) begin
                cache[main_commit.index].coh <= main_commit.coh;
                if (main_commit.tag_we) begin
                    cache[main_commit.index].line_tag <= main_commit.tag;
                end
                if (main_commit.data_we) begin
                    cache[main_commit.index].line_data <= main_commit.data;
                end
            end
        end
    end

{% else %}
//TODO
//Fill this area with 2rw sram module from nang45 library
{% endif %}

{% if not RENDER_OPTION.SYNTH %}
    assert property (@(posedge clk_i) disable iff (!rst_ni)
        !same_row_commit
    ) else $error(
        "same-row remote/main commits escaped cache coherence serialization"
    );

    assert property (@(posedge clk_i) disable iff (!rst_ni)
        remote_commit.rdy && main_commit.rdy
    ) else $error("both 2RW cache commit ports must remain ready");
{% endif %}

endmodule
