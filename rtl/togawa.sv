`timescale 1ns / 1ps

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

    spi_ram_if.if_src   spi_o,

    output logic        halt
);

    logic [63:0] reg_d, reg_q;
    logic [15:0] reg_addr_d, reg_addr_q;
    logic [15:0] load_addr;
    logic reg_dirty_d, reg_dirty_q;

    // The only execution pipeline register: IF -> IDEXMEM.
    logic inst_valid_d, inst_valid_q;
    logic [15:0] inst_d, inst_q;

    logic [15:0] pc_d, pc_q;
    logic [15:0] branch_pc;
    logic halt_d, halt_q;
    logic stall, flush;

    typedef enum logic { IDLE, WAIT } spi_state_t;
    spi_state_t spi_state_d, spi_state_q;
    logic [2:0] byte_d, byte_q;
    logic [55:0] load_low_d, load_low_q;

    // WA operands index eight-byte words; addresses wrap in the 64 KiB SPI space.
    assign load_addr = inst_q[14] ? {reg_q[12:0], 3'b000}
                                 : {inst_q[12:0], 3'b000};
    assign pc_o = pc_q;
    assign halt = halt_q && !reg_dirty_q && spi_state_q == IDLE;
    wire _unused_ok = &{1'b0, icache_req_rdy_i};

    always_comb begin : idexmem_stage
        reg_d = reg_q;
        reg_addr_d = reg_addr_q;
        reg_dirty_d = reg_dirty_q;
        spi_state_d = spi_state_q;
        byte_d = byte_q;
        load_low_d = load_low_q;

        spi_o.req_val = 1'b0;
        spi_o.req_we = reg_dirty_q;
        spi_o.req_addr = reg_dirty_q
            ? {reg_addr_q[15:3], byte_q} : {load_addr[15:3], byte_q};
        spi_o.req_wdata = reg_q[byte_q * 8 +: 8];
        spi_o.rsp_rdy = 1'b0;
        stall = 1'b0;
        flush = 1'b0;
        branch_pc = pc_q;

        // HALT clears stage valid but still writes back a dirty word.
        if (rst_ni && !halt && (inst_valid_q || halt_q)) begin
            if (inst_q[15] || inst_q == 16'h0000) begin
                stall = 1'b1;
                case (spi_state_q)
                    IDLE: begin
                        spi_o.req_val = 1'b1;
                        if (spi_o.req_rdy)
                            spi_state_d = WAIT;
                    end
                    WAIT: begin
                        spi_o.rsp_rdy = 1'b1;
                        if (spi_o.rsp_val) begin
                            spi_state_d = IDLE;
                            // Keep the indirect pointer intact until all eight bytes arrive.
                            byte_d = byte_q + 3'd1;
                            if (byte_q != 3'd7) begin
                                if (!reg_dirty_q)
                                    load_low_d[byte_q * 8 +: 8] = spi_o.rsp_rdata;
                            end else if (reg_dirty_q) begin
                                reg_dirty_d = 1'b0;
                            end else begin
                                reg_d = {spi_o.rsp_rdata, load_low_q};
                                reg_addr_d = load_addr;
                                stall = 1'b0;
                            end
                        end
                    end
                endcase
            end else begin
                reg_d = reg_q ^ (64'h0000000000000001 << inst_q[14:9]);
                reg_dirty_d = 1'b1;
                // The old bit being one means the toggled bit is zero.
                flush = reg_q[inst_q[14:9]] && inst_q[8:0] != 9'd0;
                // IF already advanced PC past the executing instruction.
                branch_pc = pc_q + { {7{inst_q[8]}}, inst_q[8:0] };
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
            reg_q <= 64'd0;
            reg_addr_q <= 16'd0;
            reg_dirty_q <= 1'b0;
            pc_q <= 16'd0;
            spi_state_q <= IDLE;
            byte_q <= 3'd0;
            load_low_q <= '0;
            halt_q <= 1'b0;
        end else begin
            reg_q <= reg_d;
            reg_addr_q <= reg_addr_d;
            reg_dirty_q <= reg_dirty_d;
            pc_q <= pc_d;
            spi_state_q <= spi_state_d;
            byte_q <= byte_d;
            load_low_q <= load_low_d;
            halt_q <= halt_d;
        end
    end

endmodule

module reset_sync (
    input  logic clk_i,
    input  logic rst_ni,
    output logic rst_sync_ni
);

    logic [1:0] sync_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            sync_q <= 2'b00;
        else
            sync_q <= {sync_q[0], 1'b1};
    end

    assign rst_sync_ni = sync_q[1];

endmodule
