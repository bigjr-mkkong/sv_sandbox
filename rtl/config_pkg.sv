`timescale 1ns / 1ps

package config_pkg;

    // Static, project-owned configuration. Third-party module configuration
    // belongs in config.json and is rendered directly at its integration site.
    parameter int unsigned MAIN_DATA_WIDTH = 8;
    parameter int unsigned CLOCK_FREQUENCY_HZ = 48_000_000;

endpackage
