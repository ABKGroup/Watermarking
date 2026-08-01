#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
#
# Blind/targeted routing-attack driver (paper §7.1).
#
# Like run.sh but uses attack_route_pre.tcl as PRE_GLOBAL_ROUTE_TCL.  The
# wrong-way bias is applied normally to every WM net, then dropped for the
# subset listed in WM_NETS_ATTACK before detail_route runs.
#
# Required env:
#   DESIGN, PLATFORM, WM_FLOW_VARIANT (always)
#   WM_NETS_ATTACK   path to a text file with one net name per line
#   FLOW_VARIANT     where to write attacked outputs (e.g. atk-r-aes-qs0.50)
#
# Optional env:
#   CTS_ODB                 input ODB (default: flow/results/.../<wm>/4_cts.odb)
#   WATERMARK_FRACTION/STRENGTH (default 0.05 / 100)
#   WM_RESULTS              experiments/results/.../<FLOW_VARIANT>/  (default derived)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../wm_env.sh"

: "${DESIGN:?set DESIGN}"
: "${PLATFORM:?set PLATFORM}"
: "${WM_FLOW_VARIANT:?set WM_FLOW_VARIANT (the reference flow variant)}"

export DESIGN DESIGN_NICKNAME="${DESIGN_NICKNAME:-${DESIGN}}" PLATFORM WM_FLOW_VARIANT
export FLOW_VARIANT="${FLOW_VARIANT:?FLOW_VARIANT must be set, e.g. atk-r-aes-qs0.50}"
export WM_RESULTS="${WM_RESULTS:-${WM_RESULTS_HOME}/${PLATFORM}/${DESIGN_NICKNAME}/${FLOW_VARIANT}}"

if [[ -z "${WM_NETS_ATTACK:-}" || ! -f "${WM_NETS_ATTACK}" ]]; then
  echo "[run_attack_route] ERROR: WM_NETS_ATTACK must point at an existing file" >&2
  exit 2
fi

LOG_DIR="${SCRIPT_DIR}/wm_log"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/${DESIGN}_run_attack_route_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1
echo "[run_attack_route] logging to ${LOG_FILE}"

export WATERMARK_FRACTION="${WATERMARK_FRACTION:-0.05}"
export WATERMARK_STRENGTH="${WATERMARK_STRENGTH:-100.0}"
export WATERMARK_P="${WATERMARK_P:-0.4}"

BUNDLE_DIR="${GEN_KEY_DIR}/out/${DESIGN}"
SEED_ROUTING="${BUNDLE_DIR}/seed_routing.hex"

# Ensure the per-design seed bundle exists (matches owner flow behavior).
KEYS_DIR="${GEN_KEY_DIR}/keys"
if [[ ! -f "${KEYS_DIR}/sk.pem" ]]; then
  echo "[run_attack_route] generating owner keypair in ${KEYS_DIR}"
  ( cd "${GEN_KEY_DIR}" && ./gen_key.sh keygen --owner-id "${OWNER_ID}" --out-dir keys )
fi
if [[ ! -f "${SEED_ROUTING}" ]]; then
  echo "[run_attack_route] signing bundle for design=${DESIGN}"
  ( cd "${GEN_KEY_DIR}" && ./gen_key.sh sign \
      --sk keys/sk.pem --pk keys/pk.pem \
      --owner-id "${OWNER_ID}" --design-id "${DESIGN}" \
      --out-dir "out/${DESIGN}" --force )
fi
export WM_SEED_HEX="${SEED_ROUTING}"

# Drive ORFS with the attack-aware pre-route hook instead of the owner one.
export PRE_GLOBAL_ROUTE_TCL="${SCRIPT_DIR}/attack_route_pre.tcl"
export POST_DETAIL_ROUTE_TCL="${SCRIPT_DIR}/post_route_watermark.tcl"

export INPUTS_DIR="${FLOW_HOME}/OR_inputs/route_wm/${PLATFORM}/${DESIGN_NICKNAME}"
export CTS_ODB="${CTS_ODB:-${FLOW_HOME}/results/${PLATFORM}/${DESIGN_NICKNAME}/${WM_FLOW_VARIANT}/4_cts.odb}"
export SKIP_RT_WM="1"

echo "[run_attack_route] WM_NETS_ATTACK : ${WM_NETS_ATTACK}"
echo "[run_attack_route] CTS_ODB        : ${CTS_ODB}"
echo "[run_attack_route] FLOW_VARIANT   : ${FLOW_VARIANT}"
echo "[run_attack_route] WM_RESULTS     : ${WM_RESULTS}"

mkdir -p "${WM_RESULTS}"
wm_require_openroad
wm_exec make -f "${FLOW_HOME}/Makefile" \
     DESIGN_CONFIG="${FLOW_HOME}/designs/${PLATFORM}/${DESIGN}/config.mk" \
     OPENROAD_EXE="${OPENROAD_EXE}" \
     WORK_HOME="${EXPERIMENTS_HOME}" \
     wm_route_wrong_way
