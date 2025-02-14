
package config_pkg;

interface ice_uart #(parameter DATA_WIDTH=32) (input logic clk)
    logic dut_recv_rdy;
    logic [DATA_WIDTH-1: 0]dut_data_recv;
    logic dut_send_rdy;
    logic [DATA_WIDTH-1: 0]dut_data_send;
endinterface

endpackage
