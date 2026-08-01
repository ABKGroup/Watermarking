# CTS watermark — leaf-clock-buffer fanout parity

Embeds ownership evidence in the **sequential fanout parity** of selected
leaf clock buffers (LCBs) on a post-TritonCTS ODB. The key comes from
[`../gen_key/`](../gen_key/) as `seed_cts.hex`.

## What the watermark is

For a keyed pair of neighbouring LCBs `(L_A, L_B)`, the seed fixes

```
seq_fanout(target_lcb) % 2  ==  target_bit
```

where `target_bit` and which of the two LCBs is the target both come from the
seed. Parity is adjusted by **moving one boundary flip-flop** from the target
LCB to its peer — no buffers are added or removed, and the clock tree keeps its
shape. A boundary FF is one whose distance gap to the peer LCB is within
`WM_CTS_DELTA_SITES` site pitches, so the move is short.

Successful pairs are marked `setDoNotTouch` / `FIRM` (along with quasi-leaf
repair cells) so downstream routing does not undo the watermark.

Ownership evidence is `r_C` and `P_c = sum_{i<=x} C(X,i) 0.5^X`: each pair is a
fair coin under a wrong key.

## Channels

Every clock buffer is classified by what its output net drives:

- **seq** — a sequential clock pin (a flip-flop).
- **repair** — a timing-repair cell, recognised by a basename hint
  (`rebuffer`, `wire`, `hold`, `max_cap`, `max_slew`, `fanout`, `load_slew`,
  `clkload`, `clk_load`) and *not* named like a CTS buffer (`clkbuf`, …).
- **other** — anything else.

| Channel | Definition |
|---|---|
| `pure` | `seq > 0`, `repair == 0`, `other == 0` |
| `quasi_leaf` | `seq > 1`, `1 <= repair <= R_max`, `other == 0` |
| *(neither)* | not a candidate |

Candidate pairs may be pure–pure, quasi–quasi, or the cross-channel
`pure_quasi`. All three use the same `seq_fanout % 2` bit; quasi-leaf pairs
additionally enforce capacitance margin, tighter slew, setup/hold bounds, and a
**repair-signature check** — if the set of repair instances changes during a
trial the move is reverted (`repair_changed`).

Pairs are filled in priority order **pure → quasi_leaf → pure_quasi** until
`WM_CTS_NUM_PAIRS` successful embeds or the queue is exhausted. One pair, one
successful embed: both LCBs leave the pool afterwards.

## Embed algorithm

1. Read the post-CTS ODB and classify every clock buffer.
2. Build proximity pairs (centroid distance ≤ `WM_CTS_SIBLING_DIST_UM`)
   separately per channel pool.
3. Filter on Liberty headroom: `max_fanout` slack, slew margin, and (quasi)
   capacitance margin.
4. Select pairs and target bits with domain-separated RNGs
   (`cts_pure`, `cts_quasi`, `cts_pure_quasi`), honouring
   `WM_CTS_CHANNEL_BUDGET`.
5. For each pair, if parity is already correct, record it and move on;
   otherwise move the closest boundary FF from target to peer.
6. Run incremental STA after each trial — slew, capacitance, skew growth, and
   (quasi) setup/hold degradation. Reject and revert anything unsafe.
7. Mark accepted structures do-not-touch; write the watermarked ODB and the
   ground-truth CSV.

## Files

| File | Role |
|---|---|
| `cts_watermark_common.py` | classification, pairing, Liberty/timing helpers |
| `cts_watermark_embed.py` | channel embed, filters, legality checks, CSV + ODB |
| `cts_watermark_verify.py` | verify one ODB against the embed CSV |
| `cts_watermark_verify_stages.py` | verify across a `label:odb` stage list |
| `cts_wm.sh` | thin wrapper: `embed` / `verify` / `verify_stages` / `all` |
| `run_cts_wm.sh` | end-to-end example: key bundle → embed → verify |
| `run_ppa.sh` | continue the ORFS back-end (GRT + DRT) from the marked ODB |
| `run_verify_stages.sh` | verify at post-CTS / GRT / DRT / final |

The keyed primitives live in [`../wm_prf.py`](../wm_prf.py), shared with the
placement and routing stages.

## Usage

```bash
export DESIGN=jpeg PLATFORM=nangate45 WM_FLOW_VARIANT=base

./run_cts_wm.sh          # embed + self-verify
./run_ppa.sh             # optional: GRT + DRT from the watermarked CTS ODB
./run_verify_stages.sh   # optional: confirm survival at each later stage
```

Driving the embedder directly:

```bash
WM_SEED_HEX=../gen_key/out/jpeg/seed_cts.hex \
WM_CTS_INPUT=.../4_cts.odb \
WM_CTS_OUTPUT_ODB=.../4_cts_wm.odb \
WM_CTS_OUTPUT_CSV=.../wm_cts_pairs_embed.csv \
  ./cts_wm.sh embed
```

## Parameters

`cts_watermark_embed.py`'s argparse defaults are the **single source of truth**;
the wrapper scripts set none of them.

**Required**

| Var | Meaning |
|---|---|
| `WM_CTS_INPUT` | post-CTS `.odb` |
| `WM_CTS_OUTPUT_ODB` | watermarked `.odb` to write |
| `WM_CTS_OUTPUT_CSV` | ground-truth CSV (the verification commitment) |
| `WM_SEED_HEX` | `seed_cts.hex` |

**Selection**

| Var | Meaning | Default |
|---|---|---|
| `WM_CTS_NUM_PAIRS` | target number of **successful** embeds | 32 |
| `WM_CTS_SIBLING_DIST_UM` | max centroid distance for a pair (µm) | 20 |
| `WM_CTS_DELTA_SITES` | boundary-FF threshold (site pitches) | 2 |
| `WM_CTS_MAX_ATTEMPTS` | boundary-FF trials per pair | 3 |
| `WM_CTS_CHANNEL_BUDGET` | `auto` \| `pure_only` \| `quasi_only` \| `N:M` | auto |
| `WM_CTS_R_MAX` | quasi-leaf max `repair_fanout` | 2 |

**Safety margins (pure channel)**

| Var | Meaning | Default |
|---|---|---|
| `WM_CTS_FANOUT_MARGIN` | min slack against Liberty `max_fanout` | 2 |
| `WM_CTS_SLEW_HEADROOM_FRAC` | min output slew margin | 0.20 |
| `WM_CTS_SKEW_SLACK_PS` | max growth of worst \|clock skew\| vs baseline | 20 |

**Safety margins (quasi-leaf channel)**

| Var | Meaning | Default |
|---|---|---|
| `WM_CTS_QL_SLEW_HEADROOM_FRAC` | slew margin | `max(0.30, pure + 0.10)` |
| `WM_CTS_QL_CAP_HEADROOM_FRAC` | capacitance margin | 0.20 |
| `WM_CTS_QL_SETUP_SLACK_PS` | setup WNS degradation limit | 50 |
| `WM_CTS_QL_HOLD_SLACK_PS` | hold WNS degradation limit | 30 |
| `WM_CTS_QL_SKEW_SLACK_PS` | skew slack vs baseline | `WM_CTS_SKEW_SLACK_PS` |
| `WM_CTS_AVOID_HOLD_REPAIR` | `1` skips quasi-leaf with a `hold` repair hint | 1 |

**Liberty fallbacks** (used only when the value cannot be read from the library)

| Var | Meaning | Default |
|---|---|---|
| `WM_CTS_MAX_FANOUT` | fallback `max_fanout` | 32 |
| `WM_CTS_MAX_TRANSITION_NS` | fallback `max_transition` (ns) | 0.4 |
| `WM_CTS_MAX_CAP_FF` | fallback `max_capacitance` (fF) | 50 |
| `WM_LIB_FILES`, `WM_SDC`, `WM_SETRC` | STA inputs | auto-discovered |

**Verify**

| Var | Meaning |
|---|---|
| `WM_CTS_VERIFY_INPUT` | `.odb` to check |
| `WM_CELL_LIST` | embed CSV (ground truth) |
| `WM_CTS_VERIFY_CSV` | optional per-pair report |
| `WM_VERIFY_STAGES` | `verify_stages` only: `label:odb,label:odb,…` |
| `WM_STAGE_REPORT` | optional per-pair × stage CSV |

## Verification

The embed CSV carries `channel`, `target_lcb`, `target_bit`, `final_bit`, the
seq/repair fanout counts, and `skipped_reason`. Verification recomputes
`seq_fanout(target_lcb) % 2` on the ODB under test and compares it to
`target_bit`; quasi-leaf pairs additionally fail if the repair signature was
tampered with.

A CTS re-run renames buffers, so the **embed CSV** — not the ODB — is the
durable ground truth on later stages. Keep it for sign-off.

Exit codes: `0` every pair matches, `2` otherwise.

## Survival

GRT and DRT generally preserve clock sink wiring, and the do-not-touch marks on
watermarked LCBs and their repair cells reduce disruption further. Use
`run_verify_stages.sh` to confirm this on your own designs.
