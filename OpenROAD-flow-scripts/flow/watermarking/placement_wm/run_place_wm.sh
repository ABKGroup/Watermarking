#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# End-to-end placement-watermark example: key bundle -> embed -> self-verify.
#
# Required env:
#   DESIGN, PLATFORM, WM_FLOW_VARIANT   identify a completed reference ORFS run
#                                       whose 3_place.odb is the input
# Optional env:
#   DESIGN_NICKNAME  on-disk ORFS name (default: DESIGN)
#   FLOW_VARIANT     output variant    (default: WM_FLOW_VARIANT)
#   OWNER_ID         owner id recorded in the key bundle
#   WM_*             any embed tunable; see README.md.  This script sets NONE
#                    of them, so watermark_embed.py's argparse defaults are the
#                    single source of truth.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../wm_env.sh"

: "${DESIGN:?set DESIGN}"
: "${PLATFORM:?set PLATFORM}"
: "${WM_FLOW_VARIANT:?set WM_FLOW_VARIANT (the reference flow variant)}"

DESIGN_NICKNAME="${DESIGN_NICKNAME:-${DESIGN}}"
FLOW_VARIANT="${FLOW_VARIANT:-${WM_FLOW_VARIANT}}"

RUN_START_EPOCH="$(date +%s)"
ts()  { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] [run_place_wm] $*"; }
finish_log() {
  local status=$?
  echo "[$(ts)] [run_place_wm] finished status=${status} elapsed=$(( $(date +%s) - RUN_START_EPOCH ))s"
  exit "${status}"
}
trap finish_log EXIT

LOG_DIR="${SCRIPT_DIR}/wm_log"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/${DESIGN}_run_place_wm_ordering_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1
log "logging to ${LOG_FILE}"

# Reference ORFS results dir and experiment output dir both use DESIGN_NICKNAME.
export REF_RES="${FLOW_HOME}/results/${PLATFORM}/${DESIGN_NICKNAME}/${WM_FLOW_VARIANT}"
export WM_OUT_RES="${WM_RESULTS:-${WM_RESULTS_HOME}/${PLATFORM}/${DESIGN_NICKNAME}/${FLOW_VARIANT}}"
mkdir -p "${WM_OUT_RES}"

# --- key bundle (generated on demand) --------------------------------------
if [[ ! -f "${GEN_KEY_DIR}/keys/sk.pem" ]]; then
  log "generating owner keypair in ${GEN_KEY_DIR}/keys"
  ( cd "${GEN_KEY_DIR}" && ./gen_key.sh keygen --owner-id "${OWNER_ID}" --out-dir keys )
fi
SEED_PLACEMENT="${GEN_KEY_DIR}/out/${DESIGN}/seed_placement.hex"
if [[ ! -f "${SEED_PLACEMENT}" ]]; then
  log "signing bundle for design=${DESIGN}"
  ( cd "${GEN_KEY_DIR}" && ./gen_key.sh sign \
      --sk keys/sk.pem --pk keys/pk.pem \
      --owner-id "${OWNER_ID}" --design-id "${DESIGN}" \
      --out-dir "out/${DESIGN}" --force )
fi

# --- inputs / outputs -------------------------------------------------------
export WM_SEED_HEX="${SEED_PLACEMENT}"
export WM_INPUT="${WM_INPUT:-${REF_RES}/3_place.odb}"
export WM_OUTPUT_ODB="${WM_OUTPUT_ODB:-${WM_OUT_RES}/3_place_order_wm.odb}"
export WM_OUTPUT_DEF="${WM_OUTPUT_DEF:-${WM_OUT_RES}/3_place_order_wm.def}"
export WM_OUTPUT_CELL_LIST="${WM_OUTPUT_CELL_LIST:-${WM_OUT_RES}/wm_place_order_embed.csv}"
export WM_VERIFY_CELL_LIST="${WM_VERIFY_CELL_LIST:-${WM_OUT_RES}/wm_place_order_verify.csv}"

# Liberty files for the STA slack filter; auto-discovered from ORFS when unset.
if [[ -z "${WM_LIB_FILES:-}" ]]; then
  _make_out="$(make -C "${FLOW_HOME}" print-LIB_FILES \
    DESIGN_CONFIG="./designs/${PLATFORM}/${DESIGN}/config.mk" \
    CORNER="${WM_CORNER:-TC}" 2>/dev/null || true)"
  WM_LIB_FILES="$(echo "${_make_out}" | grep "^LIB_FILES:" | sed 's/^LIB_FILES:[[:space:]]*//')"
  [[ -z "${WM_LIB_FILES}" ]] && log "WARNING: could not auto-discover LIB_FILES"
fi
export WM_LIB_FILES
export WM_SDC="${WM_SDC:-${REF_RES}/3_place.sdc}"
export PYTHONUNBUFFERED="${PYTHONUNBUFFERED:-1}"

log "design : ${PLATFORM}/${DESIGN}/${WM_FLOW_VARIANT} -> ${FLOW_VARIANT}"
log "seed   : ${WM_SEED_HEX}"
log "input  : ${WM_INPUT}"
log "output : ${WM_OUTPUT_ODB}"
log "starting embed + verify"

"${SCRIPT_DIR}/place_wm.sh" all
