# Two rows of nine fakerams per cache, with a central strip for control logic.
# These are fixed placements, not soft guidance that the placer may ignore.
# Coordinates follow the actual core bounds; dimensions/gaps are in microns.
set block [ord::get_db_block]
set dbu [$block getDbUnitsPerMicron]
set core [$block getCoreArea]
set lx [expr {double([$core xMin]) / $dbu}]
set ly [expr {double([$core yMin]) / $dbu}]
set ux [expr {double([$core xMax]) / $dbu}]
set uy [expr {double([$core yMax]) / $dbu}]
set gap 12.0
set margin 12.0
set columns 9
set groups [list {} {}]

foreach inst [$block getInsts] {
    set master [$inst getMaster]
    if {![$master isBlock]} { continue }
    set name [$inst getName]
    if {[$master getName] ne "fakeram45_128x64"
        || ![regexp {simple_cache_1rw_inst([01])\.} $name -> cache]} {
        error "Unexpected macro in two-cache floorplan: $name"
    }
    lset groups $cache [linsert [lindex $groups $cache] end $name]
    set width [expr {double([$master getWidth]) / $dbu}]
    set height [expr {double([$master getHeight]) / $dbu}]
}

foreach cache {0 1} {
    if {[llength [lindex $groups $cache]] != 18} {
        error "Expected 18 SRAM macros for cache $cache"
    }
}
set span [expr {$columns * $width + ($columns - 1) * $gap}]
set strip_height [expr {2 * $height + $gap}]
if {$ux - $lx < $span + 2 * $margin
    || $uy - $ly < 2 * ($strip_height + $margin) + 100.0} {
    error "Core too small for SRAM strips and a 100um control channel"
}
set x_start [expr {($lx + $ux - $span) / 2.0}]

foreach cache {0 1} {
    set slot 0
    foreach name [lsort -dictionary [lindex $groups $cache]] {
        set column [expr {$slot % $columns}]
        set row [expr {$slot / $columns}]
        set x [expr {$x_start + $column * ($width + $gap)}]
        if {$cache == 0} {
            set y [expr {$uy - $margin - $height - $row * ($height + $gap)}]
        } else {
            set y [expr {$ly + $margin + $row * ($height + $gap)}]
        }
        place_macro -macro_name $name -location [list $x $y] -orientation R0
        incr slot
    }
}
