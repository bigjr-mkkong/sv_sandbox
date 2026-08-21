`timescale 1ns / 1ps

package config_pkg;

    // Static, project-owned configuration. Third-party module configuration
    // belongs in config.json and is rendered directly at its integration site.
    parameter int unsigned ADDR_WIDTH     = 64;
    parameter int unsigned DATA_WIDTH     = 64;

endpackage
