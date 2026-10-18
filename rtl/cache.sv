`timescale 1ns / 1ps

module sram_blk #(
    parameter int unsigned DATA_W = 16,
    parameter int unsigned DEPTH  = 16,
    parameter int unsigned ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic              clk_i,
    input  logic              rst_ni,

    input  logic              req_val_i,
    output logic              req_rdy_o,
    input  logic              req_is_write_i,
    input  logic [ADDR_W-1:0] req_addr_i,
    input  logic [DATA_W-1:0] req_data_i,

    output logic              rsp_val_o,
    input  logic              rsp_rdy_i,
    output logic [DATA_W-1:0] rsp_data_o
);

    typedef enum logic {
        IDLE,
        RESP
    } state_e;

    state_e state_q, state_d;

    logic              rsp_is_write_q;
    logic [DATA_W-1:0] mem_rdata;

    /*
    * Since there will only be a 16x16 dff array
    * It's actually possible to directly synthesize into a dff
    * We don't get compatible sram macro for sky130
    * So here we will directly use basejump model into synthesize
    *
    * Notice 16x16 is not harden in basejump so it has risk
    */
    bsg_mem_1rw_sync #(
        .width_p           (DATA_W),
        .els_p             (DEPTH),
        .latch_last_read_p (1)
    ) bsg_mem_inst (
        .clk_i   (clk_i),
        .reset_i (!rst_ni),

        .v_i     (req_val_i && req_rdy_o),
        .w_i     (req_is_write_i),

        .addr_i  (req_addr_i),
        .data_i  (req_data_i),
        .data_o  (mem_rdata)
    );

    always_comb begin
        state_d = state_q;
        req_rdy_o = 0;
        rsp_val_o = 0;
        rsp_data_o = rsp_is_write_q ? '0 : mem_rdata;

        case (state_q)
            IDLE: begin
                req_rdy_o = rst_ni;
                if (req_val_i && req_rdy_o)
                    state_d = RESP;
            end

            RESP: begin
                req_rdy_o = rst_ni && rsp_rdy_i;
                rsp_val_o = rst_ni;
                if (req_val_i && req_rdy_o)
                    state_d = RESP;
                else if (rsp_val_o && rsp_rdy_i)
                    state_d = IDLE;
            end

            default: begin
                state_d = IDLE;
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state_q        <= IDLE;
            rsp_is_write_q <= 1'b0;
        end else begin
            state_q <= state_d;

            if (req_val_i && req_rdy_o)
                rsp_is_write_q <= req_is_write_i;
        end
    end

endmodule

{% do unit_test(
    module_name = "iram_blk",
    test_framework = "cocotb",
    use_wrapper = true,
    rtl_dependencies = ["rtl/spi_master.sv"],
    test_path = "dv/cocotb_benches/iram_tb.py") %}
module iram_blk #(
    parameter int unsigned DATA_W = 16,
    parameter int unsigned DEPTH  = 16,
    parameter int unsigned ADDR_W = 16
) (
    input  logic              clk_i,
    input  logic              rst_ni,

    input  logic              req_val_i,
    input  logic [ADDR_W-1:0] pc_i,
    output logic              req_rdy_o,

    output logic              rsp_val_o,
    output logic [DATA_W-1:0] inst_o,
    input  logic              rsp_rdy_i,

    output logic              iram_val_o,
    output logic [15:0]       iram_new_pc_o,
    input  logic              spi_rdy_i,
    input  logic              spi_val_i,
    input  logic [7:0]        spi_data_i
);

    localparam int unsigned INDEX_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    typedef enum logic [1:0] {
        IDLE,
        RESP_PIPELINE,
        MISS_REQUEST,
        MISS_REFILL
    } state_e;

    state_e state_d, state_q;
    logic sram_req_val, sram_req_rdy, sram_is_write;
    logic sram_rsp_val, sram_rsp_rdy;
    logic [INDEX_W-1:0] sram_addr;
    logic [7:0] sram_refill_data_q, sram_refill_data_d;
    logic byte_q, byte_d;
    logic [INDEX_W-1:0] addr_ofst_q, addr_ofst_d;
    logic [ADDR_W-1:0] req_pc_q, req_pc_d;
    logic [ADDR_W-1:0] iram_window_begin_q, iram_window_begin_d;
    logic iram_window_valid_q, iram_window_valid_d;

    // Convert the word PC to a byte address in the 64 KiB SPI address space.
    assign iram_new_pc_o = 16'({ADDR_W'(req_pc_q + ADDR_W'(addr_ofst_q)), byte_q});

    sram_blk #(
        .DATA_W(DATA_W),
        .DEPTH(DEPTH),
        .ADDR_W(INDEX_W)
    ) sram_blk_inst (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .req_val_i(sram_req_val),
        .req_rdy_o(sram_req_rdy),
        .req_is_write_i(sram_is_write),
        .req_addr_i(sram_addr),
        .req_data_i({spi_data_i, sram_refill_data_q}),
        .rsp_val_o(sram_rsp_val),
        .rsp_rdy_i(sram_rsp_rdy),
        .rsp_data_o(inst_o)
    );

    always_comb begin
        state_d = state_q;
        req_pc_d = req_pc_q;
        addr_ofst_d = addr_ofst_q;
        byte_d = byte_q;
        sram_refill_data_d = sram_refill_data_q;
        iram_window_begin_d = iram_window_begin_q;
        iram_window_valid_d = iram_window_valid_q;

        req_rdy_o = 1'b0;
        rsp_val_o = 1'b0;
        iram_val_o = 1'b0;
        sram_req_val = 1'b0;
        sram_is_write = 1'b0;
        sram_addr = INDEX_W'(pc_i - iram_window_begin_q);
        sram_rsp_rdy = 1'b1;

        if (rst_ni) begin
            case (state_q)
                IDLE: begin
                    req_rdy_o = sram_req_rdy;
                    if (req_val_i && sram_req_rdy) begin
                        req_pc_d = pc_i;
                        // Truncate the distance so windows can wrap around the PC space.
                        if (iram_window_valid_q
                            && int'(ADDR_W'(pc_i - iram_window_begin_q)) < DEPTH) begin
                            sram_req_val = 1'b1;
                            state_d = RESP_PIPELINE;
                        end else begin
                            addr_ofst_d = '0;
                            byte_d = 1'b0;
                            iram_window_valid_d = 1'b0;
                            state_d = MISS_REQUEST;
                        end
                    end
                end

                RESP_PIPELINE: begin
                    if (sram_rsp_val) begin
                        if (pc_i != req_pc_q) begin
                            state_d = IDLE;
                        end else begin
                            // Valid must not depend on req_val_i: HALT withdraws it.
                            rsp_val_o = 1'b1;
                            sram_rsp_rdy = rsp_rdy_i;
                            if (rsp_rdy_i)
                                state_d = IDLE;
                        end
                    end
                end

                MISS_REQUEST: begin
                    iram_val_o = 1'b1;
                    if (spi_rdy_i)
                        state_d = MISS_REFILL;
                end

                MISS_REFILL: begin
                    if (iram_window_valid_q) begin
                        // Drain the last write acknowledgement while reading the requested word.
                        sram_req_val = 1'b1;
                        sram_addr = '0;
                        if (sram_req_rdy)
                            state_d = RESP_PIPELINE;
                    end else if (spi_val_i) begin
                        if (!byte_q) begin
                            sram_refill_data_d = spi_data_i;
                            byte_d = 1'b1;
                            state_d = MISS_REQUEST;
                        end else begin
                            sram_req_val = 1'b1;
                            sram_is_write = 1'b1;
                            sram_addr = addr_ofst_q;
                            if (sram_req_rdy) begin
                                byte_d = 1'b0;
                                addr_ofst_d = addr_ofst_q + 1'b1;
                                if (addr_ofst_q == INDEX_W'(DEPTH - 1)) begin
                                    iram_window_begin_d = req_pc_q;
                                    iram_window_valid_d = 1'b1;
                                end else begin
                                    state_d = MISS_REQUEST;
                                end
                            end
                        end
                    end
                end

                default: state_d = IDLE;
            endcase
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            req_pc_q <= '0;
            addr_ofst_q <= '0;
            byte_q <= 1'b0;
            sram_refill_data_q <= '0;
            iram_window_begin_q <= '0;
            iram_window_valid_q <= 1'b0;
        end else begin
            state_q <= state_d;
            req_pc_q <= req_pc_d;
            addr_ofst_q <= addr_ofst_d;
            byte_q <= byte_d;
            sram_refill_data_q <= sram_refill_data_d;
            iram_window_begin_q <= iram_window_begin_d;
            iram_window_valid_q <= iram_window_valid_d;
        end
    end

endmodule
