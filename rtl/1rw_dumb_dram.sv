`timescale 1ns / 1ps

/* verilator lint_off DECLFILENAME */
{% do unit_test(
    module_name = "dumb_dram_1rw",
    test_framework = "cocotb",
    use_wrapper = true,
    test_path = "dv/cocotb_benches/1rw_dumb_dram_tb.py") %}
module dumb_dram_1rw #(
    parameter int unsigned ADDR_WIDTH    = 64,
    parameter int unsigned DATA_WIDTH    = 64,
    parameter int unsigned DATA_PER_LINE = 8
) (
    input logic clk_i,
    input logic rst_ni,

    // Cache-line-wide upstream AXI-Lite slave interface.
    taxi_axil_if.wr_slv s_axil_wr,
    taxi_axil_if.rd_slv s_axil_rd
);

    localparam logic [1:0] AXIL_RESP_OKAY = 2'b00;
    localparam logic [DATA_WIDTH-1:0] MAGIC_WORD = DATA_WIDTH'(114514);
    localparam int unsigned LINE_WIDTH = DATA_WIDTH * DATA_PER_LINE;

    typedef enum logic [1:0] {
        IDLE,
        WRITE_RESP,
        READ_RESP
    } state_e;

    state_e state_d, state_q;

    logic write_pair_valid;
    logic write_channel_pending;
    logic [LINE_WIDTH-1:0] read_data_q;

`ifdef VERILATOR
    chandle ideal_mem_handle;
    bit [511:0] ideal_mem_read_result;

    import "DPI-C" function chandle ideal_mem_create();
    import "DPI-C" function void ideal_mem_destroy(input chandle handle);
    import "DPI-C" function void ideal_mem_reset(input chandle handle);
    import "DPI-C" function void ideal_mem_write(
        input chandle handle,
        input longint unsigned addr,
        input bit [511:0] data
    );
    import "DPI-C" function void ideal_mem_read(
        input chandle handle,
        input longint unsigned addr,
        output bit [511:0] data
    );

    initial begin
        if (ADDR_WIDTH != 64 || DATA_WIDTH != 64 || DATA_PER_LINE != 8) begin
            $fatal(1,
                "Verilator ideal_mem requires ADDR_WIDTH=64, DATA_WIDTH=64, and DATA_PER_LINE=8");
        end
        ideal_mem_handle = ideal_mem_create();
        if (ideal_mem_handle == null) begin
            $fatal(1, "ideal_mem_create failed");
        end
    end

    final begin
        ideal_mem_destroy(ideal_mem_handle);
    end
`endif

    always_comb begin
        state_d = state_q;

        s_axil_wr.awready = 1'b0;
        s_axil_wr.wready = 1'b0;
        s_axil_wr.bresp = AXIL_RESP_OKAY;
        s_axil_wr.buser = '0;
        s_axil_wr.bvalid = 1'b0;

        s_axil_rd.arready = 1'b0;
        s_axil_rd.rdata = read_data_q;
        s_axil_rd.rresp = AXIL_RESP_OKAY;
        s_axil_rd.ruser = '0;
        s_axil_rd.rvalid = 1'b0;

        write_pair_valid = s_axil_wr.awvalid && s_axil_wr.wvalid;
        write_channel_pending = s_axil_wr.awvalid || s_axil_wr.wvalid;

        case (state_q)
            IDLE: begin
                if (write_channel_pending) begin
                    if (write_pair_valid) begin
                        s_axil_wr.awready = 1'b1;
                        s_axil_wr.wready = 1'b1;
                        state_d = WRITE_RESP;
                    end
                end else if (s_axil_rd.arvalid) begin
                    s_axil_rd.arready = 1'b1;
                    state_d = READ_RESP;
                end
            end

            WRITE_RESP: begin
                s_axil_wr.bvalid = 1'b1;
                if (s_axil_wr.bready) begin
                    state_d = IDLE;
                end
            end

            READ_RESP: begin
                s_axil_rd.rvalid = 1'b1;
                if (s_axil_rd.rready) begin
                    state_d = IDLE;
                end
            end

            default: begin
                state_d = IDLE;
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            state_q <= IDLE;
`ifdef VERILATOR
            ideal_mem_reset(ideal_mem_handle);
            read_data_q <= '0;
`else
            read_data_q <= {DATA_PER_LINE{MAGIC_WORD}};
`endif
        end else begin
            state_q <= state_d;

`ifdef VERILATOR
            if (s_axil_wr.awvalid && s_axil_wr.awready
                    && s_axil_wr.wvalid && s_axil_wr.wready) begin
                ideal_mem_write(
                    ideal_mem_handle,
                    s_axil_wr.awaddr,
                    s_axil_wr.wdata
                );
            end

            if (s_axil_rd.arvalid && s_axil_rd.arready) begin
                ideal_mem_read(
                    ideal_mem_handle,
                    s_axil_rd.araddr,
                    ideal_mem_read_result
                );
                read_data_q <= ideal_mem_read_result;
            end
`else
            if (s_axil_rd.arvalid && s_axil_rd.arready) begin
                read_data_q <= {DATA_PER_LINE{MAGIC_WORD}};
            end
`endif
        end
    end

endmodule
/* verilator lint_on DECLFILENAME */
