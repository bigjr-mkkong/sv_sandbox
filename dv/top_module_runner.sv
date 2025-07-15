module top_module_runner;

logic clk_i;
logic rst_ni;

localparam realtime ClockPeriod = 6ms;
localparam DATAW = 32;
localparam MEM_SZ = 16;
localparam ADDRW = $clog2(MEM_SZ);

logic req_val_i, req_rdy_o, req_comm_i, rsp_val_o, rsp_rdy_i;
logic [DATAW-1: 0] req_data_i, rsp_data_o;
logic [ADDRW-1: 0] req_addr_i;

initial begin
    clk_i = 0;
    forever begin
        #(ClockPeriod/2);
        clk_i = !clk_i;
    end
end

top_module #(
    .DATAW(DATAW),
    .MEM_SZ(MEM_SZ)
    ) topmod_inst (
		.clk_i(clk_i),
		.rst_ni(rst_ni),

		.req_val_i(req_val_i),
		.req_comm_i(req_comm_i),
		.req_addr_i(req_addr_i),
		.req_data_i(req_data_i),
		.req_rdy_o(req_rdy_o),

		.rsp_val_o(rsp_val_o),
		.rsp_data_o(rsp_data_o),
		.rsp_rdy_i(rsp_rdy_i)
);

task automatic wait_end;
    repeat (100) @(posedge clk_i);
endtask

task automatic reset;
    rst_ni = 0;
    repeat(10) @(posedge clk_i);
    rst_ni = 1;
endtask

task automatic send(int rw, int addr, int data);
    int result = 0;
    while(!req_rdy_o) @(posedge clk_i);

    req_val_i = 1;
    req_comm_i = rw;
    req_addr_i = ADDRW'(addr);
    req_data_i = DATAW'(data);

    @(posedge clk_i);

    req_val_i = 0;

    while(!rsp_val_o)@(posedge clk_i);
    rsp_rdy_i = 1;
    result = rsp_data_o;

    $display("Read from rsp: %d\n", result);

    @(posedge clk_i);
    rsp_rdy_i = 0;


endtask

endmodule
