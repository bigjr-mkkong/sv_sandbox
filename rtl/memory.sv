module memory#(
    parameter MEM_SZ = 16,
    parameter ADDRW = $clog2(MEM_SZ),
    parameter DATAW = 32
    ) (
        input   logic clk_i,
        input   logic rst_ni,

        input   logic req_val_i,
        input   logic req_comm_i, //0 read, 1 write
        input   logic [ADDRW-1: 0] req_addr_i,
        input   logic [DATAW-1: 0] req_data_i,
        output  logic req_rdy_o,

        output  logic rsp_val_o,
        output  logic [DATAW-1: 0] rsp_data_o, //when write, it return the written data
        input   logic rsp_rdy_i
    );

    typedef enum logic [1:0]  {
        IDLE,
        RESP
    } state_t;

    state_t state_d, state_q;
    logic   [DATAW-1: 0] data_buf;
    logic   [DATAW-1: 0] mem[MEM_SZ-1: 0];
    
    always @(posedge clk_i) begin
        if (~rst_ni) begin
            state_q <= IDLE;
            data_buf <= 0;

            for (int i = 0; i < MEM_SZ; i++) begin
                mem[i] <= '0;
            end

        end else begin
            state_q <= state_d;
            mem[req_addr_i] <= (req_comm_i)? req_data_i:mem[req_addr_i];
            data_buf <= (~req_comm_i)? mem[req_addr_i]:req_data_i;
        end
    end

    assign rsp_data_o = data_buf;

    always_comb begin
        state_d = state_q;
        req_rdy_o = 0;
        rsp_val_o = 0;
        case (state_q) 
            IDLE: begin
                req_rdy_o = 1;
                if (req_val_i) begin
                    state_d = RESP;
                end
            end

            RESP: begin
                rsp_val_o = 1;
                if (rsp_rdy_i) begin
                    state_d = IDLE;
                end
            end
        endcase
    end


endmodule
