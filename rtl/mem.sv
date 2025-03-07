module mem #(
    parameter DATA_BITS = 32,
    localparam DATA_WIDTH = $clog2(DATA_BITS),
    parameter MEM_SIZE = 2**7,
    localparam ADDR_WIDTH = $clog2(MEM_SIZE)
    )(
        input logic clk_i,
        input logic rst_ni,
        input logic req_val_i,
        input logic req_typ_i, //0 is read, 1 is write
        input logic [ADDR_WIDTH-1: 0]req_addr_i,
        input logic [DATA_WIDTH-1: 0]req_data_i,
        output logic req_rdy_o,

        output logic rsp_val_o,
        output logic [DATA_WIDTH-1: 0]rsp_data_o,
        input logic rsp_rdy_i
    );

    logic [DATA_WIDTH-1: 0] mem_d[MEM_SIZE-1: 0], mem_q[MEM_SIZE-1: 0];

    //Two stage
    //INIT and RSP(in and rs)

    logic in2rs_req_typ_d, in2rs_req_typ_q;
    logic [ADDR_WIDTH-1: 0]in2rs_req_addr_d, in2rs_req_addr_q;
    logic [DATA_WIDTH-1: 0]in2rs_req_data_d, in2rs_req_data_q;
    logic in2rs_val, rs2in_rdy;

    logic [DATA_WIDTH-1: 0]rsp_data_tmp;

    //pipeline control
    always @(posedge clk_i) begin
        if (~rst_ni) begin
            in2rs_req_typ_q <= 0;
            in2rs_req_addr_q <= 0;
            in2rs_req_data_q <= 0;
        end else begin
            in2rs_req_typ_q <= in2rs_req_typ_d;
            in2rs_req_addr_q <= in2rs_req_addr_d;
            in2rs_req_data_q <= in2rs_req_data_d;
        end
    end

    //INIT stage
    always_comb begin
        req_rdy_o = 0;
        in2rs_req_typ_d = 0;
        in2rs_req_addr_d = 0;
        in2rs_req_data_d = 0;
        in2rs_val = 0;
        if(req_val_i && rs2in_rdy) begin
            req_rdy_o = 1;
            in2rs_req_typ_d = req_typ_i;
            in2rs_req_addr_d = req_addr_i;
            in2rs_req_data_d = req_data_i;
            in2rs_val = 1;
        end
    end

    always_comb begin
        if (in2rs_val) begin
            case (in2rs_req_typ_q)
                1'b0: begin
                    rsp_data_tmp = mem_q[in2rs_req_addr_q];
                end

                1'b1: begin
                    mem_d[in2rs_req_addr_q] = in2rs_req_data_q;
                end
            endcase
        end
    end

    always_comb begin
        rsp_data_o = 0;
        rsp_val_o = 0;
        rs2in_rdy = 1;
        if (rsp_rdy_i) begin
            rs2in_rdy = 0;
            rsp_data_o = rsp_data_tmp;
            rsp_val_o = 1;
        end
    end

    always @(posedge clk_i) begin
        if(~rst_ni) begin
            mem_q[in2rs_req_addr_q] <= 0;
        end else begin
            mem_q[in2rs_req_addr_q] <= mem_d[in2rs_req_addr_q];
            $display("Written mem[0x%x] = 0x%x", in2rs_req_addr_q, mem_d[in2rs_req_addr_q]);
        end
    end

endmodule
