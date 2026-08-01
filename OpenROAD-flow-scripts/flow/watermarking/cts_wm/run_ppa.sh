#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Continue the ORFS back-end (GRT + DRT + finish) from a watermarked CTS ODB,
# so PPA can be compared against the reference flow.
#
# Required env:
#   DESIGN, PLATFORM, WM_FLOW_VARIANT   identify the reference run
# Optional env:
#   DESIGN_NICKNAME  on-disk ORFS name  (default: DESIGN)
#   FLOW_VARIANT     output variant     (default: <WM_FLOW_VARIANT>-ppa)
#   CTS_ODB          watermarked CTS ODB to start from
#   SINGULARITY_SIF  run inside this container instead of natively

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../wm_env.sh"

: "${DESIGN:?set DESIGN}"
: "${PLATFORM:?set PLATFORM}"
: "${WM_FLOW_VARIANT:?set WM_FLOW_VARIANT (the reference flow variant)}"

export DESIGN DESIGN_NICKNAME="${DESIGN_NICKNAME:-${DESIGN}}" PLATFORM WM_FLOW_VARIANT
export FLOW_VARIANT="${FLOW_VARIANT:-${WM_FLOW_VARIANT}-ppa}"
export WM_RESULTS="${WM_RESULTS:-${WM_RESULTS_HOME}/${PLATFORM}/${DESIGN_NICKNAME}/${FLOW_VARIANT}}"
export CTS_ODB="${CTS_ODB:-${WM_RESULTS}/4_cts_wm.odb}"

# Pre-staged OR_inputs live under DESIGN_NICKNAME; DESIGN_CONFIG uses DESIGN.
export INPUTS_DIR="${FLOW_HOME}/OR_inputs/cts_wm/${PLATFORM}/${DESIGN_NICKNAME}"
export SKIP_RT_WM="1"

wm_require_openroad
wm_exec make -f "${FLOW_HOME}/Makefile" \
     DESIGN_CONFIG="${FLOW_HOME}/designs/${PLATFORM}/${DESIGN}/config.mk" \
     OPENROAD_EXE="${OPENROAD_EXE}" \
     WORK_HOME="${EXPERIMENTS_HOME}" \
     wm_cts
