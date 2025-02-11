
yosys -import

read_verilog synth/build/rtl.sv2v.v
read_verilog -sv synth/yosys_generic/top_module_sim_gls.sv

prep
opt -full
stat

write_verilog -noexpr -noattr -simple-lhs synth/yosys_generic/build/synth.v
