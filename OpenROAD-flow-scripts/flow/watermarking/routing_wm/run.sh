#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Embed the routing watermark and run detail_route + finish.
#
# Reads the 32-byte routing seed from gen_key/out/<DESIGN>/seed_routing.hex and
# passes its hex serialization to `set_routing_watermark -key_hex` through
# pre_route_watermark.tcl.  The key bundle is generated on demand if missing.
#
# Required env:
#   DESIGN, PLATFORM, WM_FLOW_VARIANT   identify the reference run whose
#                                       4_cts.odb is the starting point
# Optional env:
#   DESIGN_NICKNAME      on-disk ORFS name (default: DESIGN)
#   FLOW_VARIANT         output variant    (default: pdmarks-r-only)
#   OWNER_ID             owner id recorded in the key bundle
#   WATERMARK_FRACTION   f, fraction of signal nets selected  (default 0.02)
#   WATERMARK_STRENGTH   lambda_wm, wrong-way cost multiplier (default 100.0)
#   WATERMARK_P          p cutoff for report_routing_watermark (default 0.4)
#   CTS_ODB              explicit post-CTS ODB to start from
#   SINGULARITY_SIF      run inside this container instead of natively
#
# Requires an OpenROAD build providing set_routing_watermark,
# set_routing_watermark_strength and report_routing_watermark -- see README.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../wm_env.sh"

: "${DESIGN:?set DESIGN}"
: "${PLATFORM:?set PLATFORM}"
: "${WM_FLOW_VARIANT:?set WM_FLOW_VARIANT (the reference flow variant)}"

export DESIGN DESIGN_NICKNAME="${DESIGN_NICKNAME:-${DESIGN}}" PLATFORM WM_FLOW_VARIANT
export FLOW_VARIANT="${FLOW_VARIANT:-pdmarks-r-only}"
export WM_RESULTS="${WM_RESULTS:-${WM_RESULTS_HOME}/${PLATFORM}/${DESIGN_NICKNAME}/${FLOW_VARIANT}}"

LOG_DIR="${SCRIPT_DIR}/wm_log"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/${DESIGN}_run_route_wm_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1
echo "[run_route_wm] logging to ${LOG_FILE}"

# Watermark parameters (paper Eqs. eq:routing_selection / eq:routing_pvalue).
export WATERMARK_FRACTION="${WATERMARK_FRACTION:-0.02}"     # f
export WATERMARK_STRENGTH="${WATERMARK_STRENGTH:-100.0}"    # lambda_wm
export WATERMARK_P="${WATERMARK_P:-0.4}"                    # report cutoff

BUNDLE_DIR="${GEN_KEY_DIR}/out/${DESIGN}"
SEED_ROUTING="${BUNDLE_DIR}/seed_routing.hex"

# Generate the owner keypair / per-design bundle on demand.
if [[ ! -f "${GEN_KEY_DIR}/keys/sk.pem" ]]; then
  echo "[run] generating owner keypair in ${GEN_KEY_DIR}/keys"
  ( cd "${GEN_KEY_DIR}" && ./gen_key.sh keygen --owner-id "${OWNER_ID}" --out-dir keys )
fi
if [[ ! -f "${SEED_ROUTING}" ]]; then
  echo "[run] signing bundle for design=${DESIGN}"
  ( cd "${GEN_KEY_DIR}" && ./gen_key.sh sign \
        --sk keys/sk.pem --pk keys/pk.pem \
        --owner-id "${OWNER_ID}" --design-id "${DESIGN}" \
        --out-dir "out/${DESIGN}" --force )
fi
export WM_SEED_HEX="${SEED_ROUTING}"

export PRE_GLOBAL_ROUTE_TCL="${SCRIPT_DIR}/pre_route_watermark.tcl"
export POST_DETAIL_ROUTE_TCL="${SCRIPT_DIR}/post_route_watermark.tcl"

# Pre-staged OR_inputs and ORFS results both live under DESIGN_NICKNAME;
# DESIGN_CONFIG below uses DESIGN (the directory under designs/).
export INPUTS_DIR="${FLOW_HOME}/OR_inputs/route_wm/${PLATFORM}/${DESIGN_NICKNAME}"
export CTS_ODB="${CTS_ODB:-${FLOW_HOME}/results/${PLATFORM}/${DESIGN_NICKNAME}/${WM_FLOW_VARIANT}/4_cts.odb}"
export SKIP_RT_WM="1"

echo "[run] seed_routing  : ${WM_SEED_HEX}"
echo "[run] fraction f    : ${WATERMARK_FRACTION}"
echo "[run] strength lwm  : ${WATERMARK_STRENGTH}"

wm_require_openroad
wm_exec make -f "${FLOW_HOME}/Makefile" \
     DESIGN_CONFIG="${FLOW_HOME}/designs/${PLATFORM}/${DESIGN}/config.mk" \
     OPENROAD_EXE="${OPENROAD_EXE}" \
     WORK_HOME="${EXPERIMENTS_HOME}" \
     wm_route_wrong_way
