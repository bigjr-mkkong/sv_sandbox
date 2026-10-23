`timescale 1ns / 1ps

package config_pkg;

    // Static, project-owned configuration.
    parameter int unsigned CLOCK_FREQUENCY_HZ = 48_000_000;

endpackage

interface spi_ram_if;

    logic        req_val;
    logic        req_rdy;
    logic        req_we;
    logic [15:0] req_addr;
    logic [7:0]  req_wdata;
    logic        rsp_val;
    logic [7:0]  rsp_rdata;
    logic        rsp_rdy;

    // Request and response payloads remain stable until valid and ready meet.
    modport if_src (
        output req_val, req_we, req_addr, req_wdata, rsp_rdy,
        input  req_rdy, rsp_val, rsp_rdata
    );

    modport if_sink (
        input  req_val, req_we, req_addr, req_wdata, rsp_rdy,
        output req_rdy, rsp_val, rsp_rdata
    );
endinterface
