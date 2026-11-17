# The guide's 6.6.10 note says a compare of builtin results is an integer compare of the bits; at 6.7.18 it is IEEE — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18 (x86_64), 2026-11-16, against `docs/guides/cyrius-guide.md` at that
release. The repro exits 1.
**Placement:** unpinned — 6.x-line backlog (documentation).
**Discovered:** 2026-11-16, by rasayan's Rust → Cyrius port (M0 step 9, probe 12, trap 11;
`rasayan/docs/development/port-parity.md` §3).
**Reporter:** rasayan 2.0.0 port.
**Severity:** **Low.** Documentation only; the compiler is right.
**Affects:** `docs/guides/cyrius-guide.md` ("Float builtin results in arithmetic (6.6.10)").

## Summary

The note says: "The result is still not a typed *value*: `==`, `!=`, `<` … on builtin results remain INTEGER compares
of the bit patterns (so `f64_neg(z) == z` is 0 for z = 0.0, and `f64_neg(a) < f64_neg(b)` is wrong for negative
values — compare with `f64_lt` / `f64_gt` / `f64_eq` / `f64_le` / `f64_ge`)".

At 6.7.18 both examples are IEEE compares: `f64_neg(z) == z` is **1** for z = +0.0 (−0 == +0), and `f64_neg(1.0) <
f64_neg(2.0)` is **0** (−1 < −2 is false) — the same answers as with each result bound to a `: f64` local first. A
reader who trusts the note rewrites correct compares through `f64_eq` / `f64_lt`, or distrusts code that is right.

## Reproduction

[`repros/2026-11-16-guide-builtin-result-compare-note-is-stale.sh`](repros/2026-11-16-guide-builtin-result-compare-note-is-stale.sh)
(it reads the guide from
`docs/guides/cyrius-guide.md` there):

```sh
bash docs/development/issues/repros/2026-11-16-guide-builtin-result-compare-note-is-stale.sh; echo $?
# f64_neg(+0.0) == +0.0: 1 (IEEE 1, the note says 0); f64_neg(1.0) < f64_neg(2.0): 0 (IEEE 0)
# guide note present: 1 (…/cyrius-guide.md)
# repro: DEFECT PRESENT (the compares are IEEE; the guide says they are integer compares)
# 1
```

## Proposed fix

Replace the sentence with the 6.7.18 behaviour (and the release that changed it): a compare whose operands are float
builtin results is an IEEE compare. Keep the advice that matters still — `var x = f64_sqrt(u);` declares an untyped
`x`, so bind a result to a `: f64` local before later arithmetic on it.

## Consumer-side workaround

None needed in code. rasayan keeps the documented safe form anyway (bind a builtin's result to a `: f64` local before
an operator or comparison: CLAUDE.md, f64 hygiene).
