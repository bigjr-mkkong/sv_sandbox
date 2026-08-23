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
        BusRd,   // Dirty snoopers must supply or write back their data.
        BusRd_Ex, // MESI BusRdX: fetch and invalidate other cached copies.
        BusSync   // MESI BusUpgr: invalidate shared copies without a fetch.
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

    modport if_mst (
        output req_val,
        output req_addr,
        output req_data,
        output req_rw_flag,
        input  req_rdy,

        input  rsp_val,
        input  rsp_data,
        output rsp_rdy
    );

    modport if_slv (
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

interface coh_bus_if #(
    parameter int unsigned ADDR_WIDTH = config_pkg::ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = config_pkg::DATA_WIDTH
) ();
    logic                  req_val;
    config_pkg::coh_bus_op bus_op;
    logic [ADDR_WIDTH-1:0] req_addr;
    logic                  req_rdy;

    logic rsp_val;
    logic rsp_rdy;

endinterface
