# PDMarks experiment harness

Reproduces the evaluation in the PDMarks paper: PPA overhead, capacity,
survival, wrong-key null distributions, parameter sensitivity, and the blind and
targeted attacks. Analysis scripts write CSV and JSON; `render_tex.py` turns
those into LaTeX row fragments. Nothing here edits a paper source file.

Run every command from this directory.

---

## Contents

1. [Setup](#1-setup)
2. [Layout](#2-layout)
3. [Embedding and PPA](#3-embedding-and-ppa)
4. [Security analysis](#4-security-analysis)
5. [Attacks](#5-attacks)
6. [Baselines](#6-baselines)
7. [Aggregation and tables](#7-aggregation-and-tables)
8. [Supplementary tools](#8-supplementary-tools)

---

## 1. Setup

### Environment

```bash
export ORFS_FLOW_HOME=/path/to/OpenROAD-flow-scripts/flow
export OPENROAD_EXE=/path/to/openroad            # built with the PDMarks routing commands
export SINGULARITY_SIF=/path/to/image.sif        # OPTIONAL; unset = run natively
pip install -r ../requirements.txt               # numpy, scikit-learn, matplotlib
```

Path and container resolution lives in [`../wm_env.sh`](../wm_env.sh) (shell)
and [`lib/orexec.py`](lib/orexec.py) (Python). No script hard-codes a machine.

### Reference runs

Every bench needs a completed un-watermarked ORFS run (`6_report.json` on disk)
before anything else. Everything downstream is measured against it.

```bash
DESIGN=jpeg PLATFORM=nangate45 WM_FLOW_VARIANT=base bash drivers/run_ref.sh
```

The active bench matrix is `bench_matrix.py` — 10 cells across NanGate45 and
ASAP7. Adding a design means appending one `Bench(...)` row and running
`run_ref.sh` once for it.

### `DESIGN` vs `DESIGN_NICKNAME`

ORFS lets a design's `config.mk` override the name used for **on-disk paths**
while `DESIGN_NAME` still drives config and key identity. The harness handles
this everywhere; you always pass `DESIGN=<full_name>` and let
`drivers/_common.sh` discover the nickname.

| Path kind | Uses |
|---|---|
| `designs/<plat>/<DESIGN>/config.mk` | `DESIGN` |
| `gen_key/out/<DESIGN>/seed_*.hex` | `DESIGN` |
| `flow/{results,logs}/<plat>/<NICK>/` | `DESIGN_NICKNAME` |
| `experiments/{results,logs}/<plat>/<NICK>/` | `DESIGN_NICKNAME` |
| CSV/JSON `"design"` columns | `DESIGN` (logical identity) |

The only bench with a split today is `bp_multi_top` (NG45), nickname
`bp_multi`.

### Keys

The drivers call `ensure_keys` automatically. Manually:

```bash
cd "$ORFS_FLOW_HOME"/watermarking/gen_key
./gen_key.sh keygen --owner-id <id> --out-dir keys
./gen_key.sh sign --sk keys/sk.pem --pk keys/pk.pem \
    --owner-id <id> --design-id jpeg --out-dir out/jpeg
```

---

## 2. Layout

```
experiments/
├── bench_matrix.py          # the active design matrix
├── sbpy                     # shim: a Python that has sklearn/matplotlib
│
├── lib/
│   ├── orfs.py              # path resolution, 6_report.json / *.log readers
│   ├── orexec.py            # how OpenROAD is invoked (native or container)
│   ├── pc.py                # coincidence probability P_c
│   ├── route_stat.py        # q_R, T_R, and the net-level randomization test
│   ├── keys.py              # stage-seed derivation, wrong-key streams
│   ├── keyless_verify.py    # extraction rates recomputed from a seed alone
│   ├── eligibility.py       # public-rule reconstruction of eligible P/C/R sets
│   └── thresholds.py        # tau_P / tau_C / tau_all / alpha_R, ownership_pass
│
├── drivers/                 # one ORFS flow per PDMarks variant
│   ├── _common.sh           # shared env, DESIGN_NICKNAME discovery, ensure_keys
│   ├── adaptive_params.sh   # timing-adaptive parameter defaults
│   ├── run_ref.sh           # unmodified reference flow
│   ├── run_p_only.sh        # placement watermark + PPA continuation
│   ├── run_c_only.sh        # CTS watermark + PPA continuation
│   ├── run_r_only.sh        # routing watermark + PPA continuation
│   └── run_all_stage.sh     # chained P -> C -> R
│
├── baselines/               # prior-work comparisons -- see baselines/README.md
├── sensitivity/             # 1-D parameter sweeps
├── wrong_key/               # wrong-key null distribution
├── attacks/
│   ├── blind/               # paper §7.1
│   ├── targeted/            # paper §7.2
│   └── ppa/                 # ΔPPA of the attacked layouts
├── tools/                   # per-net routing dumps, ODB utilities
│
├── phase1_ppa.py            # Δ-PPA + P_c per variant
├── phase1_capacity.py       # eligible / selected counts per stage
├── phase1_survival.py       # extraction rate at 4 PD checkpoints
├── baseline_survival.py     # same, for the baselines
├── aggregate.py             # raw JSON -> per-phase CSV
└── render_tex.py            # CSV -> LaTeX row fragments
```

---

## 3. Embedding and PPA

### Run the watermarked flows

Each driver embeds and runs ORFS to completion.

```bash
DESIGN=jpeg PLATFORM=nangate45 WM_FLOW_VARIANT=base bash drivers/run_p_only.sh
DESIGN=jpeg PLATFORM=nangate45 WM_FLOW_VARIANT=base bash drivers/run_c_only.sh
DESIGN=jpeg PLATFORM=nangate45 WM_FLOW_VARIANT=base bash drivers/run_r_only.sh
DESIGN=jpeg PLATFORM=nangate45 WM_FLOW_VARIANT=base bash drivers/run_all_stage.sh
```

The whole matrix:

```bash
while read -r plat dsgn var; do
  [ -z "$plat" ] && continue
  DESIGN=$dsgn PLATFORM=$plat WM_FLOW_VARIANT=$var bash drivers/run_all_stage.sh
done <<'EOF'
nangate45 aes            watermarking-test1
nangate45 jpeg           watermarking-test1
nangate45 swerv_wrapper  base
nangate45 ariane136      base_tcp3p5
nangate45 bp_multi_top   base_tcp3p2
asap7     aes            base
asap7     jpeg           base_tcp540
asap7     swerv_wrapper  base_tcp1455
asap7     ariane         base_fixed
asap7     cva6           base_tcp950
EOF
```

`run_phase1_embeds.sh` does an embed-only pass (no PPA round-trip) when you
just want capacity numbers quickly.

**Adaptive parameters.** The drivers derive placement/CTS/routing parameters
from the reference timing by default. Disable with
`PDMARKS_ADAPTIVE_PARAMS=0`, or override one knob and leave the rest adaptive:

```bash
WM_CTS_NUM_PAIRS=16 bash drivers/run_c_only.sh
```

### Analyse

```bash
python3 phase1_ppa.py          # Δ-PPA + P_c        -> results/phase1/raw/ppa_*.json
python3 phase1_capacity.py     # eligible/selected  -> results/phase1/raw/capacity_*.json
python3 phase1_survival.py     # 4 checkpoints      -> results/phase1/raw/survival_*.json
```

**Pinning a variant.** By default the analysis picks the most recently
completed run. Override per module with `WM_VARIANT_PLACEMENT_WM`,
`WM_VARIANT_CTS_WM`, `WM_VARIANT_ROUTING_WM`.

---

## 4. Security analysis

### Wrong-key null distribution

Evaluates the true key and N deterministic wrong keys against the same layout,
so the false-positive rate is measured rather than assumed.

```bash
./sbpy wrong_key/run_wrong_key.py -n 1000
./sbpy wrong_key/plot_wrong_key.py
python3 aggregate.py --what wrong_key
```

The true key gets the full B-trial randomization test for `p_R`; wrong keys use
the analytic normal approximation (clamped at the empirical floor `1/(B+1)`),
because a full randomization per key across a 1000-key sweep is infeasible.
Tune with `--randomization-B`.

### Parameter sensitivity

1-D sweeps over `D_pair`, `theta_HPWL`, `delta_guard` (placement),
`sibling_um` (CTS), and `f`, `lambda_wm` (routing).

```bash
bash sensitivity/run_sensitivity.sh --list       # show the knob labels
bash sensitivity/run_sensitivity.sh              # all knobs (long)
SENS_KNOBS="D_pair,f" bash sensitivity/run_sensitivity.sh   # a subset

python3 sensitivity/verify_sweep.py
python3 sensitivity/aggregate_sensitivity.py
```

`SENS_KNOBS` is how you fan the sweep across machines. Routing knobs are
skipped on ASAP7 (no wrong-way wirelength); force them with
`SENS_ROUTE_ASAP7=1`, or drop routing entirely with `SENS_ROUTE=0`.

---

## 5. Attacks

Both attackers are given exactly what the paper allows: the leaked layout and
the public algorithm, never the key. `lib/eligibility.py` reconstructs the
key-independent eligible set the same way the embedder enumerates it, so the
attacker's search space matches the defender's by construction.

### Blind (§7.1)

Perturbs a random fraction `q_s` of eligible objects.

```bash
./sbpy attacks/blind/run_blind_attack.py
```

Sweeps 4 stages × 5 values of `q_s`. Placement and CTS run in minutes; routing
re-runs `detail_route` and takes hours. ASAP7 routing is skipped by default
(`--no-routing-platforms ""` to force it).

### Targeted (§7.2)

Trains a classifier on observable features and perturbs the top-K objects by
predicted P(watermarked).

```bash
./sbpy attacks/targeted/run_targeted_attack.py
```

Reports AUC, precision@recall and recall@top-K per stage. Routing top-K
triggers a real re-route via `routing_wm/run_attack_route.sh`.

### ΔPPA of attacked layouts

Placement and CTS attacks leave an ODB that still needs the back-end run;
routing attacks self-complete.

```bash
python3 attacks/ppa/run_attack_ppa.py --dry-run    # check the work list first
./sbpy attacks/ppa/run_attack_ppa.py --skip-done
python3 attacks/ppa/aggregate_attack_ppa.py
```

---

## 6. Baselines

See [`baselines/README.md`](baselines/README.md) for the methods, their carriers
and the equal-capacity argument.

```bash
nohup bash run_baselines_all.sh > logs/baselines_all.log 2>&1 &
python3 baseline_survival.py                          # all methods
python3 baseline_survival.py --methods buffer_insertion
./sbpy baselines/attacks/run_baseline_attacks.py      # blind + targeted
python3 baselines/attacks/aggregate_baseline_attacks.py
```

---

## 7. Aggregation and tables

```bash
python3 aggregate.py                 # everything
python3 aggregate.py --what ppa      # one section; choices are:
#   all | ref | capacity | ppa | survival | wrong_key | blind | targeted
python3 render_tex.py
cat results/tables_index.md          # where each fragment landed
```

### Outputs

| File | Contents |
|---|---|
| `results/phase1/summary_ref.csv` | reference PPA for every bench |
| `results/phase1/ppa_{nangate45,asap7}.csv` | Δ-PPA per platform |
| `results/phase1/capacity.csv` | eligible / selected counts |
| `results/phase1/survival.csv` | extraction rate at 4 checkpoints |
| `results/phase1/baseline_survival.csv` | same, per baseline |
| `results/phase2/wrong_key.csv` | wrong-key summary + false-positive rates |
| `results/phase2/sensitivity.csv` | sensitivity sweep |
| `results/phase3/blind.csv` | blind attack extraction rates |
| `results/phase3/blind_ppa.csv` | blind attack Δ-PPA (vs ref and vs watermarked) |
| `results/phase3/targeted.csv` | targeted attack summary |

Raw per-cell JSON lives under `results/phase{1,2,3}/raw/`.

### Evidence columns

| Column | Meaning |
|---|---|
| `r_P` | placement extraction rate, `1 - x_P/X_P` |
| `r_C` | CTS extraction rate, `1 - x_C/X_C` |
| `T_R` | routing statistic, mean `q_R` difference (more negative = stronger) |
| `p_R` | net-level randomization p-value for `T_R` |
| `r_R` | `1{p_R <= alpha_R}` |
| `r_all` | mean of the available per-stage rates |
| `P_c` | coincidence probability under a wrong key |

**ASAP7 routing rows are blank by design.** Its strict-direction router emits
zero wrong-way wirelength, so `q_R` is identically zero and `T_R` / `p_R` are
structurally undefined — not a failure, and not a number worth reporting.

---

## 8. Supplementary tools

Not part of the main pipeline; each backs a specific claim in the paper.

| Script | Purpose |
|---|---|
| `tools/dump_route_qr.{py,sh}` | per-net `(ww_len, tot_len)` + geometry from a routed ODB |
| `tools/unlock_atk_placement_odb.py` | clear do-not-touch marks on an attacked ODB |
| `run_removal_ppa_check.sh` | surgically reroute only the watermark nets, then re-measure `T_R` and PPA |
| `run_full_reroute_check.sh` | same, rerouting every net — the upper bound on removal effort |
| `run_reroute_timing.sh` | surgical vs full reroute wall-clock, matched thread count |
| `run_surgical_reroute_qs.sh` | surgical reroute at a given attack fraction |
| `run_postroute_allstage_qs.sh` | post-route extraction + PPA for an all-stage attack |
| `blind_postdrt_extract.py` | re-extract `r_P` / `r_C` from post-DRT ODBs |
| `attacks/targeted/classify_unsupervised.py` | unsupervised ranking, as an attacker-capability check |
| `attacks/targeted/filter_cts_feasibility.py` | restrict CTS candidates to feasible moves |
| `attacks/blind/plot_blind_qstar.py` | `q*` (fraction needed to defeat ownership) figure |
| `attacks/blind/plot_ppa_wm_vs_attack.py` | watermark vs attack PPA cost figure |

## Notes on reproducibility

- No results ship with this tree — `results/`, `logs/` and `plots/` are
  gitignored. Every table and figure below is regenerated from scratch by the
  commands above, starting from your own reference ORFS runs.
- Watermark parameter defaults live in each embedder's argparse and nowhere
  else. The wrapper scripts deliberately set none, so what you read in
  `placement_wm/README.md` and `cts_wm/README.md` is what runs.
- `sbpy` picks an interpreter that has scikit-learn and matplotlib, falling
  back to `SINGULARITY_SIF` when one is configured. Use plain `python3` for
  scripts that need no ML dependencies.
