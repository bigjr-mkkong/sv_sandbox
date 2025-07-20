module top_module_runner;

logic clk_i;
logic rst_ni;

localparam realtime ClockPeriod = 6ms;
localparam DATAW = 32;
localparam ERRW = 2;
localparam MEM_SZ = 16;
localparam ADDRW = $clog2(MEM_SZ);

logic req_val_i, req_rdy_o, rsp_val_o, rsp_rdy_i;
logic [DATAW-1: 0] req_data_i, rsp_data_o;
logic [ERRW-1: 0] req_comm_i, rsp_state_o;

initial begin
    clk_i = 0;
    forever begin
        #(ClockPeriod/2);
        clk_i = !clk_i;
    end
end

task automatic timeout_killer(input int to_cyc);
    repeat(to_cyc) @(posedge clk_i);
    $display("Timeout reached, simulation will terminate\n");
    $finish;
endtask

top_module #(
    .DATAW(DATAW),
    .ERRW(ERRW)
    ) topmod_inst (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .req_val_i(req_val_i),
    .req_comm_i(req_comm_i), //0->enq 1->deq
    .req_data_i(req_data_i),
    .req_rdy_o(req_rdy_o),

    .rsp_val_o(rsp_val_o),
    .rsp_state_o(rsp_state_o), //0->normal 1->empty 2->full
    .rsp_data_o(rsp_data_o),
    .rsp_rdy_i(rsp_rdy_i)
);

task automatic wait_end;
    repeat (1000) @(posedge clk_i);
endtask

task automatic reset;
    rst_ni = 0;
    repeat(10) @(posedge clk_i);
    rst_ni = 1;
endtask

task automatic send(int comm, int data);
    logic [DATAW-1:0] result;
    logic [ERRW-1:0] ecode;

    while(!req_rdy_o) @(posedge clk_i);

    req_val_i = 1;
    req_comm_i = comm;
    req_data_i = DATAW'(data);

    @(posedge clk_i);

    req_val_i = 0;

    while(!rsp_val_o)@(posedge clk_i);
    rsp_rdy_i = 1;

    result = rsp_data_o;
    ecode = rsp_state_o;

    $display("comm: %s, rptr_q: %d, wptr_q: %d , ecode: %d\n",
        (comm)?"DEQ":"ENQ",result[31:28], result[3:0], ecode);
    @(posedge clk_i);
    rsp_rdy_i = 0;
    @(posedge clk_i);
endtask

endmodule
