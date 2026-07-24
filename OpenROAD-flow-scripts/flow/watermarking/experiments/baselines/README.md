# Baseline watermarking methods

Prior physical-design watermarking methods re-implemented in the same ORFS flow,
used for the comparison in the paper. Each baseline selects its watermark objects
with a keyed PRF (matching the PDMarks threat model) but uses a different carrier.

| Directory | Method | Carrier (one binary claim per object) |
|---|---|---|
| `kahng/` | Row-parity | row-index parity of a selected cell |
| `buffer_insertion/` | Buffer-insertion | parity of the buffer count on a selected net |
| `cell_scattering/` | Cell-scattering | column parity of a selected cell |
| `icmarks/` | ICMarks | region-side bit of a cell constrained to a region |
| `automarks/` | AutoMarks | as ICMarks, with a GNN-accelerated region search |

`attacks/` holds the blind and targeted attack drivers for these baselines.

## Comparison of PD watermarking methods

Reproduced from the paper (Table: *Comparison of PD watermarking methods*).
"Kerckhoffs" means security rests on the key alone, with the algorithm public.

| Work | Placement | CTS | Routing | Kerckhoffs | Open-source |
|---|:---:|:---:|:---:|:---:|:---:|
| Row-parity [Kahng et al., DAC'98; TCAD'01] | ✓ | ✗ | ✓ | ✗ | ✗ |
| Buffer-insertion [Sun et al., ISQED'06] | ✓ | ✗ | ✗ | ✗ | ✗ |
| Cell-scattering [Cai et al., ASICON'07] | ✓ | ✗ | ✗ | ✗ | ✗ |
| ICMarks [Zhang et al., TCAD'25] | ✓ | ✗ | ✗ | ✗ | ✓ |
| AutoMarks [Zhang et al., MLCAD'24; TODAES] | ✓ | ✗ | ✗ | ✗ | ✓ |
| **PDMarks (ours)** | ✓ | ✓ | ✓ | ✓ | ✓ |

## Running

```bash
# All baselines on the active benchmark set
bash ../run_phase1_baselines.sh

# A single method
python3 kahng/embed.py  --odb <3_place.odb> --seed <seed.hex>
python3 kahng/verify.py --odb <post-DRT.odb> --embed-csv <kahng_embed.csv>
```

Each method writes `<method>_embed.csv` (one row per selected object, with its
target bit and whether the bit was committed) and, after verification,
`<method>_verify_DRT.csv`.

## Coincidence probability

`P_c` is computed from the post-DRT verify CSV with the same Bernoulli model used
for the PDMarks placement and CTS stages:

```
P_c = sum_{i=0}^{x} C(X, i) * 0.5^X
```

`X` is the number of **committed** claims — objects whose target bit was
successfully embedded and is therefore verified — and `x` the number that no
longer match after detailed routing. Objects whose bit could not be committed are
excluded from `X`, so `X` reflects each carrier's embed feasibility.
