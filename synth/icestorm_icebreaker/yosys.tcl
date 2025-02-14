
yosys -import

read_verilog synth/build/rtl.sv2v.v synth/icestorm_icebreaker/icebreaker.v
read_verilog synth/icestorm_icebreaker/uart/uart_baud_tick_gen.v
read_verilog synth/icestorm_icebreaker/uart/uart_rx.v
read_verilog synth/icestorm_icebreaker/uart/uart_tx.v
read_verilog synth_ice40 -top icebreaker

write_verilog -noexpr -noattr -simple-lhs synth/icestorm_icebreaker/build/synth.v
write_json synth/icestorm_icebreaker/build/synth.json
