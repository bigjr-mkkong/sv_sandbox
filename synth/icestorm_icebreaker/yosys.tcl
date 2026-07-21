yosys -import

set mode [lindex $argv 0]
set rtl_filelist [lindex $argv 1]
set wrapper [lindex $argv 2]
set output_netlist [lindex $argv 3]

if {$mode eq "simulation"} {
    read_slang -DICEBREAKER_SIMULATION --top icebreaker -f $rtl_filelist $wrapper
} elseif {$mode eq "hardware"} {
    set pll_source [lindex $argv 4]
    set ice40_cells [lindex $argv 5]

    read_slang -Wno-unconnected-port -v $ice40_cells \
        --top icebreaker -f $rtl_filelist $pll_source $wrapper
} else {
    error "unknown iCEBreaker synthesis mode: $mode"
}

hierarchy -check -top icebreaker
synth_ice40 -top icebreaker
check
stat

write_verilog -noexpr -noattr -simple-lhs $output_netlist

if {$mode eq "hardware"} {
    set output_json [lindex $argv 6]
    write_json $output_json
}
