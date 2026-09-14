foreach inst [[ord::get_db_block] getInsts] {
    if {! [[$inst getMaster] isBlock]} {
        continue
    }

    set name [$inst getName]

    if {[string match {*simple_cache_1rw_inst0*} $name]} {
        set region {20 20 330 680}
    } elseif {[string match {*simple_cache_1rw_inst1*} $name]} {
        set region {370 20 680 680}
    } else {
        continue
    }

    puts "Guiding $name toward $region"

    set_macro_guidance_region \
        -macro_name $name \
        -region $region
}
