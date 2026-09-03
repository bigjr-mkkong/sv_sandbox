`timescale 1ns / 1ps

package config_pkg;

    // Static, project-owned configuration. Third-party module configuration
    // belongs in config.json and is rendered directly at its integration site.
    parameter int unsigned ADDR_WIDTH     = 64;
    parameter int unsigned DATA_WIDTH     = 64;

    typedef enum logic [1:0] {
        COH_Modified,
        COH_Exclusive,
        COH_Shared,
        COH_Invalid
    } coh_state;

    typedef enum logic [1:0] {
        BusNOP,
        BusRd,   // Fetch the line; a Modified snooper must write back its data.
        BusRdX,  // Fetch the line and invalidate all other cached copies.
        BusUpgr  // Invalidate Shared copies without fetching the line.
    } coh_bus_op;

endpackage

interface upstream_if #(
    parameter int unsigned ADDR_WIDTH = config_pkg::ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = config_pkg::DATA_WIDTH
) ();
    logic                  req_val;
    logic [ADDR_WIDTH-1:0] req_addr;
    logic [DATA_WIDTH-1:0] req_data;
    logic                  req_rw_flag;
    logic                  req_rdy;

    logic                  rsp_val;
    logic [DATA_WIDTH-1:0] rsp_data;
    logic                  rsp_rdy;

    modport if_src (
        output req_val,
        output req_addr,
        output req_data,
        output req_rw_flag,
        input  req_rdy,

        input  rsp_val,
        input  rsp_data,
        output rsp_rdy
    );

    modport if_sink (
        input  req_val,
        input  req_addr,
        input  req_data,
        input  req_rw_flag,
        output req_rdy,

        output rsp_val,
        output rsp_data,
        input  rsp_rdy
    );
endinterface


// Cache request/response connection to the global coherence controller.
// A cache (or arbiter output) is the request source; the global controller is
// the request sink. Responses travel in the opposite direction.
interface coh_cache2bus_req #(
    parameter int unsigned ADDR_WIDTH = config_pkg::ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = config_pkg::DATA_WIDTH,
    parameter int unsigned SRC_WIDTH  = 4
) ();
    logic                  req_val;
    config_pkg::coh_bus_op bus_op;
    logic [ADDR_WIDTH-1:0] req_addr;
    logic [SRC_WIDTH-1:0]  req_src;
    logic                  req_rdy;

    logic rsp_val;
    logic rsp_shared;
    logic rsp_rdy;

    modport if_sink (
        input req_val,
        input bus_op,
        input req_addr,
        input req_src,
        output req_rdy,

        output rsp_val,
        output rsp_shared,
        input rsp_rdy
    );

    modport if_src (
        output req_val,
        output bus_op,
        output req_addr,
        output req_src,
        input req_rdy,

        input rsp_val,
        input rsp_shared,
        output rsp_rdy
    );

endinterface

// Global-controller snoop request/response connection to a cache. The global
// controller is the request source; each cache is a request sink. Responses
// travel in the opposite direction.
interface coh_bus2cache_req #(
    parameter int unsigned ADDR_WIDTH = config_pkg::ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = config_pkg::DATA_WIDTH
) ();

    logic                  req_val;
    config_pkg::coh_bus_op bus_op;
    logic [ADDR_WIDTH-1:0] req_addr;
    logic                  req_rdy;

    logic rsp_val;
    logic rsp_shared;
    logic rsp_rdy;

    modport if_sink (
        input req_val,
        input bus_op,
        input req_addr,
        output req_rdy,

        output rsp_val,
        output rsp_shared,
        input rsp_rdy
    );

    modport if_src (
        output req_val,
        output bus_op,
        output req_addr,
        input req_rdy,

        input rsp_val,
        input rsp_shared,
        output rsp_rdy
    );

endinterface
