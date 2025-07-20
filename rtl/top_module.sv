module top_module#(
    parameter DATAW = 32,
    parameter ERRW = 2
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input   logic req_val_i,
    input   logic req_comm_i, //0 enq, 1 deq
    input   logic [DATAW-1: 0]req_data_i,
    output  logic req_rdy_o,

    output  logic rsp_val_o,
    output  logic [ERRW-1: 0]rsp_state_o, //0 normal, 1 empty, 2 full
    output  logic [DATAW-1: 0]rsp_data_o,
    input   logic rsp_rdy_i
);

/*
* recv |-> read/write |-> send
*/

logic [DATAW-1: 0] recv_rw_data_q, recv_rw_data_d;
logic recv_rw_com_q, recv_rw_com_d;

logic recv_rw_val_q, recv_rw_val_d;
logic recv_rw_rdy_q, recv_rw_rdy_d;

logic [DATAW-1: 0] rw_send_data_q;
logic [ERRW-1: 0] rw_send_state_q;

logic rw_send_val_q, rw_send_val_d;
logic rw_send_rdy_q, rw_send_rdy_d;

logic en;


logic [DATAW-1: 0] rw_data_out;
logic [ERRW-1: 0] rw_state_out;

always @(posedge clk_i) begin
    if (~rst_ni) begin
        recv_rw_data_q <= 0;
        recv_rw_com_q <= 0;
        rw_send_data_q <= 0;
        rw_send_state_q <= 0;
        recv_rw_rdy_q <= 0;
        rw_send_rdy_q <= 0;
        recv_rw_val_q <= 0;
        rw_send_val_q <= 0;
    end else begin
        recv_rw_data_q <= recv_rw_data_d;
        recv_rw_com_q <= recv_rw_com_d;
        rw_send_data_q <= rw_data_out;
        rw_send_state_q <= rw_state_out;
        recv_rw_rdy_q <= recv_rw_rdy_d;
        rw_send_rdy_q <= rw_send_rdy_d;
        recv_rw_val_q <= recv_rw_val_d;
        rw_send_val_q <= rw_send_val_d;
    end
end

//recv stage
always_comb begin
    recv_rw_data_d = recv_rw_data_q;
    recv_rw_com_d = recv_rw_com_q;
    recv_rw_val_d = req_val_i;
    req_rdy_o = recv_rw_rdy_q;

    if (recv_rw_rdy_q) begin
        recv_rw_data_d = req_data_i;
        recv_rw_com_d = req_comm_i;
    end

end


//rw stage
assign en = recv_rw_val_q & recv_rw_rdy_q;
always_comb begin
    recv_rw_rdy_d = recv_rw_rdy_q;
    rw_send_val_d = rw_send_val_q;

    if (recv_rw_val_q && !rw_send_rdy_q) begin //recv ready but send not ready
        recv_rw_rdy_d = 0;
    end else if (!recv_rw_val_q && rw_send_rdy_q) begin //recv not ready but send ready
        rw_send_val_d = 0;
    end else begin
        recv_rw_rdy_d = 1;
        rw_send_val_d = 1;
    end
end

//send
always_comb begin
    rsp_state_o = rw_send_state_q;
    rsp_data_o = rw_send_data_q;
    rw_send_rdy_d = rw_send_rdy_q;
    rsp_val_o = rw_send_val_q;

    if(rsp_rdy_i && rsp_val_o) begin
        rw_send_rdy_d = 0;
    end else begin
        rw_send_rdy_d = 1;
    end
end



//then write to rw_data_out and rw_state_out

fifo #(
    .DATAW(DATAW),
    .FIFO_SZ(16),
    .FIFO_ADDRW($clog2(16)),
    .ERRW(ERRW)
    ) fifo_inst(
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .en(en),
    .data_i(recv_rw_data_q),
    .cmd_i(recv_rw_com_q), //0 enq, 1 deq

    .data_o(rw_data_out),
    .state_o(rw_state_out)//0 normal, 1 empty, 2 full
);
endmodule

module ptr_gen#(
    parameter PTR_WID = 4
    )(
    input   logic [PTR_WID-1: 0] old_ptr,
    output  logic [PTR_WID-1: 0] new_ptr
);

    assign new_ptr =  old_ptr + PTR_WID'(1);

endmodule

module fifo #(
    parameter DATAW = 32,
    parameter FIFO_SZ = 16,
    parameter FIFO_ADDRW = $clog2(FIFO_SZ),
    parameter ERRW = 2
    ) (
    input   logic clk_i,
    input   logic rst_ni,

    input   logic en,
    input   logic [DATAW-1: 0] data_i,
    input   logic cmd_i, //0 enq, 1 deq

    output  logic [DATAW-1: 0] data_o,
    output  logic [ERRW-1: 0] state_o//0 normal, 1 empty, 2 full
);

logic [FIFO_ADDRW-1: 0] rptr_d, rptr_q, rptr_buf;
logic [FIFO_ADDRW-1: 0] wptr_d, wptr_q, wptr_buf;
logic [FIFO_ADDRW: 0] cnt_d, cnt_q;

logic [ERRW-1:0] state_out;

always @(posedge clk_i) begin
    if (~rst_ni) begin
        rptr_q <= 0;
        wptr_q <= 0;
        cnt_q <= 0;
    end else begin
        rptr_q <= rptr_d;
        wptr_q <= wptr_d;
        cnt_q <= cnt_d;
    end
end

always_comb begin: cnt_update
    if (en) begin
        if (state_out != 0) begin
            cnt_d = cnt_q;
        end else begin
            if(cmd_i) begin
                cnt_d = cnt_q - 1;
            end else begin
                cnt_d = cnt_q + 1;
            end
        end
    end else begin
        cnt_d = cnt_q;
    end
end

ptr_gen ptr_adder1_int(
    .old_ptr(wptr_q),
    .new_ptr(wptr_buf)
    );
// assign wptr_d = ((~cmd_i) && en)?wptr_buf:wptr_q;

ptr_gen ptr_adder2_int(
    .old_ptr(rptr_q),
    .new_ptr(rptr_buf)
    );
// assign rptr_d = ((cmd_i) && en)?rptr_buf:rptr_q;

always_comb begin: ecode_update
    // if (rptr_q == wptr_q) begin
    //     if (cnt_q == 0) begin
    //         state_out = (cmd_i && en)?1:0;
    //     end else if (cnt_q == 4'(FIFO_SZ)) begin
    //         state_out = ((~cmd_i) && en)?2:0;
    //     end else begin
    //         state_out = (en)?3:0;
    //     end
    // end else begin
    //     state_out = 0;
    // end

    if (rptr_q == wptr_q) begin
        if (cnt_q == 0) begin
            state_out = (cmd_i && en)?1:0;
        end else begin
            state_out = ((~cmd_i) && en)?2:0;
        end
    end else begin
        state_out = 0;
    end
    wptr_d = ((~cmd_i) && en && (state_out == 0))?wptr_buf:wptr_q;
    rptr_d = ((cmd_i) && en && (state_out == 0))?rptr_buf:rptr_q;
end

// memory#(
//     .MEM_SZ(FIFO_SZ),
//     .ADDRW(FIFO_ADDRW),
//     .DATAW(FIFO_DATAW)
//     ) (
// 		.clk_i(clk_i),
// 		.rst_ni(rst_ni),

// 		.req_val_i(req_val_i),
// 		.req_comm_i(req_comm_i),
// 		.req_addr_i(req_addr_i),
// 		.req_data_i(req_data_i),
// 		.req_rdy_o(req_rdy_o),

// 		.rsp_val_o(rsp_val_o),
// 		.rsp_data_o(rsp_data_o),
// 		.rsp_rdy_i(rsp_rdy_i)
//     );

assign state_o = state_out;

assign data_o = DATAW'({rptr_q, 24'b0, wptr_q});
/*
* data_o[31:28] == rptr_q
* data_o[3:0] == wptr_q
*/

endmodule
