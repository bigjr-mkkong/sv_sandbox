`timescale 1ns / 1ps

{% do unit_test(
    module_name = "togawa_pipeline",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/togawa_tb.py") %}
module togawa_pipeline (
    input  logic        clk_i,
    input  logic        rst_ni,

    // IF: cache valid/data describe the current word-indexed PC.
    output logic        icache_req_val_o,
    output logic [15:0] pc_o,
    input  logic        icache_req_rdy_i,

    input  logic        icache_val_i,
    input  logic [15:0] icache_inst_i,
    output logic        icache_rdy_o,

    output logic        dcache_req_val_o,
    input  logic        dcache_req_rdy_i,
    output logic        dcache_req_w,
    output logic [15:0] dcache_req_addr_o,
    output logic [15:0] dcache_req_data_o,

    input  logic        dcache_rsp_val_i,
    input  logic [15:0] dcache_rsp_data_i,
    output logic        dcache_rsp_rdy_o,

    output logic        halt
);

    logic [15:0] reg_d, reg_q;
    logic [15:0] reg_addr_d, reg_addr_q;
    logic reg_dirty_d, reg_dirty_q;

    // The only execution pipeline register: IF -> IDEXMEM.
    logic inst_valid_d, inst_valid_q;
    logic [15:0] inst_d, inst_q;

    logic [15:0] pc_d, pc_q;
    logic [15:0] branch_pc;
    logic halt_d, halt_q;
    logic stall, flush;

    typedef enum logic { IDLE, WAIT } dcache_state_t;
    dcache_state_t dcache_state_d, dcache_state_q;

    assign pc_o = pc_q;
    assign halt = halt_q && !reg_dirty_q && dcache_state_q == IDLE;
    wire _unused_ok = &{1'b0, icache_req_rdy_i};

    always_comb begin : idexmem_stage
        reg_d = reg_q;
        reg_addr_d = reg_addr_q;
        reg_dirty_d = reg_dirty_q;
        dcache_state_d = dcache_state_q;

        dcache_req_val_o = 1'b0;
        dcache_req_w = reg_dirty_q;
        dcache_req_addr_o = reg_dirty_q
            ? reg_addr_q : {inst_q[14:0], 1'b0};
        dcache_req_data_o = reg_q;
        dcache_rsp_rdy_o = 1'b0;
        stall = 1'b0;
        flush = 1'b0;
        branch_pc = pc_q;

        // HALT clears stage valid but still writes back a dirty word.
        if (rst_ni && !halt && (inst_valid_q || halt_q)) begin
            if (inst_q[15] || inst_q == 16'h0000) begin
                stall = 1'b1;
                case (dcache_state_q)
                    IDLE: begin
                        dcache_req_val_o = 1'b1;
                        if (dcache_req_rdy_i)
                            dcache_state_d = WAIT;
                    end
                    WAIT: begin
                        dcache_rsp_rdy_o = 1'b1;
                        if (dcache_rsp_val_i) begin
                            dcache_state_d = IDLE;
                            if (reg_dirty_q) begin
                                reg_dirty_d = 1'b0;
                            end else begin
                                reg_d = dcache_rsp_data_i;
                                reg_addr_d = {inst_q[14:0], 1'b0};
                                stall = 1'b0;
                            end
                        end
                    end
                endcase
            end else begin
                reg_d = reg_q ^ (16'h0001 << inst_q[14:11]);
                reg_dirty_d = 1'b1;
                // The old bit being one means the toggled bit is zero.
                flush = reg_q[inst_q[14:11]] && inst_q[10:0] != 11'd0;
                // IF already advanced PC past the executing instruction.
                branch_pc = pc_q + { {5{inst_q[10]}}, inst_q[10:0] };
            end
        end
    end

    always_comb begin : if_stage
        inst_valid_d = inst_valid_q && stall;
        inst_d = inst_q;
        pc_d = pc_q;
        halt_d = halt_q;

        icache_rdy_o = rst_ni && !halt_q && !stall;

        if (icache_val_i && icache_rdy_o && !flush) begin
            inst_d = icache_inst_i;
            inst_valid_d = 1'b1;
            pc_d = pc_q + 16'd1;
            if (icache_inst_i == 16'h0000) begin
                inst_valid_d = 1'b0;
                halt_d = 1'b1;
            end
        end

        if (flush) begin
            inst_valid_d = 1'b0;
            pc_d = branch_pc;
        end

        icache_req_val_o = rst_ni && !halt_d && !stall && !flush;
    end

    always_ff @(posedge clk_i) begin : if_idexmem_rf
        if (!rst_ni) begin
            inst_valid_q <= 1'b0;
            inst_q <= 16'd0;
        end else begin
            inst_valid_q <= inst_valid_d;
            inst_q <= inst_d;
        end
    end

    always_ff @(posedge clk_i) begin : state_rf
        if (!rst_ni) begin
            reg_q <= 16'd0;
            reg_addr_q <= 16'd0;
            reg_dirty_q <= 1'b0;
            pc_q <= 16'd0;
            dcache_state_q <= IDLE;
            halt_q <= 1'b0;
        end else begin
            reg_q <= reg_d;
            reg_addr_q <= reg_addr_d;
            reg_dirty_q <= reg_dirty_d;
            pc_q <= pc_d;
            dcache_state_q <= dcache_state_d;
            halt_q <= halt_d;
        end
    end

endmodule
