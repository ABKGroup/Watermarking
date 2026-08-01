# Key generation and stage-seed derivation

Ed25519-signature-based derivation of the per-stage watermark seeds. Each
watermarking stage consumes exactly one `seed_<stage>.hex`.

## Why a signature

The watermark must bind to *an owner and a design*, not just to a random
number. Deriving the master seed from a signature over a binding message means
that showing `(M, sig, pk)` proves the seed could only have been produced by the
holder of `sk` — the seed itself never has to be revealed to make the argument.

## Pipeline

**1. One-time owner setup** (`keygen`)

Generates `sk.pem` (mode `0600`) and `pk.pem`, and appends
`{owner_id, timestamp_utc, pk_fingerprint_sha256, pk_path}` to a local
`registry.json`.

**2. Per-design signing** (`sign`)

Builds the binding message

```json
{
  "owner_id":  "...",
  "design_id": "...",
  "date":      "YYYY-MM-DD",
  "tool":      {"name": "OpenROAD", "commit": "<hash>"},
  "nonce":     "<hex>"
}
```

canonicalizes it with sorted keys and compact separators (a pragmatic RFC 8785),
signs it, and derives:

```
master_seed    = SHA256(sig)                       # 32 B
seed_placement = SHA256(master_seed || "placement")
seed_cts       = SHA256(master_seed || "cts")
seed_routing   = SHA256(master_seed || "routing")
```

Writes `M.json`, `sig.bin`, `pk.pem`, `bundle.json` and the three
`seed_*.hex` files to `out/<design_id>/`.

**3. Audit** (`verify`)

Re-canonicalizes `M.json`, verifies `sig.bin` against `pk.pem`, recomputes the
master seed and the three stage seeds, and compares them to what is on disk.

## Install

```bash
pip install -r ../requirements.txt      # needs cryptography>=42
```

PyNaCl is supported as a fallback backend if `cryptography` is unavailable.

## Usage

```bash
# 1) One-time: owner keypair + local registry entry.
./gen_key.sh keygen --owner-id alice --out-dir keys

# 2) Per design: sign and derive the three stage seeds.
./gen_key.sh sign \
    --sk keys/sk.pem --pk keys/pk.pem \
    --owner-id alice --design-id jpeg \
    --out-dir out/jpeg

# 3) Audit an existing bundle.
./gen_key.sh verify --bundle-dir out/jpeg
```

`sign` refuses to overwrite an existing bundle unless you pass `--force`.

| Flag | Meaning | Default |
|---|---|---|
| `--sk`, `--pk` | key paths | *required* |
| `--owner-id`, `--design-id` | binding-message identity | *required* |
| `--date` | date recorded in `M` | today (UTC) |
| `--tool-name` | tool recorded in `M` | `OpenROAD` |
| `--tool-commit` | commit recorded in `M` | git HEAD of `--tool-root`, else `unknown` |
| `--tool-root` | checkout to read HEAD from | `$OPENROAD_ROOT` |
| `--nonce` | hex nonce | 16 random bytes |
| `--out-dir` | output directory | `out/<design_id>` |
| `--force` | overwrite an existing bundle | off |

`GEN_KEY_PYTHON` overrides the interpreter `gen_key.sh` picks.

## Consuming the seeds

Each stage's runner points `WM_SEED_HEX` at the matching file:

```bash
export WM_SEED_HEX=out/jpeg/seed_placement.hex   # placement_wm/
export WM_SEED_HEX=out/jpeg/seed_cts.hex         # cts_wm/
export WM_SEED_HEX=out/jpeg/seed_routing.hex     # routing_wm/
```

[`wm_prf.load_seed_hex`](../wm_prf.py) reads the file into a raw 32-byte key and
rejects anything that is not exactly 32 bytes — a truncated seed would silently
produce a different, unverifiable watermark. The runner in each stage directory
generates the bundle on demand if it is missing, so you rarely call
`gen_key.sh` by hand.

## Threat model and operational notes

- `registry.json` here is a **local stub**. A real deployment publishes
  `(pk, owner_identity, timestamp)` to a tamper-evident registry so a verifier
  can anchor `pk_fingerprint_sha256` to an identity. It is gitignored.
- Ed25519 signatures are deterministic; verification needs only what is stored
  in `M`, not the original nonce separately.
- `sk.pem` is written `0600`. **Never commit it**; back it up offline.
- `keys/`, `out/` and `registry.json` are gitignored. Once a design is taped
  out, freeze its seed files read-only — regenerating them changes the
  watermark.
