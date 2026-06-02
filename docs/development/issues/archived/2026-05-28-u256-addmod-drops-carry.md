# cyrius: `lib/bigint.cyr` `u256_addmod` drops the 2^256 carry — wrong for moduli near 2^256

**Filed:** 2026-05-28
**Reporter:** sigil (AGNOS trust-verification library, v3.5.9 — ECDSA
P-256/P-384 RFC 6979 signing)
**Cyrius version at time of report:** 6.0.14
**Severity:** **Medium — latent correctness bug.** The stdlib
`u256_addmod` returns a wrong residue whenever `a + b >= 2^256`. It
happens to be correct for the only modulus cyrius's own callers use
it with today (Curve25519's `p = 2^255 − 19`, where field elements
are `< 2^255` so `a + b < 2^256`), which is why it has not surfaced.
It is **wrong** for any modulus near `2^256` — e.g. the NIST P-256
group order `n ≈ 2^256` — where `a + b` can exceed `2^256`. No cyrius
build is currently broken; sigil hit it building ECDSA scalar
arithmetic and worked around it locally. Filing so the stdlib is
fixed before another consumer trusts it on a large modulus.
**Status:** open.

## Summary

`lib/bigint.cyr:286`:

```cyrius
fn u256_addmod(r, a, b, p): i64 {
    u256_add(r, a, b);                                   # <-- carry discarded
    if (u256_cmp(r, p) >= 0) { u256_sub(r, r, p); }
    return 0;
}
```

`u256_add` (`lib/bigint.cyr:133`) **returns the carry-out** (the bit
that overflows 256 bits) — every other caller checks it. `u256_addmod`
ignores it. When `a + b >= 2^256`, `u256_add` stores `(a + b) mod
2^256` in `r` and returns `carry = 1`; `u256_addmod` then tests only
the truncated `r` against `p`. Because the true sum lost its `2^256`
term, the single conditional subtract can be skipped when it was
actually needed, leaving `r` short by `2^256 − p`.

The sibling `u256_submod` (`:293`) *does* honor its borrow
(`if (borrow > 0) u256_add(r, r, p)`), so the add path is the
inconsistent one.

## Concrete failing case

Let `p = n` = the P-256 group order
`FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551`
(`≈ 2^256 − 2^224`), and `a = b = n − 1` (both valid residues `< p`).

- True result: `(a + b) mod n = (2n − 2) mod n = n − 2`.
- `u256_addmod`: `a + b = 2n − 2 ≈ 2^257`, so `u256_add` overflows —
  `r = (2n − 2) − 2^256`, `carry = 1` (dropped). That `r` is
  `< n`, so the `cmp(r, p) >= 0` test is **false**, no subtract runs,
  and the function returns `r = 2n − 2 − 2^256`, which differs from
  the correct `n − 2` by exactly `n − 2^256` (`≈ 2^224`). **Wrong.**

Any `a, b < p` with `a + b >= 2^256` reproduces it. With
`p < 2^255` (Curve25519) the precondition `a + b < 2^256` always
holds, so the existing ed25519/x25519 callers are unaffected.

## Proposed fix

Honor the carry, mirroring `u256_submod`. With the standard
precondition `a, b < p` the sum is `< 2p < 2^257`, so a single
subtract still suffices:

```cyrius
fn u256_addmod(r, a, b, p): i64 {
    var carry = u256_add(r, a, b);
    if (carry > 0) {
        u256_sub(r, r, p);                  # overflowed 2^256 → reduce once
    } else {
        if (u256_cmp(r, p) >= 0) { u256_sub(r, r, p); }
    }
    return 0;
}
```

(When `carry == 1` and `a, b < p`, the truncated `r` is always `< p`,
so `u256_sub(r, r, p)` borrows and wraps to the correct
`a + b − 2^256 + (2^256 − p) = a + b − p`. Verified against the P-256
case above.)

Please also audit any `u384_addmod` / wider `*_addmod` helpers for the
same dropped-carry pattern, and consider a one-line comment on the
precondition (`a, b < p`).

## Where it bit (sigil)

sigil 3.5.9 (`src/ecdsa_sign.cyr`) computes the ECDSA signature
scalar `s = k^{-1}(e + r·d) mod n` over the P-256/P-384 group order
`n ≈ 2^{256/384}`. The `(e + r·d) mod n` add needs a carry-correct
add-mod-n; `u256_addmod` produced wrong signatures for inputs whose
sum crossed `2^256`. sigil worked around it with a local
`_ecs_addmod_n_p256` / `_p384` that checks the `u256_add` /
`u384_add` carry (the snippet above). The RFC 6979 Appendix A.2.5 /
A.2.6 known-answer vectors only pass with the carry-correct version,
which is how the bug was caught.

## Not asking for

- Any change to `u256_submod` (already correct).
- Behavior change for sub-`2^256` moduli (the fix is a no-op there).
