proc require_env {name} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    puts stderr "Missing required environment variable: $name"
    exit 1
  }
}

foreach name {
  TOP
  LIBERTY
  MAPPED_VERILOG
  SDC_FILE
  REPORT_DIR
  STA_STAGE
} {
  require_env $name
}

read_liberty $::env(LIBERTY)

if {[info exists ::env(LEF_FILES)] && $::env(LEF_FILES) ne ""} {
  foreach lef $::env(LEF_FILES) {
    read_lef $lef
  }
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

set_power_activity -input -activity 0.10

file mkdir $::env(REPORT_DIR)
set prefix [file join $::env(REPORT_DIR) $::env(STA_STAGE)]

report_checks -path_delay max -fields {slew cap input net fanout} -digits 3 > "${prefix}_setup.rpt"
report_checks -path_delay min -fields {slew cap input net fanout} -digits 3 > "${prefix}_hold.rpt"
report_worst_slack -max -digits 3 > "${prefix}_worst_slack_max.rpt"
report_worst_slack -min -digits 3 > "${prefix}_worst_slack_min.rpt"
report_tns -digits 3 > "${prefix}_tns.rpt"
sta::redirect_file_begin "${prefix}_area.rpt"
report_design_area
sta::redirect_file_end
report_power > "${prefix}_power.rpt"
