# Prior-Work Baselines

Prior physical-design watermarking methods, re-implemented in the same ORFS flow
so that the comparison in the paper is like for like. Each baseline selects its
watermark objects with a keyed PRF, matching the PDMarks threat model, but uses a
different carrier.

| Directory | Method | Carrier, one binary claim per object | Source ODB |
| ----- | ----- | ----- | ----- |
| [`row_parity/`](row_parity/) | Row-parity [Kahng et al., DAC'98; TCAD'01] | Row-index parity of a selected cell. | `3_place.odb` |
| [`buffer_insertion/`](buffer_insertion/) | Buffer-insertion [Sun et al., ISQED'06] | Parity of the buffer count on a selected net. | `4_cts.odb` |
| [`icmarks/`](icmarks/) | ICMarks [Zhang et al., TCAD'25] | Region-side bit of a cell constrained to a region. | `3_place.odb` |

Each method has `embed.py`, `verify.py` and a `run.sh` that chains embed,
`make wm_cts_and_route`, then verify at DRT. The `attacks/` directory holds the
blind and targeted attack drivers for these baselines.

## Comparison of PD watermarking methods

Reproduced from the paper. "Kerckhoffs" means security rests on the key alone,
with the algorithm public.

| Work | Placement | CTS | Routing | Kerckhoffs | Open-source |
| ----- |:---:|:---:|:---:|:---:|:---:|
| Row-parity [Kahng et al., DAC'98; TCAD'01] | ✓ | ✗ | ✓ | ✗ | ✗ |
| Buffer-insertion [Sun et al., ISQED'06] | ✓ | ✗ | ✗ | ✗ | ✗ |
| Cell-scattering [Cai et al., ASICON'07] | ✓ | ✗ | ✗ | ✗ | ✗ |
| ICMarks [Zhang et al., TCAD'25] | ✓ | ✗ | ✗ | ✗ | ✓ |
| AutoMarks [Zhang et al., MLCAD'24] | ✓ | ✗ | ✗ | ✗ | ✓ |
| **PDMarks (ours)** | ✓ | ✓ | ✓ | ✓ | ✓ |

## Running

```bash
# from the experiments/ directory
# All methods against the 8 paper designs. This takes hours, so detach it.
nohup bash run_baselines_all.sh > logs/baselines_all.log 2>&1 &

# A subset
BASELINES="row_parity icmarks" bash run_baselines_all.sh
bash run_baselines_all.sh --only buffer_insertion
SKIP_DONE=1 bash run_baselines_all.sh          # skip designs already finished
```

A single method on one design:

```bash
DESIGN=jpeg PLATFORM=nangate45 WM_FLOW_VARIANT=base \
  bash row_parity/run.sh
```

Outputs land in
`experiments/{results,logs}/<platform>/<nickname>/baseline-<method>/`, which is
where `phase1_ppa.py` looks.

| Variable | Description | Default |
| ----- | ----- | ----- |
| `DESIGN`, `PLATFORM`, `WM_FLOW_VARIANT` | Identify the reference run. | *required* |
| `FLOW_VARIANT` | Output variant. | `baseline-<method>` |
| `BASELINE_K` | Override the number of claims K for every design. | Matched to PDMarks. |

## Equal capacity

All methods embed `K = capacity_for(...)` claims, matched to the PDMarks
placement-only accepted-pair count in `_common.py`, so capacity is held equal
across the comparison. Override this globally with `export BASELINE_K=<int>`.

## Coincidence probability

`P_c` is computed from the post-DRT verify CSV with the same Bernoulli model
used for the PDMarks placement and CTS stages.

```
P_c = sum_{i=0}^{x} C(X, i) * 0.5^X
```

`X` is the number of committed claims, that is objects whose target bit was
successfully embedded and is therefore verifiable. `x` is the number that no
longer match after detailed routing. Objects whose bit could not be committed are
excluded from `X`, so `X` reflects each carrier's embed feasibility rather than
flattering methods that silently drop claims.

Each method writes `<method>_embed.csv`, holding one row per selected object with
its target bit and whether the bit was committed, and after verification
`<method>_verify_DRT.csv`.

## Full-flow survival

`../baseline_survival.py` measures each method's extraction rate
`r = accepted / K` at the four PD checkpoints. It runs each method's own
`verify.py` read-only on the checkpoint ODBs that the baseline flow already left
on disk, so no flow is re-run. See the
[experiments runbook](../README.md#6-baselines) for how to invoke it.

## Limitations

- The paper's comparison table also lists Cell-scattering [Cai et al.,
  ASICON'07] and AutoMarks [Zhang et al., MLCAD'24]. Neither is in this tree.
  AutoMarks' GNN region search and Cell-scattering's original formulation both
  depend on DREAMPlace, which this harness does not carry, so only the three
  methods above are reproducible here.
- ICMarks is a post-detailed-placement re-implementation. The original uses a
  DREAMPlace-driven region search, while this version selects a low-cost region
  and applies ±1-site shifts to `K` keyed cells inside it. See the docstring in
  `icmarks/embed.py` for the faithfulness notes.

## License

BSD 3-Clause License. See the [LICENSE](../../../../LICENSE_BUILD_RUN_SCRIPTS) file.
