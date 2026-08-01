#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Verify the CTS fanout-parity watermark across the post-CTS / GRT / DRT /
# final ODBs produced by run_ppa.sh.
#
# Required env:
#   DESIGN, PLATFORM, WM_FLOW_VARIANT
# Optional env:
#   DESIGN_NICKNAME   on-disk ORFS name (default: DESIGN)
#   FLOW_VARIANT      embed output variant   (default: WM_FLOW_VARIANT)
#   PPA_FLOW_VARIANT  run_ppa.sh variant     (default: <WM_FLOW_VARIANT>-ppa)
#   WM_VERIFY_STAGES  explicit 'label:odb,...' list, overriding the defaults

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../wm_env.sh"

: "${DESIGN:?set DESIGN}"
: "${PLATFORM:?set PLATFORM}"
: "${WM_FLOW_VARIANT:?set WM_FLOW_VARIANT (the reference flow variant)}"

DESIGN_NICKNAME="${DESIGN_NICKNAME:-${DESIGN}}"
FLOW_VARIANT="${FLOW_VARIANT:-${WM_FLOW_VARIANT}}"
PPA_FLOW_VARIANT="${PPA_FLOW_VARIANT:-${WM_FLOW_VARIANT}-ppa}"

EMBED_RES="${WM_RESULTS:-${WM_RESULTS_HOME}/${PLATFORM}/${DESIGN_NICKNAME}/${FLOW_VARIANT}}"
PPA_RES="${WM_RESULTS_HOME}/${PLATFORM}/${DESIGN_NICKNAME}/${PPA_FLOW_VARIANT}"

export WM_CELL_LIST="${WM_CELL_LIST:-${EMBED_RES}/wm_cts_pairs_embed.csv}"
export WM_VERIFY_STAGES="${WM_VERIFY_STAGES:-post_cts:${EMBED_RES}/4_cts_wm.odb,post_grt:${PPA_RES}/5_1_grt.odb,post_drt:${PPA_RES}/5_route.odb,post_final:${PPA_RES}/6_final.odb}"
export WM_STAGE_REPORT="${WM_STAGE_REPORT:-${EMBED_RES}/wm_cts_stage_report.csv}"

echo "[run_verify_stages] cell list : ${WM_CELL_LIST}"
echo "[run_verify_stages] stages    : ${WM_VERIFY_STAGES}"
echo "[run_verify_stages] report    : ${WM_STAGE_REPORT}"

"${SCRIPT_DIR}/cts_wm.sh" verify_stages
