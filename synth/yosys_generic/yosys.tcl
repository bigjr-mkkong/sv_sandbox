yosys -import

set rtl_filelist [lindex $argv 0]
set output_netlist [lindex $argv 1]

read_slang -Ithird_party/basejump_stl/bsg_misc --top top_module -f $rtl_filelist
synth -top top_module
check -assert
# Generic gates use $_* names; reject any remaining coarse $ cells.
select -assert-none {t:$*} {t:$_*} %d

write_verilog -noattr -simple-lhs $output_netlist
