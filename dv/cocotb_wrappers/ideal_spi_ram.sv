`timescale 1ns / 1ps

module ideal_spi_ram (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        req_val,
    output logic        req_rdy,
    input  logic        req_we,
    input  logic [15:0] req_addr,
    input  logic [7:0]  req_wdata,
    output logic        resp_val,
    output logic [7:0]  resp_rdata
);
    import "DPI-C" function chandle ideal_mem_create(input int unsigned data_width);
    import "DPI-C" function void ideal_mem_destroy(input chandle handle);
    import "DPI-C" function void ideal_mem_reset(input chandle handle);
    import "DPI-C" function void ideal_mem_write(
        input chandle handle, input int unsigned addr, input bit [15:0] data);
    import "DPI-C" function void ideal_mem_read(
        input chandle handle, input int unsigned addr, output bit [15:0] data);

    chandle memory;
    typedef enum logic { IDLE, RESP } state_e;
    state_e state_q;
    logic write_q;
    logic [15:0] addr_q;
    logic [7:0] data_q;
    bit [15:0] read_data;

    initial begin
        memory = ideal_mem_create(8);
        assert (memory != null) else $fatal(1, "SPI ideal RAM allocation failed");
    end

    final begin
        ideal_mem_destroy(memory);
    end

    assign req_rdy = rst_ni && state_q == IDLE;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            ideal_mem_reset(memory);
            state_q <= IDLE;
            write_q <= 1'b0;
            addr_q <= '0;
            data_q <= '0;
            resp_val <= 1'b0;
            resp_rdata <= '0;
        end else begin
            resp_val <= 1'b0;
            case (state_q)
                IDLE: begin
                    if (req_val && req_rdy) begin
                        write_q <= req_we;
                        addr_q <= req_addr;
                        data_q <= req_wdata;
                        state_q <= RESP;
                    end
                end
                RESP: begin
                    if (write_q) begin
                        ideal_mem_write(memory, {16'd0, addr_q}, {8'd0, data_q});
                        resp_rdata <= 8'd0;
                    end else begin
                        ideal_mem_read(memory, {16'd0, addr_q}, read_data);
                        assert (read_data[15:8] == 8'd0)
                            else $fatal(1, "8-bit ideal memory returned nonzero upper bits");
                        resp_rdata <= read_data[7:0];
                    end
                    // Match the master's pulse-only response, without SPI timing.
                    resp_val <= 1'b1;
                    state_q <= IDLE;
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
