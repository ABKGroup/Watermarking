# PDMarks — Kerckhoffs-compliant watermarking for physical design

Reference implementation for *"Kerckhoffs-Compliant Watermarking for Physical
Design IP Protection: From Placement to Routing."*

PDMarks embeds keyed ownership evidence at three stages of the OpenROAD flow.
Security rests solely on a secret key: every watermarked object and every target
value is derived from a 32-byte master key via domain-separated HMAC-SHA256, so
the algorithm and these scripts can be fully public.

| Directory | Stage | Carrier | Evidence |
|---|---|---|---|
| [`placement_wm/`](placement_wm/) | Placement | keyed x-order of same-row cell pairs | `r_P` |
| [`cts_wm/`](cts_wm/) | CTS | leaf-clock-buffer fanout parity | `r_C` |
| [`routing_wm/`](routing_wm/) | Routing | keyed wrong-way routing bias | `T_R`, `p_R` |
| [`gen_key/`](gen_key/) | — | master key commitment + stage seeds | — |
| [`experiments/`](experiments/) | — | paper reproduction harness | — |

Two files are shared by everything:

- **`wm_prf.py`** — the keyed primitives (HMAC PRF, seed loading, `P_c`).
  Embedders and verifiers import these rather than reimplementing them; the
  watermark only verifies if both sides agree byte-for-byte.
- **`wm_env.sh`** — resolves `FLOW_HOME` / `OPENROAD_EXE` and provides
  `wm_exec`, so every shell entry point behaves the same.

## Requirements

- **OpenROAD** built with the PDMarks routing commands
  (`set_routing_watermark`, `set_routing_watermark_strength`,
  `report_routing_watermark`, `clear_routing_watermark`).
  These are **not yet in upstream OpenROAD** — see
  [`routing_wm/README.md`](routing_wm/README.md#requirements) for where to get
  them. Placement and CTS watermarking work with a stock OpenROAD build.
- **OpenROAD-flow-scripts** with the NanGate45 and/or ASAP7 platforms.
- **Python 3.9+**, plus `pip install -r requirements.txt` for `gen_key/` and the
  experiment harness.

## Configuration

Everything is resolved from the environment; nothing is hard-coded to a machine.

| Variable | Meaning | Default |
|---|---|---|
| `ORFS_FLOW_HOME` | ORFS flow root | derived from this file's location |
| `OPENROAD_EXE` | OpenROAD binary | `openroad` on `PATH` |
| `SINGULARITY_SIF` | run inside this container | unset = run natively |
| `OWNER_ID` | identity recorded in the key bundle | `pdmarks-owner` |

Containers are opt-in: set `SINGULARITY_SIF` and every script re-executes inside
it; leave it unset and everything runs on the host.

## Quick start

Watermarking consumes the outputs of a completed reference flow, so build one
first. The example below uses `jpeg` on NanGate45 with flow variant `base`.

```bash
export ORFS_FLOW_HOME=/path/to/OpenROAD-flow-scripts/flow
export OPENROAD_EXE=/path/to/openroad
export DESIGN=jpeg PLATFORM=nangate45 WM_FLOW_VARIANT=base
export OWNER_ID=alice          # identity bound into the key bundle

# 1. Reference (un-watermarked) run — required input for every stage.
cd "$ORFS_FLOW_HOME"
make DESIGN_CONFIG=./designs/$PLATFORM/$DESIGN/config.mk FLOW_VARIANT=$WM_FLOW_VARIANT

# 2. Owner keypair + per-design stage seeds.
cd watermarking/gen_key
./gen_key.sh keygen --owner-id "$OWNER_ID" --out-dir keys
./gen_key.sh sign --sk keys/sk.pem --pk keys/pk.pem \
    --owner-id "$OWNER_ID" --design-id "$DESIGN" --out-dir "out/$DESIGN"

# 3. Embed + self-verify, one stage at a time.
cd ../placement_wm && ./run_place_wm.sh    # 3_place.odb -> 3_place_order_wm.odb
cd ../cts_wm       && ./run_cts_wm.sh      # 4_cts.odb   -> 4_cts_wm.odb
cd ../routing_wm   && ./run.sh             # tags nets, then detail-routes
```

Each stage writes its watermarked ODB and a ground-truth CSV under
`experiments/results/<platform>/<design>/<variant>/`. The CSV is the
verification commitment — keep it.

`DESIGN`, `PLATFORM` and `WM_FLOW_VARIANT` are required by every script and
have no defaults, so a run either targets the design you meant or fails
immediately.

## Verifying a suspect layout

```bash
cd "$ORFS_FLOW_HOME"/watermarking/placement_wm
WM_VERIFY_INPUT=/path/to/suspect.odb \
WM_CELL_LIST=/path/to/wm_place_order_embed.csv \
  ./place_wm.sh verify        # exit 0 = all claims hold, 2 = mismatch
```

`cts_wm/cts_wm.sh verify` is the same for the CTS stage. For routing, dump the
per-net statistic and run the test — see
[`routing_wm/README.md`](routing_wm/README.md#verification).

## Reproducing the paper

[`experiments/README.md`](experiments/README.md) is the full runbook (PPA,
capacity, survival, wrong-key, sensitivity, attacks), and
[`experiments/baselines/README.md`](experiments/baselines/README.md) covers the
prior-work comparisons.

## License

BSD-3-Clause, matching OpenROAD-flow-scripts. Every source file carries an SPDX
header.
