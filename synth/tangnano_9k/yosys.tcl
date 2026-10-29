yosys -import

set rtl_filelist [lindex $argv 0]
set pll_source [lindex $argv 1]
set wrapper [lindex $argv 2]
set gowin_cells [lindex $argv 3]
set output_json [lindex $argv 4]

read_verilog -lib $gowin_cells
read_verilog $pll_source
read_slang --extern-modules -Ithird_party/basejump_stl/bsg_misc \
    --top tangnano_9k -f $rtl_filelist $wrapper
hierarchy -check -top tangnano_9k
synth_gowin -top tangnano_9k
check -assert
stat
write_json $output_json
