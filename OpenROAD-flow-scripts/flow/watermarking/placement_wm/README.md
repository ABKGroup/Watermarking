# Placement watermark — keyed cell ordering

Embeds ownership evidence in the **relative x-order of same-row cell pairs** on
a post-detailed-placement ODB. Pure OpenROAD-Python; no OpenROAD source changes.
The key comes from [`../gen_key/`](../gen_key/) as `seed_placement.hex`.

## What the watermark is

**Pairs.** For two instances `A`, `B` in the same row within `D_pair` of each
other:

- observed bit = `0` if `x(A) < x(B)`, else `1` (ties resolve to `1`)
- target bit = `HMAC(seed, "bit", tile_id, sorted(name_A, name_B))[0] & 1`

The embedder swaps the two cells when the observed bit differs from the target.
Since both cells sit in the same row and swap positions with each other, the
perturbation is local and area-neutral.

**Triples** (optional, `WM_USE_GROUPS=1`). Three cells in one bucket admit six
left-to-right orders; the target index is `HMAC(..., "perm", ...) % 6`. Only
triples whose six permutations differ in local HPWL by at most
`WM_HPWL_EPS_GROUP_DBU` are eligible, so the reordering is near-free.

Ownership evidence is the extraction rate `r_P` and the Bernoulli coincidence
probability `P_c = sum_{i<=x} C(X,i) 0.5^X` over `X` committed claims with `x`
mismatches.

## How candidates are chosen

Selection is deliberately conservative — the watermark must not cost PPA:

1. **Bucket** cells by `(tile, row, master width, criticality bin)` and sort by x.
2. **Enumerate** only `(i, i+1) … (i, i+K)` per bucket (`WM_PAIR_NEIGHBOR_K`,
   default 2) instead of a full O(n²) window. `0` restores the full window.
3. **Filter cascade**, cheapest first, so rejects save later work:
   `distance -> neighbor-slack -> fanout-diff -> dense-tile gate -> HPWL delta`.
4. **Per-tile early stop** once `WM_PAIRS_PER_TILE * WM_TILE_OVERSAMPLE`
   candidates are accepted in a tile.
5. **Keyed greedy selection**: `HMAC(seed, …)` totally orders the candidates;
   pick non-overlapping ones until the per-tile quota or the touch cap
   (`WM_TILE_TOUCH_FRAC_MAX`) is hit.
6. **Capacity fallback**: if fewer than `WM_MIN_PAIRS_TOTAL` pairs survive, a
   second pass widens K, coarsens criticality bins, and relaxes the HPWL bound,
   then reselects from the merged pool. The strict pass is preserved.
7. **Post-embed STA guard**: one STA pass over all swapped cells; any swap that
   drops slack below `WM_SLACK_THRESHOLD_NS - WM_GUARD_DEGRADE_NS` (or by more
   than `WM_GUARD_DEGRADE_NS`) is reverted and marked `reverted_post_guard`.
8. **Incremental DPL** once at the end, bounded by `WM_MAX_DISP_X/Y`.

Cost control that matters in practice: an **HPWL cache** built once over the
kept cells makes `swap_delta_hpwl` pure Python arithmetic with no OpenDB walks
per candidate. Nets above `WM_HPWL_NET_FANOUT_MAX` pins are skipped as
uninformative for local swap quality. The cache is freed before DPL.

## Files

| File | Role |
|---|---|
| `watermark_common.py` | tile grid, slack, macro index, HPWL cache, enumeration |
| `watermark_embed.py` | select, swap/permute, DPL, write ODB/DEF/CSV |
| `watermark_verify.py` | verify one ODB against the embed CSV |
| `watermark_verify_stages.py` | verify across a `label:odb` stage list |
| `place_wm.sh` | thin wrapper: `embed` / `verify` / `verify_stages` / `all` |
| `run_place_wm.sh` | end-to-end example: key bundle → embed → verify |
| `run_ppa.sh` | continue the ORFS back-end from the watermarked placement |
| `run_verify_stages.sh` | verify at post-CTS / GRT / DRT / final |

The keyed primitives live in [`../wm_prf.py`](../wm_prf.py), shared with the CTS
and routing stages.

## Usage

```bash
export DESIGN=jpeg PLATFORM=nangate45 WM_FLOW_VARIANT=base

./run_place_wm.sh        # embed + self-verify
./run_ppa.sh             # optional: CTS + route + finish from the marked ODB
./run_verify_stages.sh   # optional: confirm survival at each later stage
```

To drive the embedder directly, set the inputs and call the wrapper:

```bash
WM_SEED_HEX=../gen_key/out/jpeg/seed_placement.hex \
WM_INPUT=.../3_place.odb \
WM_OUTPUT_ODB=.../3_place_order_wm.odb \
WM_OUTPUT_CELL_LIST=.../wm_place_order_embed.csv \
  ./place_wm.sh embed
```

## Parameters

`watermark_embed.py`'s argparse defaults are the **single source of truth**; the
wrapper scripts set none of them. Every knob is also a `--flag`.

**Required**

| Var | Meaning |
|---|---|
| `WM_INPUT` | post-DP `.odb` |
| `WM_OUTPUT_ODB` | watermarked `.odb` to write |
| `WM_SEED_HEX` | `seed_placement.hex` |

**Outputs**

| Var | Meaning | Default |
|---|---|---|
| `WM_OUTPUT_CELL_LIST` | embed CSV (the verification commitment) | unset |
| `WM_OUTPUT_DEF` | optional DEF | unset |

**Selection**

| Var | Meaning | Default |
|---|---|---|
| `WM_GRID_NX`, `WM_GRID_NY` | tile grid | 8 × 8 |
| `WM_PAIR_DIST_UM` | max horizontal separation for a pair | 1 |
| `WM_PAIRS_PER_TILE` | pair quota per tile | 4 |
| `WM_GROUPS_PER_TILE` | triple quota per tile | 2 |
| `WM_USE_GROUPS` | `1` enables triples | 0 |
| `WM_PAIR_NEIGHBOR_K` | bounded K-neighbor enumeration (`0` = full window) | 2 |
| `WM_TILE_OVERSAMPLE` | per-tile early-stop multiplier | 4 |
| `WM_TILE_TOUCH_FRAC_MAX` | max fraction of a tile's cells perturbed | 0.05 |
| `WM_TILE_TOUCH_FLOOR_PAIRS` | min pairs a tile may always take | 4 |
| `WM_TILE_DENSITY_MAX` | skip tiles denser than this | 1.2 |
| `WM_TILE_DISP_CAP_UM` | cumulative \|dx\| budget per tile | 200 |
| `WM_BLOCKAGE_MARGIN_SITES` | macro/obstruction keep-out | 4 |

**Quality gates**

| Var | Meaning | Default |
|---|---|---|
| `WM_HPWL_EPS_PAIR_DBU` | max \|ΔHPWL\| for a pair swap | 100 |
| `WM_HPWL_EPS_GROUP_DBU` | max permutation spread for a triple | 100 |
| `WM_FANOUT_MAX` | skip cells whose own fanout exceeds this | 16 |
| `WM_FANOUT_DIFF_MAX` | skip pairs whose fanouts differ by more | 4 |
| `WM_SLACK_THRESHOLD_NS` | worst-pin slack lower bound | 0.20 |
| `WM_NEIGHBOR_SLACK_MARGIN_NS` | extra slack required of net-mates | 0.10 |
| `WM_CRIT_BIN_NS` | slack quantization for bucketing | 0.05 |
| `WM_HPWL_CACHE` | `1` uses the deduped HPWL cache | 1 |
| `WM_HPWL_NET_FANOUT_MAX` | ignore nets above this pin count | 64 |

**Capacity fallback**

| Var | Meaning | Default |
|---|---|---|
| `WM_MIN_PAIRS_TOTAL` | trigger the fallback below this pair count | 64 |
| `WM_PAIR_NEIGHBOR_K_RELAXED` | fallback K | 8 |
| `WM_HPWL_EPS_PAIR_RELAXED_DBU` | fallback HPWL bound | 200 |
| `WM_CRIT_BIN_RELAXED_NS` | fallback criticality bin | 0.20 |

**Post-guard and legalization**

| Var | Meaning | Default |
|---|---|---|
| `WM_POST_GUARD` | `1` runs STA after the batch and reverts bad swaps | 1 |
| `WM_POST_GUARD_FINAL_CHECK` | `1` re-runs STA after reverting (diagnostic) | 1 |
| `WM_GUARD_DEGRADE_NS` | slack-drop tolerance before reverting | 0.02 |
| `WM_MAX_DISP_X`, `WM_MAX_DISP_Y` | incremental DPL bound (µm) | 5 |
| `WM_LIB_FILES`, `WM_SDC` | STA inputs | auto-discovered / optional |

**Verify**

| Var | Meaning |
|---|---|
| `WM_VERIFY_INPUT` | watermarked or suspect `.odb` |
| `WM_CELL_LIST` | embed CSV (ground truth) |
| `WM_VERIFY_CELL_LIST` | optional summary CSV to write |
| `WM_VERIFY_STAGES` | `verify_stages` only: `label:odb,label:odb,…` |
| `WM_STAGE_REPORT` | optional per-stage CSV |

## Verification

`watermark_verify.py` checks the ODB against the **embed CSV**, not against the
seed alone. Only rows whose `skipped_reason` is empty or `already_satisfied`
are checked; rows the embedder skipped or the post-guard reverted
(`balance_cap`, `hpwl_precheck`, `reverted_post_guard`, …) are excluded. The
commitment is the set of constraints the embed actually applied and kept.

Re-deriving the selection from the seed alone is deliberately not implemented —
it would mean rerunning the full candidate enumeration against the same netlist.
**Keep the embed CSV for sign-off.**

Exit codes: `0` every checked constraint holds, `2` otherwise.

## Security note

Order-based bits are invariant under **global translation** of the block — both
cells of a pair move together, so the bit is unchanged. Tampering that
**reorders** watermarked cells relative to each other is what the verifier
detects.
