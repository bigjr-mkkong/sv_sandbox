set script_dir [file dirname [file normalize [info script]]]
set project_dir [file join $script_dir build basys3]
set rtl_files $argv

create_project -force basys3 $project_dir -part xc7a35tcpg236-1

add_files -norecurse $rtl_files
add_files -norecurse [file join $script_dir basys3.sv]
add_files -fileset constrs_1 -norecurse [list \
    [file join $script_dir Basys3_Master.xdc] \
    [file join $script_dir constraints.xdc] \
]
set_property top basys3 [current_fileset]

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 \
    -module_name mmcm_100_to_48
set_property -dict [list \
    CONFIG.CLK_OUT1_PORT {clk_48} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {48} \
    CONFIG.PRIMARY_PORT {clk_100} \
    CONFIG.USE_LOCKED {false} \
    CONFIG.USE_RESET {false} \
] [get_ips mmcm_100_to_48]
generate_target all [get_ips mmcm_100_to_48]

set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
launch_runs synth_1 -jobs [exec nproc]
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs [exec nproc]
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Vivado implementation did not complete"
}

exit
