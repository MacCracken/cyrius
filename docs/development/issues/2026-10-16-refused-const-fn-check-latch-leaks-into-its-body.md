# A refused const fn's definition check leaves the cascade latch on for its run-time body: a false "undefined variable" for a local const, and a later statement's error reported twice — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-16 by the 6.7.14 frontend lane (unit F2) while fixing the const-fn double
report (issues/archived/2026-10-08-diagnostic-cascades-and-locationless-eof-errors.md, item 1). Measured on 87ef0dd9 (the lane
before F2) and on F2's tree: identical (F2 deliberately keeps the latch, see Root cause).
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — every input is refused; one shape prints a FALSE error, the other a duplicate.
**Kind:** diagnostics.

## Repro

```cyrius
# lc4b — the check refuses the local const's annotation; the run-time body then never binds k
const fn cf(): i64 { var a = 1; const k: i64 = 3; return k; }
const Z = cf();
fn g(): i64 { return cf(); }
syscall(60, g() + Z);
```
```
error:<source>:1:40: a const takes no type annotation: its type is its value's
error:<source>:1:59: undefined variable 'k' (missing include or enum?)      <- false: k is declared
```
(Without the leading `var a = 1;` — tests/gates/frontend/const_checked.sh row LC4 — one error.)

```cyrius
# sx1 — a syntax error in the body's second statement
const fn f(n) {
    var a = 1;
    var b = (2;
    return b;
}
fn main() { return 0; }
var r = main();
```
```
error:<source>:3:15: expected ')', got ';'
error:<source>:3:15: expected ')', got ';'
```
(In the FIRST statement — `var b = (2;` alone — one error.)

Want: each error once, and no false one.

## Root cause

`_ce_check_fn` (src/frontend/parse_fn.cyr) walks a const fn's body at its definition (pass 2) with `_ce_ti`; a refusal
sets the cascade latch `_panic` (ERR_*, or `_ce_said`'s count of a token the end-of-pass-1 sweep already reported,
"exactly as ERR_* would set them"), and nothing clears it before the SAME body is compiled as an ordinary fn. So the
run-time parse begins latched: its first statement's errors are swallowed (which is what dedupes LC4 and sx2 today —
by accident), and at that statement's end `_stmt_resync` → `_sync_skip` skips forward to the next `;` — over the next
statement whole when it does not open with a keyword (lc4b: `const k: i64 = 3;` is skipped, so `k` is never bound).
An error in any later statement is reported by the check and again by the run-time compile, at the same token (sx1).
F2 (6.7.14) stands down only the run-time "undefined variable" reports of the name the check refused
(`_ce_name_said`) and, after the const-field bite, the field arms' "no struct type in scope" in a refused body
(`_ce_fn_refd`); it keeps the latch out of `_ce_check_fn` (restoring it to clear made LC4 print its annotation
refusal twice, from `_cst_ann_err`).

## Fix sketch

End the check with the caller's latch (as `_ce_top_expr` does since 6.7.14), and make the run-time body of a const fn
whose check refused stand down every report at a token the check already reported (`_tn_seen_at`) — the per-token
memory the generics lane is agreeing for generic instance replays (ERR_EXPECT / ERR_IDENT / ERR_MSG), scoped here to
that body. Rows: lc4b one error (no 'k'), sx1 one error, LC4 / sx2 unchanged.
