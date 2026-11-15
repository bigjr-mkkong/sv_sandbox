`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
module two2one_spi_arbiter_unit_test (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic [15:0] instruction_response_i,

    input  logic        src0_req_val_i,
    output logic        src0_req_rdy_o,
    input  logic        src0_req_we_i,
    input  logic        src0_req_is_inst_i,
    input  logic [15:0] src0_req_addr_i,
    input  logic [7:0]  src0_req_wdata_i,
    output logic        src0_rsp_val_o,
    output logic [7:0]  src0_rsp_rdata_o,
    output logic [15:0] src0_rsp_rinst_o,
    input  logic        src0_rsp_rdy_i,

    input  logic        src1_req_val_i,
    output logic        src1_req_rdy_o,
    input  logic        src1_req_we_i,
    input  logic        src1_req_is_inst_i,
    input  logic [15:0] src1_req_addr_i,
    input  logic [7:0]  src1_req_wdata_i,
    output logic        src1_rsp_val_o,
    output logic [7:0]  src1_rsp_rdata_o,
    output logic [15:0] src1_rsp_rinst_o,
    input  logic        src1_rsp_rdy_i
);
    spi_ram_if #(.DATA_W(8)) if_src_inst[2]();
    spi_ram_if #(.DATA_W(8)) if_sink_inst();

    assign if_src_inst[0].req_val = src0_req_val_i;
    assign if_src_inst[0].req_we = src0_req_we_i;
    assign if_src_inst[0].req_is_inst = src0_req_is_inst_i;
    assign if_src_inst[0].req_addr = src0_req_addr_i;
    assign if_src_inst[0].req_wdata = src0_req_wdata_i;
    assign if_src_inst[0].rsp_rdy = src0_rsp_rdy_i;
    assign src0_req_rdy_o = if_src_inst[0].req_rdy;
    assign src0_rsp_val_o = if_src_inst[0].rsp_val;
    assign src0_rsp_rdata_o = if_src_inst[0].rsp_rdata;
    assign src0_rsp_rinst_o = if_src_inst[0].rsp_rinst;

    assign if_src_inst[1].req_val = src1_req_val_i;
    assign if_src_inst[1].req_we = src1_req_we_i;
    assign if_src_inst[1].req_is_inst = src1_req_is_inst_i;
    assign if_src_inst[1].req_addr = src1_req_addr_i;
    assign if_src_inst[1].req_wdata = src1_req_wdata_i;
    assign if_src_inst[1].rsp_rdy = src1_rsp_rdy_i;
    assign src1_req_rdy_o = if_src_inst[1].req_rdy;
    assign src1_rsp_val_o = if_src_inst[1].rsp_val;
    assign src1_rsp_rdata_o = if_src_inst[1].rsp_rdata;
    assign src1_rsp_rinst_o = if_src_inst[1].rsp_rinst;
    // Inject a distinct instruction payload on the ideal memory response pulse.
    assign if_sink_inst.rsp_rinst = instruction_response_i;

    two2one_spi_arbiter two2one_spi_arbiter_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .slvs_i(if_src_inst),
        .mst_o(if_sink_inst)
    );

    ideal_spi_ram ideal_spi_ram_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .req_val(if_sink_inst.req_val),
        .req_rdy(if_sink_inst.req_rdy),
        .req_we(if_sink_inst.req_we),
        .req_addr(if_sink_inst.req_addr),
        .req_wdata(if_sink_inst.req_wdata),
        .resp_val(if_sink_inst.rsp_val),
        .resp_rdata(if_sink_inst.rsp_rdata)
    );
endmodule
/* verilator lint_on DECLFILENAME */
