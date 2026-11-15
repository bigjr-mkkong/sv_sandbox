`timescale 1ns / 1ps

package config_pkg;

    // Static, project-owned configuration.
    parameter int unsigned CLOCK_FREQUENCY_HZ = 48_000_000;

endpackage

interface spi_ram_if #(parameter int DATA_W = 64);

    logic        req_val;
    logic        req_rdy;
    logic        req_we;
    logic        req_is_inst;
    logic [15:0] req_addr;
    logic [DATA_W-1:0] req_wdata;
    logic        rsp_val;
    logic [DATA_W-1:0] rsp_rdata;
    logic [15:0] rsp_rinst;
    logic        rsp_rdy;

    // Request and response payloads remain stable until valid and ready meet.
    modport if_src (
        output req_val, req_we, req_is_inst, req_addr, req_wdata, rsp_rdy,
        input  req_rdy, rsp_val, rsp_rdata, rsp_rinst
    );

    modport if_sink (
        input  req_val, req_we, req_is_inst, req_addr, req_wdata, rsp_rdy,
        output req_rdy, rsp_val, rsp_rdata, rsp_rinst
    );
endinterface
