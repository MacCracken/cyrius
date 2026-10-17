# `h.p = (two(3));` — a parenthesised multi-value call stored into a tuple FIELD — is refused twice: R17's "bind it first" and then R12's "not a tuple" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 receives lane (l6714-receives at c913d186, unit R6) and on
the lane's R5 tip compiler (0d0a054d): identical, two error lines on x86_64, aarch64 (cross), cx and PE
(CYRIUS_TARGET_WIN=1).
**Placement:** 6.7.15 — repair 5 (receives lane; filed from the 6.7.14 receives lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Low — refused loudly either way; one mistake reports two errors (the "one mistake, one error" rule,
tuple_checked.sh's CS rows). No program compiles differently.
**Kind:** diagnostics cascade.
**Discovered:** 2026-10-17, unit R6, probing the shapes around D45 (parentheses around a whole call transparent to the
destructure and the capture). A tuple FIELD store is outside D45's filed surface: it is refused by R17 (6.7.7, T5)
wrapped or not.

## Reproduction

```cyrius
struct H { a; p: (i64, i64); }
fn two(x): (i64, i64) { return (x, x + 1); }
fn t(): i64 { var h: H; h.p = (two(3)); return h.p.0 * 10 + h.p.1; }
syscall(60, t());
```

```
error:<source>:3:32: a multi-value call 'two' is not stored into a tuple field - bind it first: `var t: (i64, i64) = two(..);`, then store `t`
error:<source>:3:31: cannot store a value that is not a tuple into tuple field 'p'
```

Unwrapped, `h.p = two(3);` reports the first line only (at 3:31, `two`). Expected: the one R17 line for the wrapped
spelling too.

## Root cause

The field store (`_fld_store` area, src/frontend/parse_decl.cyr ~2600) records `fsrc = GTI(S)` — the source's first
token, the wrap's `(` — and after the value is parsed calls `_tup_fst_chk(S, ft, lfn, fsrc)`, whose R12 report is
deduplicated per token (`_tn_once`). `_fsc_paren` (6.7.6) peels the wrap and `_tup_fsc_call` reports R17 at the call's
own token (`two`, one token later), so the two reports land on different tokens and both print. Unwrapped they share
the token and R12 stays quiet.

## Fix sketch

Point R12 at the wrapped source's first inner token when the wrap holds one whole call (`_pair_unwrap(S, fsrc)` reads
exactly that shape), or have `_tup_fsc_call` mark the wrap's `(` reported as `_tup_fsc_lit` does for a literal. Row:
tuple_checked.sh beside R17i-l (the field form), one error line, wrapped and unwrapped; `h.p = (one(3));` keeps its
single R12 line.
