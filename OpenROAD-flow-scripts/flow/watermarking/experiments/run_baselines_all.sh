#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Run all prior-work baselines x 8 paper designs = 24 chained ORFS flows to
# populate the baseline rows of tab:ppa_ng45 and tab:ppa_asap7.
#
# Each baseline run.sh embeds its placement/CTS watermark on the reference ODB,
# runs `make wm_cts_and_route` (CTS + route + finish), and verifies at the DRT
# stage.  Outputs land under
#   experiments/results/<plat>/<nickname>/baseline-<method>/
#   experiments/logs/<plat>/<nickname>/baseline-<method>/6_report.json
# which is exactly where phase1_ppa.py looks.
#
# Usage:
#   bash run_baselines_all.sh                    # all methods, all 8 designs
#   bash run_baselines_all.sh --only row_parity  # one method (repeatable)
#   SKIP_DONE=1 bash run_baselines_all.sh        # skip designs already done
#   BASELINES="row_parity icmarks" bash run_baselines_all.sh
#
# To fan out across terminals, run one method per invocation:
#   BASELINES=row_parity       nohup bash run_baselines_all.sh > logs/b_rowparity.log 2>&1 &
#   BASELINES=buffer_insertion nohup bash run_baselines_all.sh > logs/b_bufins.log    2>&1 &
#   BASELINES=icmarks          nohup bash run_baselines_all.sh > logs/b_icmarks.log   2>&1 &
#
# Notes:
#  * BP uses DESIGN=bp_multi_top (config) but DESIGN_NICKNAME=bp_multi (results);
#    the per-method run.sh honor DESIGN_NICKNAME for all filesystem paths.
#  * Each flow takes minutes-to-hours; run under nohup/tmux for the full sweep.


set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="${HERE}/baselines"

# method -> run.sh
declare -A DRIVER=(
  [row_parity]="${BASE}/row_parity/run.sh"
  [buffer_insertion]="${BASE}/buffer_insertion/run.sh"
  [icmarks]="${BASE}/icmarks/run.sh"
)
# method -> FLOW_VARIANT written under experiments/{results,logs}
declare -A VARIANT=(
  [row_parity]="baseline-row-parity"
  [buffer_insertion]="baseline-bufins"
  [icmarks]="baseline-icmarks"
)

BASELINES="${BASELINES:-row_parity buffer_insertion icmarks}"
# --only <method> [--only <method> ...] restricts the run to specific baselines
# (equivalent to BASELINES="<m1> <m2> ...").  Do NOT shift inside a loop over
# "$@" -- that corrupts the args and silently falls back to all methods.
ONLY=()
args=("$@")
idx=0
while [[ ${idx} -lt ${#args[@]} ]]; do
  if [[ "${args[${idx}]}" == "--only" ]]; then
    nxt=$((idx + 1))
    [[ ${nxt} -lt ${#args[@]} ]] && ONLY+=("${args[${nxt}]}")
    idx=$((idx + 2))
  else
    idx=$((idx + 1))
  fi
done
[[ ${#ONLY[@]} -gt 0 ]] && BASELINES="${ONLY[*]}"

SKIP_DONE="${SKIP_DONE:-0}"
export OWNER_ID="${OWNER_ID:-pdmarks-owner}"

# 8 paper designs: "platform design ref_variant nickname"
read -r -d '' BENCHES <<'EOF' || true
nangate45 jpeg           watermarking-test1 jpeg
nangate45 swerv_wrapper  base               swerv_wrapper
nangate45 ariane136      base_tcp3p5        ariane136
nangate45 bp_multi_top   base_tcp3p2        bp_multi
asap7     jpeg           base_tcp540        jpeg
asap7     swerv_wrapper  base_tcp1455       swerv_wrapper
asap7     cva6           base_tcp950        cva6
asap7     ariane         base_fixed         ariane
EOF

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] [run_baselines_all] $*"; }

pass=0; skip=0; fail=0; FAILED=()

while read -r PLAT DSGN VAR NICK; do
  [[ -z "${PLAT:-}" ]] && continue
  for m in ${BASELINES}; do
    drv="${DRIVER[$m]:-}"
    fv="${VARIANT[$m]:-}"
    if [[ -z "${drv}" ]]; then log "unknown baseline '${m}'"; continue; fi
    report="${HERE}/logs/${PLAT}/${NICK}/${fv}/6_report.json"
    if [[ "${SKIP_DONE}" == "1" && -f "${report}" ]]; then
      log "SKIP  ${PLAT}/${NICK}/${fv} (done)"; ((skip++)) || true; continue
    fi
    log "START ${m} on ${PLAT}/${DSGN} (nick=${NICK}, ref=${VAR})"
    if DESIGN="${DSGN}" DESIGN_NICKNAME="${NICK}" PLATFORM="${PLAT}" \
       WM_FLOW_VARIANT="${VAR}" FLOW_VARIANT="${fv}" \
       bash "${drv}"; then
      log "OK    ${m} ${PLAT}/${NICK}"; ((pass++)) || true
    else
      log "FAIL  ${m} ${PLAT}/${NICK}"; FAILED+=("${m}:${PLAT}/${NICK}"); ((fail++)) || true
    fi
  done
done <<< "${BENCHES}"

log "================================================"
log "Done: ${pass} passed, ${skip} skipped, ${fail} failed"
for r in "${FAILED[@]:-}"; do [[ -n "${r}" ]] && log "  FAILED ${r}"; done
log ""
log "Next: refresh the PPA tables with"
log "  python3 ${HERE}/phase1_ppa.py"
log "  python3 ${HERE}/aggregate.py --what ppa"
log "  python3 ${HERE}/render_tex.py"
[[ ${fail} -gt 0 ]] && exit 1 || exit 0
