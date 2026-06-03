> **RESOLVED v6.0.47** — `secret`/`defer` per-fn cap raised 8 → 64 (table relocated to S+0x1AC020/0x1AC028). See CHANGELOG [6.0.47].

# cyrius: raise the per-function `secret`/`defer` block cap (8 → 32)

**Filed:** 2026-05-27
**Reporter:** sigil (AGNOS trust-verification library, v3.5.x crypto cycle)
**Cyrius version at time of report:** 6.0.3
**Severity:** **P4 — enhancement.** No project is blocked; sigil
worked around the cap by consolidating state into a single
`secret var` scratch block. The request is headroom for
register-/buffer-heavy crypto where a per-temporary `secret var`
reads more clearly than one sliced megablock.
**Status:** open — enhancement request.

## Summary

A single function may declare at most **8** `secret`/`defer`
blocks. Exceeding the cap is a hard compile error:

```
error: too many defer/secret blocks (max 8)
```

emitted at `src/frontend/parse.cyr:710`. The bound is the fixed
per-function block table in the compile-state struct: the count
lives at `S + 0x18F900`, and each block record is 24 bytes
(`ssbody`, `ssend`, `sflag`) at `S + 0x18F908 + i*24` — i.e. the
table reserves `8 * 24 = 192` bytes (`0x18F908 .. 0x18F9C8`).

Request: raise the cap to **32** (`32 * 24 = 768` bytes of table),
which is comfortable headroom without being open-ended.

## Where it bit (sigil)

sigil 3.5.x added X25519 (`src/x25519.cyr`), whose Montgomery
ladder keeps the clamped scalar plus ~16 Curve25519 field-element
temporaries (`x_2, z_2, x_3, z_3, A, AA, B, BB, E, C, D, DA, CB,
t0, t1, a24, k`). The natural, auditable form is one `secret var`
per field element so the compiler zeroizes each on return:

```cyrius
secret var x_2[32]; secret var z_2[32]; secret var x_3[32]; ...
```

That is ~16–18 `secret` blocks — over double the cap. The cap
forces consolidating everything into a single
`secret var W[576]` block addressed by hand-computed slice offsets
(`var x_2 = &W + 32;` …). It works and is zeroized correctly, but
the offset bookkeeping is exactly the error-prone pattern
`secret var` is meant to remove. Ladder-style algorithms (X25519,
P-256/P-384 scalar mult, future ML-KEM) all want a dozen-plus
secret temporaries.

## Proposed fix

1. Bump the bound check at `src/frontend/parse.cyr:710` from
   `if (sdci >= 8)` to `if (sdci >= 32)`.
2. Reserve `32 * 24 = 768` bytes for the block-record table at
   `S + 0x18F908`, relocating whatever per-function field
   currently follows the 192-byte table (`0x18F9C8`) so the larger
   table does not clobber it. The count slot at `S + 0x18F900` is
   unchanged.
3. Mirror the comment in `src/main.cyr:55` and
   `src/main_win.cyr:40` (`defer_count [8] … (max 8)` →
   `(max 32)`).

The sibling `&&`-conditions cap (`util.cyr:216`) and
continue-in-loop cap (`parse.cyr:867`) are independent max-8
limits; this request is only about `secret`/`defer`.

## Workaround (in place at sigil 3.5.x)

`src/x25519.cyr` uses one `secret var W[576]` scratch block with
named pointer slices. No correctness or zeroization compromise;
purely a readability cost. sigil does not need this enhancement to
ship the 3.5 crypto cycle — filing so the constraint is visible
when the next ladder-shaped primitive lands.

## Seen again — sigil 3.5.9 (2026-05-28, cyrius 6.0.14)

The cap is still 8 at 6.0.14. sigil's ECDSA signing
(`src/ecdsa_sign.cyr`, the 3.5.9 ship) hit it: `ecdsa_p256_sign` /
`ecdsa_p384_sign` each want ~13 secret temporaries (`digest, e,
h1oct, k, kint, kinv, dint, rint, sint, rd, hpd, Rx, Ry`) for the
`s = k^{-1}(e + r·d) mod n` computation. Same workaround applied —
one `secret var sc[416]` (P-256) / `sc[624]` (P-384) megablock with
named offset slices. Second ladder/scalar-mult-shaped primitive to
hit the cap; the 32-block headroom requested above would have let
both X25519 and ECDSA-sign keep one `secret var` per temporary.
Still P4 (worked around, not blocking) — recording the recurrence.

## Target (user-set 2026-06-02)

secret/defer per-fn cap **8 → 64** (supersedes the 32 originally requested). Table-cap bundle, after platform repairs.
