#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Full reroute (all nets) + route_qr, to test whether a full reroute removes
# the routing watermark (reuses wm_nets.txt dumped by the surgical run).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd "$HERE"
source "$HERE/../wm_env.sh"
WM="$WM_HOME"
TCL="$WM/routing_wm/reroute_experiment.tcl"
OUTB="$HERE/results/phase3/removal_check"
for nick in jpeg swerv_wrapper ariane136 bp_multi; do
  IN="$HERE/results/nangate45/$nick/pdmarks-all-stage/5_route.odb"
  OD="$OUTB/$nick"; OUT="$OD/5_route_full.odb"
  echo "===== $nick : FULL reroute  $(date '+%H:%M:%S') ====="
  wm_exec env \
    MODE=full WM_ODB="$(readlink -f "$IN")" WM_OUT_ODB="$OUT" \
    "$OPENROAD_EXE" -exit -threads 8 "$TCL" > "$OD/full.log" 2>&1
  [ -f "$OUT" ] || { echo "  [err] no ODB"; continue; }
  echo "  $(grep -oE 'reroute_nets=[0-9]+' "$OD/full.log" | tail -1)"
  WM_ODB="$(readlink -f "$OUT")" WM_QR_CSV="$OD/route_qr_full.csv" \
    OPENROAD_EXE="$OPENROAD_EXE" bash "$HERE/tools/dump_route_qr.sh" \
    > "$OD/dump_full.log" 2>&1 && echo "  route_qr_full -> ok" || echo "  [warn] dump failed"
  rm -f "$OUT"   # bound disk; keep only the route_qr CSV
done
echo "===== full-reroute done $(date) ====="
