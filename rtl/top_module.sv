
module top_module#(
    parameter DATA_WIDTH = 32,
    parameter MAX_CAPACITY = 2 ** 4
    ) (
    input logic clk_i,
    input logic rst_ni,
    input logic req_val_i,
    input logic [1:0]req_typ_i, // 1:read, 2:write
    input logic [DATA_WIDTH-1: 0]data_i,
    output logic req_rdy_o,

    output logic rsp_val_o,
    output logic [DATA_WIDTH-1: 0]data_o,
    input logic rsp_rdy_i
);

fifo_test#(
    .DATA_WIDTH(DATA_WIDTH),
    .MAX_CAPACITY(MAX_CAPACITY)
    ) FIFO_test_mod  (
		.clk_i (clk_i),
		.rst_ni (rst_ni),

		.req_val_i (req_val_i),
		.req_typ_i (req_typ_i),
		.data_i (data_i),
		.req_rdy_o (req_rdy_o),

		.rsp_val_o (rsp_val_o),
		.data_o (data_o),
        .err_o (_),
		.rsp_rdy_i (rsp_rdy_i)
    );

endmodule

module fifo_test#(
    parameter DATA_WIDTH = 32,
    parameter MAX_CAPACITY = 20,
    localparam ADDR_WIDTH = $clog2(MAX_CAPACITY)
    ) (
    input logic clk_i,
    input logic rst_ni,

    input logic req_val_i,
    input logic [1:0]req_typ_i, // 1:read, 2:write
    input logic [DATA_WIDTH-1: 0]data_i,
    output logic req_rdy_o,

    output logic rsp_val_o,
    output logic [DATA_WIDTH-1: 0]data_o,
    output logic err_o,
    input logic rsp_rdy_i
    );

    logic [DATA_WIDTH-1: 0] mem[MAX_CAPACITY];
    logic [ADDR_WIDTH-1: 0] write_ptr_q;
    logic [ADDR_WIDTH-1: 0] read_ptr_q;

    logic [ADDR_WIDTH-1: 0] write_ptr_d;
    logic [ADDR_WIDTH-1: 0] read_ptr_d;

    logic save_req;
    logic mem_write;
    logic [ADDR_WIDTH-1: 0] mem_w_addr;
    logic [1:0]req_typ_buf;
    logic [DATA_WIDTH-1: 0]data_buf;
    logic [DATA_WIDTH-1: 0]elecnt_d;
    logic [DATA_WIDTH-1: 0]elecnt_q;
    logic error_code;

    typedef enum logic[1:0] {
        INIT = 2'd0,
        REPLY = 2'd1
    } state_t;

    state_t state_d, state_q;

    assign err_o = error_code;

    always_comb begin
        save_req = 0;
        mem_write = 0;
        mem_w_addr = 0;
        req_rdy_o = 0;
        rsp_val_o = 0;
        elecnt_d = 0;
        error_code = 0;
        case (state_q)
            INIT:
            begin
                if (req_val_i) begin
                    save_req = 1;
                    req_rdy_o = 1;
                    state_d = REPLY;
                end else begin
                    state_d = INIT;
                end
            end

            REPLY:
            begin
                if(rsp_rdy_i) begin
                    rsp_val_o = 1;
                    case (req_typ_buf)
                        2'd1:
                        begin
                            //pop
                            data_o = mem[read_ptr_q];
                            read_ptr_d = (read_ptr_q + 1);
                            elecnt_d = -1;
                        end

                        2'd2:
                        begin
                            //push
                            mem_write = 1;
                            mem_w_addr = write_ptr_q;
                            write_ptr_d = (write_ptr_q + 1);
                            elecnt_d = 1;
                        end

                        2'd3:
                        begin
                            data_o = elecnt_q;
                        end

                        default:
                            error_code = 1;
                    endcase
                    state_d = INIT;
                end else begin
                    state_d = REPLY;
                end
            end

            default:
                error_code = 1;

        endcase
    end

    always @(posedge clk_i) begin
        if (~rst_ni) begin
            state_q <= INIT;
            write_ptr_q <= 0;
            read_ptr_q <= 0;
            elecnt_q <= 0;
        end else begin
            state_q <= state_d;
            write_ptr_q <= write_ptr_d;
            read_ptr_q <= read_ptr_d;
            req_typ_buf <= save_req?req_typ_i:req_typ_buf;
            data_buf <= save_req?data_i:data_buf;
            mem[mem_w_addr] <= mem_write?data_buf:mem[mem_w_addr];
            elecnt_q <= elecnt_q + elecnt_d;
        end
    end

endmodule
