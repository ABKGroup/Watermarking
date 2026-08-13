# PDMarks

PDMarks is a Kerckhoffs-compliant watermarking framework for physical design IP
protection. It is the reference implementation for *"Kerckhoffs-Compliant
Watermarking for Physical Design IP Protection: From Placement to Routing"*.

PDMarks embeds keyed ownership evidence at three stages of the OpenROAD flow.
Security rests on the secret key alone. Every watermarked object and every
target value is derived from a 32-byte master key by domain-separated
HMAC-SHA256, so the algorithms and these scripts can be public.

| Directory | Stage | Carrier | Evidence |
| ----- | ----- | ----- | ----- |
| [`placement_wm/`](placement_wm/) | Placement | keyed x-order of same-row cell pairs | `r_P` |
| [`cts_wm/`](cts_wm/) | CTS | leaf-clock-buffer fanout parity | `r_C` |
| [`routing_wm/`](routing_wm/) | Routing | keyed wrong-way routing bias | `T_R`, `p_R` |
| [`gen_key/`](gen_key/) | — | owner keypair, master seed and stage seeds | — |
| [`certificate/`](certificate/) | — | sealed claim certificate and ownership verification | verdict |
| [`experiments/`](experiments/) | — | paper reproduction harness | — |

## Shared modules

| File | Description |
| ----- | ----- |
| [`wm_prf.py`](wm_prf.py) | Keyed primitives: the HMAC PRF, seed loading, and `P_c`. Embedders and verifiers import these instead of reimplementing them. The watermark verifies only if both sides agree byte for byte. |
| [`wm_cert.py`](wm_cert.py) | Certificate encoding, sealing, opening and key commitment. |
| [`wm_aesgcm.py`](wm_aesgcm.py) | Vendored AES-GCM, used when `cryptography` is unavailable. |
| [`wm_claims.py`](wm_claims.py) | Claim loading for the verifiers, from either the embed CSV or a certificate. |
| [`wm_env.sh`](wm_env.sh) | Resolves `FLOW_HOME` and `OPENROAD_EXE` and provides `wm_exec`, so every shell entry point behaves the same. |

The three certificate modules use only the standard library. They are imported
inside `openroad -python`, where third-party packages are not available.

## Requirements

- OpenROAD built with the PDMarks routing commands (`set_routing_watermark`,
  `set_routing_watermark_strength`, `report_routing_watermark`,
  `clear_routing_watermark`). These commands are not in upstream OpenROAD. See
  [`routing_wm/README.md`](routing_wm/README.md#requirements) for how to obtain
  them. Placement and CTS watermarking run on a stock OpenROAD build.
- OpenROAD-flow-scripts with the NanGate45 or ASAP7 platforms.
- Python 3.9 or later. Run `pip install -r requirements.txt` for `gen_key/` and
  the experiment harness.

## Configuration

Every path is resolved from the environment. Nothing is hard-coded to a machine.

| Variable | Description | Default |
| ----- | ----- | ----- |
| `ORFS_FLOW_HOME` | ORFS flow root. | Derived from this file's location. |
| `OPENROAD_EXE` | OpenROAD binary. | `openroad` on `PATH`. |
| `SINGULARITY_SIF` | Container image to run inside. | Unset, which runs natively. |
| `OWNER_ID` | Identity recorded in the key bundle. | `pdmarks-owner` |

Containers are opt-in. Set `SINGULARITY_SIF` and every script re-executes inside
it.

## Quick start

Watermarking consumes the outputs of a completed reference flow, so build one
first. The example below uses `jpeg` on NanGate45 with flow variant `base`.

```bash
export ORFS_FLOW_HOME=/path/to/OpenROAD-flow-scripts/flow
export OPENROAD_EXE=/path/to/openroad
export DESIGN=jpeg PLATFORM=nangate45 WM_FLOW_VARIANT=base
export OWNER_ID=alice          # identity bound into the key bundle

# 1. Reference (un-watermarked) run. Required input for every stage.
cd "$ORFS_FLOW_HOME"
make DESIGN_CONFIG=./designs/$PLATFORM/$DESIGN/config.mk FLOW_VARIANT=$WM_FLOW_VARIANT

# 2. Owner keypair and per-design stage seeds.
cd watermarking/gen_key
./gen_key.sh keygen --owner-id "$OWNER_ID" --out-dir keys
./gen_key.sh sign --sk keys/sk.pem --pk keys/pk.pem \
    --owner-id "$OWNER_ID" --design-id "$DESIGN" --out-dir "out/$DESIGN"

# 3. Embed and self-verify, one stage at a time.
cd ../placement_wm && ./run_place_wm.sh    # 3_place.odb -> 3_place_order_wm.odb
cd ../cts_wm       && ./run_cts_wm.sh      # 4_cts.odb   -> 4_cts_wm.odb
cd ../routing_wm   && ./run.sh             # tags nets, then detail-routes
```

Each stage writes its watermarked ODB and a ground-truth CSV under
`experiments/results/<platform>/<design>/<variant>/`. The CSV is the
verification commitment. Keep it.

`DESIGN`, `PLATFORM` and `WM_FLOW_VARIANT` are required by every script and have
no defaults. A run either targets the intended design or fails immediately.

## Verifying a suspect layout

```bash
cd "$ORFS_FLOW_HOME"/watermarking/placement_wm
WM_VERIFY_INPUT=/path/to/suspect.odb \
WM_CELL_LIST=/path/to/wm_place_order_embed.csv \
  ./place_wm.sh verify        # exit 0 = all claims hold, 2 = mismatch
```

The `cts_wm/cts_wm.sh verify` command does the same for the CTS stage. For
routing, dump the per-net statistic and run the test. See
[`routing_wm/README.md`](routing_wm/README.md#verification).

## Certificate and ownership verification

Embedding records its accepted claims in plaintext CSVs. The certificate step
additionally seals them into an encrypted, authenticated file bound to a
timestamped key commitment. Ownership can then be checked without the claims
being public, and a claimed key cannot be chosen after seeing the suspect
layout.

```bash
./certificate/cert.sh certify --results-dir <results> --stages placement,cts,routing
./certificate/cert.sh verify  --cert <results>/wm_cert.bin \
                              --commit <results>/wm_commit.json \
                              --master-seed-hex gen_key/out/<design>/master_seed.hex \
                              --suspect-odb <suspect>/5_route.odb
```

The certificate is also the only on-disk record of the effective watermark
parameters, including the routing fraction `f` that a verifier needs to rebuild
`WM_R` from the key. The plaintext CSVs are untouched, and every verifier
behaves as before unless `WM_CERT_FILE` is set. See
[`certificate/README.md`](certificate/README.md).

## Reproducing the paper

[`experiments/README.md`](experiments/README.md) is the full runbook for PPA,
capacity, survival, wrong-key, sensitivity and attack results.
[`experiments/baselines/README.md`](experiments/baselines/README.md) covers the
prior-work comparisons.

## Limitations

- The routing stage requires the OpenROAD fork described above.
- ASAP7 produces no wrong-way wirelength, so the routing statistic is undefined
  on that platform and the harness skips it.
- No results ship with this tree. Every table and figure is regenerated from
  your own reference ORFS runs.

## License

BSD 3-Clause License, matching OpenROAD-flow-scripts. Every source file carries
an SPDX header.
