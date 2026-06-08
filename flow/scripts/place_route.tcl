proc require_env {name} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    puts stderr "Missing required environment variable: $name"
    exit 1
  }
}

foreach name {
  TOP
  LIBERTY
  LEF_FILES
  MAPPED_VERILOG
  SDC_FILE
  OBJECT_DIR
  REPORT_DIR
  SITE
  DIE_AREA
  CORE_AREA
} {
  require_env $name
}

read_liberty $::env(LIBERTY)
foreach lef $::env(LEF_FILES) {
  read_lef $lef
}
read_verilog $::env(MAPPED_VERILOG)
link_design $::env(TOP)
read_sdc $::env(SDC_FILE)

if {[info exists ::env(RC_FILE)] && $::env(RC_FILE) ne ""} {
  source $::env(RC_FILE)
}
if {[info exists ::env(WIRE_RC_LAYER)] && $::env(WIRE_RC_LAYER) ne ""} {
  set_wire_rc -signal -layer $::env(WIRE_RC_LAYER)
}
if {[info exists ::env(CLOCK_RC_LAYER)] && $::env(CLOCK_RC_LAYER) ne ""} {
  set_wire_rc -clock -layer $::env(CLOCK_RC_LAYER)
}

initialize_floorplan \
  -die_area $::env(DIE_AREA) \
  -core_area $::env(CORE_AREA) \
  -site $::env(SITE)
make_tracks

place_pins \
  -hor_layers $::env(IO_H_LAYER) \
  -ver_layers $::env(IO_V_LAYER)

global_placement -density $::env(PLACE_DENSITY)
detailed_placement
check_placement

estimate_parasitics -placement
report_checks -path_delay max -fields {slew cap input net fanout} -digits 3 > [file join $::env(REPORT_DIR) "post_place_setup.rpt"]
report_checks -path_delay min -fields {slew cap input net fanout} -digits 3 > [file join $::env(REPORT_DIR) "post_place_hold.rpt"]
report_worst_slack -max -digits 3 > [file join $::env(REPORT_DIR) "post_place_worst_slack_max.rpt"]
report_worst_slack -min -digits 3 > [file join $::env(REPORT_DIR) "post_place_worst_slack_min.rpt"]
sta::redirect_file_begin [file join $::env(REPORT_DIR) "post_place_area.rpt"]
report_design_area
sta::redirect_file_end
report_power > [file join $::env(REPORT_DIR) "post_place_power.rpt"]

write_def [file join $::env(OBJECT_DIR) "$::env(BLOCK)_placed.def"]
write_db [file join $::env(OBJECT_DIR) "$::env(BLOCK)_placed.db"]

set_routing_layers \
  -signal $::env(SIGNAL_ROUTING_LAYERS) \
  -clock $::env(CLOCK_ROUTING_LAYERS)
global_route \
  -guide_file [file join $::env(OBJECT_DIR) "$::env(BLOCK).route_guide"] \
  -congestion_iterations 100
estimate_parasitics -global_routing

report_checks -path_delay max -fields {slew cap input net fanout} -digits 3 > [file join $::env(REPORT_DIR) "post_grt_setup.rpt"]
report_checks -path_delay min -fields {slew cap input net fanout} -digits 3 > [file join $::env(REPORT_DIR) "post_grt_hold.rpt"]
report_worst_slack -max -digits 3 > [file join $::env(REPORT_DIR) "post_grt_worst_slack_max.rpt"]
report_worst_slack -min -digits 3 > [file join $::env(REPORT_DIR) "post_grt_worst_slack_min.rpt"]
report_tns -digits 3 > [file join $::env(REPORT_DIR) "post_grt_tns.rpt"]
sta::redirect_file_begin [file join $::env(REPORT_DIR) "post_grt_area.rpt"]
report_design_area
sta::redirect_file_end
report_power > [file join $::env(REPORT_DIR) "post_grt_power.rpt"]

write_def [file join $::env(OBJECT_DIR) "$::env(BLOCK)_grt.def"]
write_db [file join $::env(OBJECT_DIR) "$::env(BLOCK)_grt.db"]
write_verilog [file join $::env(OBJECT_DIR) "$::env(BLOCK)_openroad.v"]
