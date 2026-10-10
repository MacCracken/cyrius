# A refused top-level const leaves the `_panic` latch set: the next const's error is never printed, and pass 2 drops a statement — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against the merged 6.7.7 tip (`/home/macro/.cache/c6/wt677/int`
@ 06bd8981, its `build/cycc`, 1,916,288 B). The repro prints the errors for `xx` and `zz` but never the one for `yy`.
The shapes measured below behave the same way. Identical on the installed 6.7.2, 6.7.4 and 6.7.6 compilers.
**Placement:** 6.7.12 — Break 2, repair 3 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
It is a diagnostics-only defect, so it goes with that release's Diagnostics group (the const-fn cascade and
`error:0:1:` issue, the bare const statement, the const field access).
**Discovered:** 2026-10-09 by the 6.7.7 B6 lane (default and named arguments), bite 2, outside its scope (listed in
the 6.7.7 CHANGELOG draft as "pass 1 never resyncs `_panic`"); filed 2026-10-09.
**Severity:** Low — every input is invalid and refused (rc 1, no binary). The cost is a missing error, or a false
`undefined variable` in its place.
**Affects:** cycc 6.7.2 (top-level `const`) through the merged 6.7.7.

## Summary

The first error of a const evaluation in pass 1 sets the parser's cascade latch `_panic`. That includes the
end-of-pass-1 sweep that evaluates every top-level const, and an enum value or a global array size declared in pass 1.
Nothing clears the latch before the next evaluation, so every later evaluation's message is swallowed. The const is
still refused (its value is 0 and `_had_error` is set), but its error is never printed. The latch then survives into
pass 2. There, the first statement's resync (`_sync_skip`) skips the statement after it: that statement's error is
lost, or a name it declared is then reported as an `undefined variable`.

## Reproduction

`docs/development/issues/repros/2026-10-09-const-sweep-swallows-later-const-errors.cyr`:

```cyrius
const A = xx;
const B = yy;
fn f(): i64 { return zz; }
syscall(60, A + B);
```

```
cat repro.cyr | build/cycc > /dev/null
actual:   error:<source>:3:11: unknown name 'xx' in a const context
          error:<source>:5:24: undefined variable 'zz' (missing include or enum?)
expected: the two above plus  error:<source>:4:11: unknown name 'yy' in a const context
```

Each shape below was measured on the merged tip. The first column is the source, with `\n` between lines. Only the
errors printed are shown.

| source | printed | missing |
|---|---|---|
| `const A = xx; const B = yy; const D = ww;` | `xx` | `yy`, `ww` |
| `const A = 10 / 0; const B = 1 / 0;` | the first "division by zero" | the second |
| `enum E { Q = yy }` then `const A = xx;` | `yy` | `xx` |
| `var g: i64[yy];` then `const A = xx;` | `yy` | `xx` |
| `const A = xx;` then `fn g(a = yy) ..` and a call `g()` | `xx`, then a cascade "'g' expects 1 argument, got 0" | `yy` |
| `const A = xx;` then `fn main(): i64 { var q = 1; const L = yy; return L + q; }` | `xx`, then a FALSE "undefined variable 'L'" | `yy` |
| `const A = xx;` then `fn main(): i64 { const L = yy; return L; }` | `xx` | `yy` |
| `enum E { Q = yy }` then `fn main(): i64 { var q = 1; const L = ww; return L + q; }` | `yy`, then a FALSE "undefined variable 'L'" | `ww` |

The controls: two bad parameter defaults print both errors, and one bad local const in each of two fns prints both.
With no earlier error, `fn main(): i64 { var q = 1; const L = ww; .. }` prints `ww` alone.

## Root cause

- `ERR_IDENT` / `ERR_MSG` (`src/common/util.cyr:2988` / `:3010`) return at once when `_panic == 1`, and otherwise set
  it. This is the v6.4.62 cascade latch. `_sync_skip` (util.cyr:2683) is what clears it, run from the statement loop
  after a statement that errored.
- `_cst_sweep` (`src/frontend/parse_fn.cyr:8616`) runs at the end of pass 1 (`_tl_pass1` :12319, the call at
  :12328), outside any statement. It goes through `_cst_value` → `_cst_eval` (:8579) → `_ce_top_expr` (:8560) →
  `_ce_bad` / `_ce_badn` (:7228 / :7237) → `ERR_*`. `_ce_top_expr` resets `_ce_err` for each evaluation but not
  `_panic`, so after the first refusal every later message is dropped.
- The pass-1 in-place sites set the latch the same way, through `_ce_eval_here` :8664 / `_ce_eval_int` :8681: an
  enum value (`_enum_val` :8928 → `_cst_ctx_val` :8910) and a global array size (`PARSE_GVAR_ARR`,
  `src/frontend/parse_decl.cyr:3086`). Pass 1's declaration loop never resyncs, so the latch is still set when the
  sweep runs, and still set when pass 2 starts at token 0.
- `_pd_eval` (:2920) shows the right local shape for a top-context evaluation. It saves the latch (`var pw = _panic;`,
  :2926) and clears it after its own refusal when it was clear before. That is why two bad defaults both report, and
  why a default after a bad const does not (`pw` is already 1).

## Proposed fix

Diagnostics only: nothing that compiles changes.

1. `_ce_top_expr` evaluates with the latch clear and puts the caller's value back afterwards. The tokens it evaluates
   are a declaration's own, never the cursor's statement, so its refusal needs no resync. This subsumes `_pd_eval`'s
   `pw` rule; remove that rule.
2. `_tl_pass1` clears `_panic` after `_pd_sweep`, because pass 2 restarts at token 0 in sync. Check that pass 2 does
   not then report a pass-1 refusal a second time, for example an enum value or a global array size re-walked in
   pass 2. If it does, dedup that site by token (`_tn_once`) rather than keep the latch.

Gate rows: each shape in the table prints exactly its own errors, once each, and no "undefined variable 'L'".
