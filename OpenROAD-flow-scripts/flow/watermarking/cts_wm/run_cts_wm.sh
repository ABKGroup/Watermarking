#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# End-to-end CTS-watermark example: key bundle -> embed -> self-verify.
#
# Required env:
#   DESIGN, PLATFORM, WM_FLOW_VARIANT   identify a completed reference ORFS run
#                                       whose 4_cts.odb is the input
# Optional env:
#   DESIGN_NICKNAME  on-disk ORFS name (default: DESIGN)
#   FLOW_VARIANT     output variant    (default: WM_FLOW_VARIANT)
#   OWNER_ID         owner id recorded in the key bundle
#   WM_CTS_*         any embed tunable; see README.md.  This script sets NONE
#                    of them, so cts_watermark_embed.py's argparse defaults are
#                    the single source of truth.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../wm_env.sh"

: "${DESIGN:?set DESIGN}"
: "${PLATFORM:?set PLATFORM}"
: "${WM_FLOW_VARIANT:?set WM_FLOW_VARIANT (the reference flow variant)}"

DESIGN_NICKNAME="${DESIGN_NICKNAME:-${DESIGN}}"
FLOW_VARIANT="${FLOW_VARIANT:-${WM_FLOW_VARIANT}}"

LOG_DIR="${SCRIPT_DIR}/wm_log"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/${DESIGN}_run_cts_wm_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1
echo "[run_cts_wm] logging to ${LOG_FILE}"

# Reference ORFS results dir and experiment output dir both use DESIGN_NICKNAME.
export REF_RES="${FLOW_HOME}/results/${PLATFORM}/${DESIGN_NICKNAME}/${WM_FLOW_VARIANT}"
export WM_OUT_RES="${WM_RESULTS:-${WM_RESULTS_HOME}/${PLATFORM}/${DESIGN_NICKNAME}/${FLOW_VARIANT}}"
mkdir -p "${WM_OUT_RES}"

# --- key bundle (generated on demand) --------------------------------------
if [[ ! -f "${GEN_KEY_DIR}/keys/sk.pem" ]]; then
  echo "[run_cts_wm] generating owner keypair in ${GEN_KEY_DIR}/keys"
  ( cd "${GEN_KEY_DIR}" && ./gen_key.sh keygen --owner-id "${OWNER_ID}" --out-dir keys )
fi
SEED_CTS="${GEN_KEY_DIR}/out/${DESIGN}/seed_cts.hex"
if [[ ! -f "${SEED_CTS}" ]]; then
  echo "[run_cts_wm] signing binding message for design=${DESIGN}"
  ( cd "${GEN_KEY_DIR}" && ./gen_key.sh sign \
      --sk keys/sk.pem --pk keys/pk.pem \
      --owner-id "${OWNER_ID}" --design-id "${DESIGN}" \
      --out-dir "out/${DESIGN}" --force )
fi

# --- inputs / outputs -------------------------------------------------------
export WM_SEED_HEX="${SEED_CTS}"
export WM_CTS_INPUT="${WM_CTS_INPUT:-${REF_RES}/4_cts.odb}"
export WM_CTS_OUTPUT_ODB="${WM_CTS_OUTPUT_ODB:-${WM_OUT_RES}/4_cts_wm.odb}"
export WM_CTS_OUTPUT_CSV="${WM_CTS_OUTPUT_CSV:-${WM_OUT_RES}/wm_cts_pairs_embed.csv}"

# Liberty files for the STA slew/skew checks; auto-discovered when unset.
if [[ -z "${WM_LIB_FILES:-}" ]]; then
  _make_out="$(make -C "${FLOW_HOME}" print-LIB_FILES \
    DESIGN_CONFIG="./designs/${PLATFORM}/${DESIGN}/config.mk" \
    CORNER="${WM_CORNER:-BC}" 2>/dev/null || true)"
  WM_LIB_FILES="$(echo "${_make_out}" | grep "^LIB_FILES:" | sed 's/^LIB_FILES:[[:space:]]*//')"
  if [[ -z "${WM_LIB_FILES}" ]]; then
    echo "[run_cts_wm] WARNING: could not auto-discover LIB_FILES;" \
         "timing checks will be best-effort" >&2
  fi
fi
export WM_LIB_FILES
export WM_SDC="${WM_SDC:-${REF_RES}/4_cts.sdc}"
export WM_SETRC="${WM_SETRC:-${FLOW_HOME}/platforms/${PLATFORM}/setRC.tcl}"

echo "[run_cts_wm] design : ${PLATFORM}/${DESIGN}/${WM_FLOW_VARIANT} -> ${FLOW_VARIANT}"
echo "[run_cts_wm] seed   : ${WM_SEED_HEX}"
echo "[run_cts_wm] input  : ${WM_CTS_INPUT}"
echo "[run_cts_wm] output : ${WM_CTS_OUTPUT_ODB}"
echo "[run_cts_wm] csv    : ${WM_CTS_OUTPUT_CSV}"

"${SCRIPT_DIR}/cts_wm.sh" "${1:-all}"

# Optional per-stage certification; see the note in placement_wm/run_place_wm.sh.
if [[ "${PDMARKS_CERTIFY:-0}" == "1" ]]; then
  echo "[run_cts_wm] certify (CTS only)"
  WM_RESULTS="${WM_OUT_RES}" \
    "${WM_HOME}/certificate/cert.sh" certify \
      --results-dir "${WM_OUT_RES}" --stages cts --force
fi
