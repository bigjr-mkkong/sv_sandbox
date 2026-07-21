yosys -import

set rtl_filelist [lindex $argv 0]
set output_netlist [lindex $argv 1]

read_slang --top top_module -f $rtl_filelist
hierarchy -check -top top_module
prep -top top_module
opt -full
check
stat

write_verilog -noexpr -noattr -simple-lhs $output_netlist
