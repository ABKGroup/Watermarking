# SPDX-License-Identifier: BSD-3-Clause
"""Observable feature vectors for the targeted attacker (paper §7.2).

Placement and CTS features are computed *inside* OpenROAD-python by
``attacks/targeted/dump_features.py`` (they need the leaked ODB to reconstruct
the public eligible object set E_s and to read per-object layout structure).
This module keeps only the **routing** feature builder, which is derivable from
the post-DRT ``route_qr`` CSV alone and therefore needs no OpenROAD context --
so it stays import-safe for the plain-Python driver.

Every feature here is computable from the leaked post-routing layout; nothing
depends on the owner key or on the embedder's private attempt log.
"""
from __future__ import annotations

import csv
import math
from pathlib import Path
from typing import List, Tuple


def routing_features(route_qr_csv: Path) -> Tuple[List[str], List[List[float]],
                                                  List[str]]:
    """Return (header, feature_rows, net_ids) over every routed signal net.

    Reads the per-net CSV produced by ``tools/dump_route_qr.py``, whose columns
    are ``net, ww_len, tot_len, degree, vias, bbox_w, bbox_h`` (plus optional
    per-layer wirelength).  The eligible population is *all* routed nets
    (``tot_len > 0``) -- the correct denominator for the routing watermark,
    since unlike placement/CTS the routing attacker observes the full set.

    Features mirror the wrong-way carrier the verifier uses (``q_R``) plus the
    cheap geometric descriptors already present in the dump.
    """
    header = [
        "tot_len", "ww_len", "q_R",
        "log_tot_len", "degree", "vias", "bbox_w", "bbox_h",
    ]
    rows: List[List[float]] = []
    ids: List[str] = []
    for r in csv.DictReader(open(route_qr_csv)):
        try:
            tot = int(r["tot_len"])
            ww = int(r["ww_len"])
        except (KeyError, TypeError, ValueError):
            continue
        if tot <= 0:
            continue

        def _num(key: str) -> float:
            try:
                return float(r.get(key, 0) or 0)
            except (TypeError, ValueError):
                return 0.0

        ids.append(r["net"])
        rows.append([
            float(tot),
            float(ww),
            ww / tot,
            math.log1p(tot),
            _num("degree"),
            _num("vias"),
            _num("bbox_w"),
            _num("bbox_h"),
        ])
    return header, rows, ids


__all__ = ["routing_features"]
