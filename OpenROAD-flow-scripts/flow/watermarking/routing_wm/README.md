# Routing watermark — keyed wrong-way bias

Embeds ownership evidence in the **routing direction statistics** of a keyed
subset of signal nets. Unlike the placement and CTS stages, this one is not a
per-object bit: it is a *population-level* bias that the detailed router
produces, and it is verified with a statistical test rather than an exact match.

The key comes from [`../gen_key/`](../gen_key/) as `seed_routing.hex`.

## Requirements

This stage needs an OpenROAD build that provides four extra Tcl commands:

| Command | Role |
|---|---|
| `set_routing_watermark -key_hex <hex> -fraction <f>` | tag the keyed net subset |
| `set_routing_watermark_strength <lambda>` | wrong-way cost multiplier in DRT |
| `report_routing_watermark -p <p>` | post-route summary |
| `clear_routing_watermark` | drop all tags |

> **These commands are not in upstream OpenROAD.** They live in `src/wmk/` on
> the `watermarking` branch of
> <https://github.com/ytliu8464/OpenROAD.git>, which is what the
> `tools/OpenROAD` submodule points at. Placement and CTS watermarking do
> **not** need them and run on a stock OpenROAD build.

```bash
# From the repository root: fetch the fork and build it.
git submodule update --init --recursive OpenROAD-flow-scripts/tools/OpenROAD
cd OpenROAD-flow-scripts/tools/OpenROAD && ./etc/Build.sh
export OPENROAD_EXE=$PWD/build/src/openroad
```

`git submodule update --init` checks out the **pinned commit**
(`0d9d73ffba0228f1a7263953fb9b41de800ba301`), which is the revision this tree
was developed and tested against. To follow the branch tip instead:

```bash
git submodule update --remote OpenROAD-flow-scripts/tools/OpenROAD
```

Confirm the commands are present before running this stage:

```bash
echo 'puts [info commands set_routing_watermark]' | "$OPENROAD_EXE" -no_init
# prints "set_routing_watermark" on a PDMarks build, an empty line on a stock one
```

## What the watermark is

**Selection.** Net `n` is watermarked iff

```
HMAC-SHA256(seed_routing, b"net\0" + n)[0:4]  /  2^32   <   f
```

read as a little-endian uint32. `f` is `WATERMARK_FRACTION`. This is the same
rule the C++ side applies, mirrored in Python by
`experiments/lib/keyless_verify.routing_wm_set`.

**Carrier.** During detailed routing, tagged nets pay a reduced penalty for
routing in the non-preferred direction of a layer, controlled by
`set_routing_watermark_strength`. The observable per-net statistic is the
wrong-way wirelength fraction

```
q_R(n) = l_ww(n) / l_tot(n)
```

computed on canonicalized geometry (overlapping collinear wire intervals merged,
vias excluded), so it does not depend on how the router happened to split route
records.

**Evidence.** The statistic is the difference in mean `q_R` between the
watermarked set and the rest of the eligible set,

```
T_R = mean_{n in WM_R} q_R(n)  -  mean_{n in E_R \ WM_R} q_R(n)
```

More negative `T_R` means stronger evidence. Its significance comes from a
**net-level randomization test**: draw `B` uniform k-subsets of `E_R`
(`k = |WM_R|`) from a stream seeded by the public design id, and report

```
p_R = (1 + #{ b : T_R^(b) <= T_R }) / (B + 1)
```

The null depends only on `k` and the fixed `q_R` vector, so wrong-key trials at
the same `k` reuse one null table. The smallest reportable `p_R` is `1/(B+1)`;
when the watermarked nets carry zero wrong-way wirelength, `exact_tail_log10`
gives the exact combinatorial tail instead of the Monte-Carlo floor.

**Platform caveat.** ASAP7's strict-direction router produces no wrong-way
wirelength at all, so `q_R` is identically zero and `T_R` / `p_R` are
structurally undefined. The harness skips the routing channel on ASAP7 by
default.

## Files

| File | Role |
|---|---|
| `run.sh` | embed the watermark and run detail_route + finish |
| `pre_route_watermark.tcl` | pre-GRT hook: tag nets, set strength, dump `watermark_nets.txt` |
| `post_route_watermark.tcl` | post-DRT hook: `report_routing_watermark` |
| `run_attack_route.sh` | attack driver (paper §7.1) |
| `attack_route_pre.tcl` | pre-DRT hook: tag normally, then clear tags on the attacker's net list |
| `reroute_experiment.tcl` | surgical vs full reroute, for removal / timing studies |
| `surgical_reroute.tcl` | reroute only the watermark nets on a routed ODB |

The keyed primitives live in [`../wm_prf.py`](../wm_prf.py), shared with the
placement and CTS stages.

## Usage

```bash
export DESIGN=jpeg PLATFORM=nangate45 WM_FLOW_VARIANT=base
./run.sh
```

`run.sh` generates the key bundle on demand, exports the two ORFS hook
variables, and runs the `wm_route_wrong_way` make target, which is
`copy_inputs_v2 route finish` starting from the reference `4_cts.odb`.

| Var | Meaning | Default |
|---|---|---|
| `DESIGN`, `PLATFORM`, `WM_FLOW_VARIANT` | identify the reference run | *required* |
| `DESIGN_NICKNAME` | on-disk ORFS name | `DESIGN` |
| `FLOW_VARIANT` | output variant | `pdmarks-r-only` |
| `WATERMARK_FRACTION` | `f`, fraction of signal nets selected | 0.02 |
| `WATERMARK_STRENGTH` | `lambda_wm`, wrong-way cost multiplier | 100.0 |
| `WATERMARK_P` | cutoff passed to `report_routing_watermark` | 0.4 |
| `CTS_ODB` | explicit post-CTS ODB to start from | derived from the reference run |
| `OWNER_ID` | identity recorded in the key bundle | `pdmarks-owner` |

Outputs land in `experiments/results/<platform>/<design>/<FLOW_VARIANT>/`,
including `watermark_nets.txt` — the committed list of tagged nets.

## Verification

Verification is a two-step process: dump the per-net statistic from the routed
ODB, then run the randomization test against the keyed net set.

```bash
cd ../experiments

# 1. Per-net (ww_len, tot_len) from the routed ODB.
WM_ODB=/path/to/5_route.odb \
WM_QR_CSV=/tmp/route_qr.csv \
  bash tools/dump_route_qr.sh

# 2. T_R / p_R against the keyed net set.
python3 - <<'EOF'
from pathlib import Path
from lib.route_stat import per_net_qr, read_watermark_nets, route_stat_from_qr
counts = per_net_qr(Path("/tmp/route_qr.csv"))
wm     = read_watermark_nets(Path(".../watermark_nets.txt"))
st = route_stat_from_qr(counts, wm, design_id="jpeg")
print(f"T_R={st.T_R:.6f}  p_R={st.p_R:.3e}  k={st.k}  |E_R|={st.n_eligible}")
EOF
```

`watermark_nets.txt` is a convenience record. A verifier holding the key does
not need it: `lib.keyless_verify.routing_wm_set(seed, net_names, fraction)`
reconstructs `WM_R` from the seed alone, which is what makes this stage
key-recoverable rather than CSV-dependent.

## Attack driver

`run_attack_route.sh` reproduces the paper's §7.1 routing attack: tag every net
normally, then clear the `watermark` property on the attacker's chosen subset so
detailed routing lays those nets out without the bias.

```bash
DESIGN=jpeg PLATFORM=nangate45 WM_FLOW_VARIANT=base \
FLOW_VARIANT=atk-r-jpeg-qs0.50 \
WM_NETS_ATTACK=/path/to/attack_nets.txt \
  ./run_attack_route.sh
```

Because OpenROAD has no per-net rip-up primitive, this re-runs `detail_route`
over the whole design; `reroute_experiment.tcl` exists to measure how much
cheaper a *surgical* reroute of only the watermark nets would be
(`MODE=surgical` vs `MODE=full`).
