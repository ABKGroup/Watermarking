# PDMarks — Kerckhoffs-Compliant Watermarking for Physical Design IP Protection

Reference implementation for the paper *"Kerckhoffs-Compliant Watermarking for
Physical Design IP Protection: From Placement to Routing."*

PDMarks embeds keyed ownership evidence at three stages of the physical-design
flow. Security rests solely on a secret key: every watermark object selection and
target value is derived from a 32-byte master key via domain-separated
HMAC-SHA256, so the algorithm and scripts can be public.

## Modules

| Directory | Stage | Watermark carrier | Verification |
|---|---|---|---|
| `placement_wm/` | Placement | keyed local ordering of same-row cell tuples | `r_P` |
| `cts_wm/` | CTS | leaf-clock-buffer (LCB) fanout parity | `r_C` |
| `routing_wm/` | Routing | keyed population-level wrong-way routing bias | `T_R`, `p_R` |
| `gen_key/` | — | master-key commitment and stage-seed derivation | — |
| `experiments/` | — | reproduction harness for the paper | — |

## Requirements

- **OpenROAD** built with the PDMarks routing commands (`set_routing_watermark`,
  `set_routing_watermark_strength`, `report_routing_watermark`,
  `clear_routing_watermark`); point `OPENROAD_EXE` at the binary.
- **OpenROAD-flow-scripts** with the NanGate45 / ASAP7 platforms.
- **Python 3.11+**; analysis scripts also need `numpy`, `scikit-learn`,
  `matplotlib` (`experiments/sbpy` selects an environment that has them).

## Usage

```bash
export ORFS_FLOW_HOME=/path/to/OpenROAD-flow-scripts/flow
export OPENROAD_EXE=/path/to/openroad

# 1. Reference (un-watermarked) layout — required input for every experiment
cd "$ORFS_FLOW_HOME" && make DESIGN_CONFIG=./designs/nangate45/jpeg/config.mk

# 2. Master key + per-stage seeds
cd watermarking/gen_key && ./sign_and_derive.py --design jpeg

# 3. Embed + verify
cd ../placement_wm && ./run_place_wm.sh     # placement
cd ../cts_wm       && ./run_cts_wm.sh       # CTS
cd ../routing_wm   && ./run.sh              # routing
```

Watermarking consumes the reference-flow outputs
(`flow/results/<platform>/<design>/<variant>/{3_place,4_cts,5_route}.odb`), so
step 1 must complete first.

## Reproducing the paper

See [`experiments/README.md`](experiments/README.md) for the full runbook (PPA,
capacity, survival, wrong-key, sensitivity, and attack evaluations) and
[`experiments/baselines/README.md`](experiments/baselines/README.md) for the
comparison baselines.
