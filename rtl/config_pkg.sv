`timescale 1ns / 1ps

package config_pkg;

    // Static, project-owned configuration. Third-party module configuration
    // belongs in config.json and is rendered directly at its integration site.
    parameter int unsigned MAIN_DATA_WIDTH = 8;
    parameter int unsigned CLOCK_FREQUENCY_HZ = 48_000_000;

endpackage

interface spi_ram_if;

    logic        req_val_i;
    logic        req_rdy;
    logic        req_we;
    logic [15:0] req_addr;
    logic [7:0]  req_wdata;
    logic        resp_val;
    logic [7:0]  resp_rdata;

    // Responses pulse for one cycle; the requester must always accept them.
    modport if_src (
        output req_val_i, req_we, req_addr, req_wdata,
        input  req_rdy, resp_val, resp_rdata
    );

    modport if_sink (
        input  req_val_i, req_we, req_addr, req_wdata,
        output req_rdy, resp_val, resp_rdata
    );
endinterface
