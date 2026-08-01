#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Wrong-key null-distribution experiment (Sec. wrong-key / tab:wrong-key).

For each active bench's all-stage layout we:

1. Read the routed ODB once to get route_qr.csv (cached if present).
2. Read the true 32-byte seeds for P, C, R from gen_key/out/<design>/.
3. Compute the TRUE evidence (r_P, r_C, T_R, p_R) and r_all.
4. Generate N (default 1000) deterministic 32-byte wrong master keys; for
   each, derive (seed_P', seed_C', seed_R') via SHA256 chaining and:
   - r_P' from placement_extraction_rate using the embed CSV but the wrong
     seed (target bits/perms recomputed)
   - r_C' from cts_extraction_rate likewise
   - T_R', p_R' from a reconstructed WM_R' using seed_R'
5. Empirical P_c is the fraction of wrong-key trials whose r_all' >= true
   r_all (i.e., "would also have passed").  We also save the full
   distribution for the figure.

Outputs:
- results/phase2/raw/wrong_key_<plat>_<design>.json (summary)
- results/phase2/raw/wrong_key_<plat>_<design>_dist.csv (1000-row distribution)
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import hmac
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
from bench_matrix import ACTIVE_BENCHES
from lib.keyless_verify import placement_extraction_rate, cts_extraction_rate, \
    routing_wm_set
from lib.keys import derive_stage_seeds, wrong_key_stream, load_seed_hex
from lib.orfs import (
    FLOW_HOME, flow_results, experiment_results,
    wm_module_results, find_latest_wm_variant,
)
from lib.pc import pc_stage, pc_total
from lib.route_stat import (
    per_net_qr, build_qr_vector, observed_T, design_seed,
    randomization_pvalue, randomization_pvalue_normal,
)


def true_seeds(design):
    """Load the true (seed_P, seed_C, seed_R) for a design."""
    base = FLOW_HOME / "watermarking" / "gen_key" / "out" / design
    return (
        load_seed_hex(base / "seed_placement.hex"),
        load_seed_hex(base / "seed_cts.hex"),
        load_seed_hex(base / "seed_routing.hex"),
    )


def eval_one_key(seed_P, seed_C, seed_R, *,
                 embed_p_csv, observe_p_csv,
                 embed_c_csv, observe_c_csv,
                 routing_counts, fraction, alpha_R=0.05,
                 qr_ctx=None, design_id="", exact_routing=False, B=100_000):
    """Return (r_P, r_C, T_R, p_R, r_R, pc_all, r_all) for a given key triple.

    Per paper Eq. eq:routing_extraction:    r_R = 1{p_R <= alpha_R}
    Per paper Eq. eq:combined_extraction:   r_all = mean(r_P, r_C, r_R)
        over the channels actually available.  Channels with no embedded
        constraints (X==0) or no routing counts (ASAP7) contribute nothing,
        so r_all averages only the stages we can measure.

    Routing p-value: ``exact_routing=True`` runs the full B-trial randomization
    test (used for the true key); otherwise the analytic normal approximation
    is used, clamped at the empirical floor 1/(B+1).  A full randomization per
    wrong key would be infeasible across a 1000+ key sweep.

    ``qr_ctx`` is the key-independent (names, q) pair from ``_qr_context``; the
    q vector never depends on the key, only the selection mask does.
    """
    pcs = []
    if embed_p_csv.exists() and observe_p_csv.exists():
        X, x = placement_extraction_rate(embed_p_csv, observe_p_csv, seed_P)
        r_P = (1 - x / X) if X > 0 else None
        if X > 0:
            pcs.append(pc_stage(X, x, 0.5))
    else:
        r_P = None
    if embed_c_csv.exists() and observe_c_csv.exists():
        X, x = cts_extraction_rate(embed_c_csv, observe_c_csv, seed_C)
        r_C = (1 - x / X) if X > 0 else None
        if X > 0:
            pcs.append(pc_stage(X, x, 0.5))
    else:
        r_C = None
    T_R = p_R = r_R = None
    if routing_counts and qr_ctx is not None:
        names, q = qr_ctx
        wm = routing_wm_set(seed_R, routing_counts.keys(), fraction)
        sel = np.fromiter((n in wm for n in names), dtype=bool, count=len(names))
        k = int(sel.sum())
        if 0 < k < q.size:
            T_R = observed_T(q, sel)
            if exact_routing:
                p_R = randomization_pvalue(q, design_seed(design_id), k, T_R, B=B)
            else:
                p_R = max(randomization_pvalue_normal(q, k, T_R), 1.0 / (B + 1))
            r_R = 1.0 if p_R <= alpha_R else 0.0
            pcs.append(p_R)
    pc_all = pc_total(*pcs) if pcs else None
    # Average of available stage extraction rates (paper Eq. eq:combined_extraction).
    parts = [v for v in (r_P, r_C, r_R) if v is not None]
    r_all = (sum(parts) / len(parts)) if parts else None
    return r_P, r_C, T_R, p_R, r_R, pc_all, r_all


def _qr_context(counts):
    """Return the key-independent (names, q) vectors for the routing channel."""
    if not counts:
        return None
    vec = build_qr_vector(counts, set())
    if vec.n_eligible == 0:
        return None
    return vec.names, vec.q


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", "--num-keys", type=int, default=1000)
    ap.add_argument("--fraction", type=float, default=0.01)
    ap.add_argument("--alpha-R", type=float, default=0.05,
                    help="Routing-stage threshold for r_R = 1{p_R <= alpha_R}.")
    ap.add_argument("--randomization-B", type=int, default=100_000,
                    help="Trials for the exact routing randomization test on "
                         "the true key; also sets the wrong-key p_R floor "
                         "1/(B+1).")
    ap.add_argument("--no-routing-platforms", default="asap7",
                    help="Comma-separated platforms for which to skip the "
                         "routing channel entirely (ASAP7 has no wrong-way "
                         "wirelength, so T_R is always 0).  Default: asap7")
    args = ap.parse_args()
    _no_route_plats = {p.strip() for p in args.no_routing_platforms.split(",")
                       if p.strip()}

    out_root = HERE / "results" / "phase2" / "raw"
    out_root.mkdir(parents=True, exist_ok=True)

    import os
    import subprocess

    for b in ACTIVE_BENCHES:
        # Output / printed labels keep the logical DESIGN_NAME (b.design).
        # gen_key seeds (true_seeds below) are keyed on the full DESIGN_NAME.
        # Filesystem paths use the ORFS DESIGN_NICKNAME.
        nick = b.design_nickname

        # The canonical embed location for all benches is the consolidated
        # all-stage directory under experiments/results/.  It contains both
        # placement / CTS embed CSVs (with the "_all_stage" suffix) and the
        # pre-dumped routing artifacts (watermark_nets.txt, route_qr_*.csv).
        # Fall back to the legacy flow/results/<wm_flow_variant>/ layout for
        # benches that were embedded before the consolidation.
        all_stage_dir = experiment_results(b.platform, nick, "pdmarks-all-stage")
        legacy_dir    = flow_results(b.platform, nick, b.wm_flow_variant)

        embed_dir: Path
        embed_p:   Path
        embed_c:   Path
        rc_csv:    Path | None = None

        if (all_stage_dir / "wm_place_order_embed_all_stage.csv").exists() \
                or (all_stage_dir / "wm_cts_pairs_embed_all_stage.csv").exists():
            embed_dir = all_stage_dir
            embed_p   = all_stage_dir / "wm_place_order_embed_all_stage.csv"
            embed_c   = all_stage_dir / "wm_cts_pairs_embed_all_stage.csv"
            # The all-stage flow dumps route_qr as part of its finishing step.
            for cand in ("route_qr_5_route.csv", "route_qr.csv"):
                if (all_stage_dir / cand).exists():
                    rc_csv = all_stage_dir / cand
                    break
        elif legacy_dir.exists():
            embed_dir = legacy_dir
            embed_p   = legacy_dir / "wm_place_order_embed_v2.csv"
            embed_c   = legacy_dir / "wm_cts_pairs_embed.csv"
        else:
            print(f"[wrong_key] skip {b.platform}/{b.design}: no embed dir "
                  f"(tried {all_stage_dir} and {legacy_dir})")
            continue

        # observed_csv is no longer consulted by keyless_verify (it reads
        # observation directly from the embed CSV's target_bit / final_bit
        # columns), but the call sites still accept the argument; pass the
        # embed CSV so the path is valid.
        observe_p = embed_p
        observe_c = embed_c

        # Fallback for routing artifacts: if the all-stage dir didn't have one
        # (or we're on the legacy path), look in the routing_wm module results
        # dir and dump it from the routed ODB on demand.
        if rc_csv is None or not rc_csv.exists():
            route_var = find_latest_wm_variant("routing_wm", b.platform, nick)
            route_dir = (
                wm_module_results("routing_wm", b.platform, nick, route_var)
                if route_var else None
            )
            if route_dir is not None:
                rc_csv = route_dir / "route_qr.csv"
                if not rc_csv.exists():
                    route_odb = route_dir / "5_route.odb"
                    if route_odb.exists():
                        subprocess.run(
                            [str(HERE / "tools" / "dump_route_qr.sh")],
                            env={**os.environ,
                                 "WM_ODB": str(route_odb),
                                 "WM_QR_CSV": str(rc_csv)},
                            check=False)
        counts = per_net_qr(rc_csv) if (rc_csv and rc_csv.exists()) else {}

        # Per-platform routing-channel veto: ASAP7's strict-direction router
        # produces zero wrong-way wirelength, so the routing statistic T_R is
        # structurally pinned to 0 and p_R to 1.  Including it would only add
        # uniform noise to pc_all and r_all.
        if b.platform in _no_route_plats:
            counts = {}
        qr_ctx = _qr_context(counts)

        # True keys + true evidence
        try:
            sp, sc, sr = true_seeds(b.design)
        except Exception as e:
            print(f"[wrong_key] {b.design}: missing seeds ({e}); skip")
            continue
        true_eval = eval_one_key(sp, sc, sr,
                                 embed_p_csv=embed_p, observe_p_csv=observe_p,
                                 embed_c_csv=embed_c, observe_c_csv=observe_c,
                                 routing_counts=counts, fraction=args.fraction,
                                 alpha_R=args.alpha_R, qr_ctx=qr_ctx,
                                 design_id=b.design, exact_routing=True,
                                 B=args.randomization_B)

        # eval_one_key returns: (r_P, r_C, T_R, p_R, r_R, pc_all, r_all)
        true_rP, true_rC, true_TR, true_pR, true_rR, true_pc, true_rall = true_eval

        # Wrong-key sweep
        slug = f"{b.platform}_{b.design}"
        dist_path = out_root / f"wrong_key_{slug}_dist.csv"
        masters = wrong_key_stream(args.num_keys, namespace=slug)
        wins_pc = 0           # # of wrong keys whose pc_all <= true pc  (legacy FPR)
        wins_rall = 0         # # of wrong keys whose r_all >= true r_all (paper FPR)
        rall_samples = []
        with open(dist_path, "w", newline="") as f:
            wr = csv.writer(f)
            wr.writerow(["idx", "r_P", "r_C", "T_R", "p_R", "r_R", "pc_all", "r_all"])
            for i, m in enumerate(masters):
                seeds = derive_stage_seeds(m)
                ev = eval_one_key(seeds["placement"], seeds["cts"], seeds["routing"],
                                  embed_p_csv=embed_p, observe_p_csv=observe_p,
                                  embed_c_csv=embed_c, observe_c_csv=observe_c,
                                  routing_counts=counts, fraction=args.fraction,
                                  alpha_R=args.alpha_R, qr_ctx=qr_ctx,
                                  design_id=b.design, exact_routing=False,
                                  B=args.randomization_B)
                rP, rC, TR, pR, rR, pc, r_all = ev
                wr.writerow([i,
                             rP    if rP    is not None else "",
                             rC    if rC    is not None else "",
                             TR    if TR    is not None else "",
                             pR    if pR    is not None else "",
                             rR    if rR    is not None else "",
                             pc    if pc    is not None else "",
                             r_all if r_all is not None else ""])
                if true_pc is not None and pc is not None and pc <= true_pc:
                    wins_pc += 1
                if true_rall is not None and r_all is not None:
                    rall_samples.append(r_all)
                    if r_all >= true_rall:
                        wins_rall += 1

        # Wrong-key r_all statistics (matches tab:wrong-key columns in the paper).
        wk_rall_mean = (sum(rall_samples) / len(rall_samples)) if rall_samples else ""
        wk_rall_max  = max(rall_samples) if rall_samples else ""

        summary = {
            "platform": b.platform, "design": b.design,
            "variant": b.wm_flow_variant, "num_keys": args.num_keys,
            "fraction": args.fraction, "alpha_R": args.alpha_R,
            "routing_skipped": (b.platform in _no_route_plats) or not counts,
            "true_r_P":   true_rP,
            "true_r_C":   true_rC,
            "true_T_R":   true_TR,
            "true_p_R":   true_pR,
            "true_r_R":   true_rR,
            "true_Pc":    true_pc,
            "true_r_all": true_rall,
            "wrong_key_r_all_mean": wk_rall_mean,
            "wrong_key_r_all_max":  wk_rall_max,
            # Legacy: fraction of wrong keys with pc_all <= true pc.
            "false_positive_rate_pc": (wins_pc / args.num_keys) if args.num_keys else "",
            # Paper definition: fraction of wrong keys with r_all >= true r_all.
            "false_positive_rate_r_all": (wins_rall / args.num_keys) if args.num_keys else "",
            "dist_csv": str(dist_path),
        }
        (out_root / f"wrong_key_{slug}.json").write_text(
            json.dumps(summary, indent=2))
        print(f"[wrong_key] {slug}: true_r_all={true_rall}  true_Pc={true_pc}  "
              f"FPR(r_all>=true)={summary['false_positive_rate_r_all']}  "
              f"FPR(pc<=true)={summary['false_positive_rate_pc']}  "
              f"routing_skipped={summary['routing_skipped']}")


if __name__ == "__main__":
    main()
