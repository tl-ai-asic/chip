#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <block-flow.env>" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT

if [ -f "${PROJECT_ROOT}/verilator-env.sh" ]; then
  # Provides local yosys/openroad binaries when installed under .local/.
  # shellcheck disable=SC1091
  . "${PROJECT_ROOT}/verilator-env.sh"
fi

CONFIG="$1"
case "$CONFIG" in
  /*) ;;
  *) CONFIG="${PWD}/${CONFIG}" ;;
esac

# shellcheck disable=SC1090
source "$CONFIG"

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required config variable: ${name}" >&2
    exit 1
  fi
}

for name in BLOCK TOP CLOCK_PORT CLOCK_PERIOD_NS LIBERTY SITE DIE_AREA CORE_AREA; do
  require_var "$name"
done

if ! declare -p RTL_FILES >/dev/null 2>&1 || [ "${#RTL_FILES[@]}" -eq 0 ]; then
  echo "RTL_FILES must contain at least one source file" >&2
  exit 1
fi

if ! declare -p LEF_FILES >/dev/null 2>&1 || [ "${#LEF_FILES[@]}" -eq 0 ]; then
  echo "LEF_FILES must contain at least one LEF file" >&2
  exit 1
fi

for tool in yosys openroad; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool not found in PATH: ${tool}" >&2
    exit 1
  fi
done

RUN_DIR="${PROJECT_ROOT}/build/openroad/${BLOCK}"
LOG_DIR="${RUN_DIR}/logs"
REPORT_DIR="${RUN_DIR}/reports"
OBJECT_DIR="${RUN_DIR}/objects"
mkdir -p "$LOG_DIR" "$REPORT_DIR" "$OBJECT_DIR"
rm -f "$LOG_DIR"/*.log "$REPORT_DIR"/*.rpt

export BLOCK TOP LIBERTY SITE DIE_AREA CORE_AREA REPORT_DIR OBJECT_DIR
export PLACE_DENSITY="${PLACE_DENSITY:-0.55}"
export REPAIR_MAX_WIRE_LENGTH="${REPAIR_MAX_WIRE_LENGTH:-0}"
export REPAIR_TIMING_SETUP="${REPAIR_TIMING_SETUP:-0}"
export REPAIR_TIMING_MAX_BUFFER_PERCENT="${REPAIR_TIMING_MAX_BUFFER_PERCENT:-20}"
export REPAIR_TIMING_MAX_PASSES="${REPAIR_TIMING_MAX_PASSES:-2}"
export REPAIR_TIMING_MAX_ITERATIONS="${REPAIR_TIMING_MAX_ITERATIONS:-500}"
export REPAIR_TIMING_MAX_REPAIRS_PER_PASS="${REPAIR_TIMING_MAX_REPAIRS_PER_PASS:-1000}"
export SIGNAL_ROUTING_LAYERS="${SIGNAL_ROUTING_LAYERS:-metal2-metal10}"
export CLOCK_ROUTING_LAYERS="${CLOCK_ROUTING_LAYERS:-metal3-metal10}"
export RC_FILE="${RC_FILE:-}"
export WIRE_RC_LAYER="${WIRE_RC_LAYER:-}"
export CLOCK_RC_LAYER="${CLOCK_RC_LAYER:-}"
export IO_H_LAYER="${IO_H_LAYER:-metal3}"
export IO_V_LAYER="${IO_V_LAYER:-metal2}"
export RESET_PORT="${RESET_PORT:-}"
export RESET_RELEASE_SYNCHRONIZED="${RESET_RELEASE_SYNCHRONIZED:-0}"

MAPPED_VERILOG="${OBJECT_DIR}/${BLOCK}_mapped.v"
MAPPED_JSON="${OBJECT_DIR}/${BLOCK}_mapped.json"
SDC_FILE="${OBJECT_DIR}/${BLOCK}.sdc"
YOSYS_SCRIPT="${RUN_DIR}/${BLOCK}_synth.ys"
export MAPPED_VERILOG MAPPED_JSON SDC_FILE

{
  for rtl in "${RTL_FILES[@]}"; do
    echo "read_verilog -sv ${rtl}"
  done
  echo "hierarchy -check -top ${TOP}"
  echo "synth -top ${TOP}"
  echo "dfflibmap -liberty ${LIBERTY}"
  echo "abc -liberty ${LIBERTY}"
  echo "clean"
  echo "stat -liberty ${LIBERTY}"
  echo "write_json ${MAPPED_JSON}"
  echo "write_verilog -noattr -noexpr ${MAPPED_VERILOG}"
} > "$YOSYS_SCRIPT"

{
  echo "create_clock -name ${CLOCK_PORT} -period ${CLOCK_PERIOD_NS} [get_ports ${CLOCK_PORT}]"
  echo "set_input_delay -clock ${CLOCK_PORT} 0.0 [all_inputs -no_clocks]"
  echo "set_output_delay -clock ${CLOCK_PORT} 0.0 [all_outputs]"
  if [ -n "${RESET_PORT:-}" ] && [ "${RESET_RELEASE_SYNCHRONIZED:-0}" = "1" ]; then
    echo "set_false_path -from [get_ports ${RESET_PORT}]"
  fi
} > "$SDC_FILE"

echo "[flow] Synthesizing ${BLOCK}"
yosys -s "$YOSYS_SCRIPT" > "${LOG_DIR}/yosys.log" 2>&1

LEF_FILES_LIST="${LEF_FILES[*]}"
unset LEF_FILES
export LEF_FILES="$LEF_FILES_LIST"
export STA_STAGE="pre_place"

echo "[flow] Running pre-place STA for ${BLOCK}"
openroad -exit "${PROJECT_ROOT}/flow/scripts/sta.tcl" > "${LOG_DIR}/openroad_sta_pre_place.log" 2>&1

echo "[flow] Running floorplan, placement, and global route for ${BLOCK}"
openroad -exit "${PROJECT_ROOT}/flow/scripts/place_route.tcl" > "${LOG_DIR}/openroad_place_route.log" 2>&1

echo "[flow] Done. Reports: ${REPORT_DIR}"
