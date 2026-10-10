# A const context counts a `Pair<i64, i64>` parameter as two — `pick(0, 7)` is refused, `pick(0, 1, 7)` builds — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against the merged 6.7.7 tip (`/home/macro/.cache/c6/wt677/int`
@ 06bd8981, its `build/cycc`, 1,916,288 B): the repro is refused with "a const fn called with the wrong number of
arguments"; the same file calling `pick(0, 1, 7)` builds and exits 7. A run-time call to the same fn counts two
parameters (`pick(q, 1, 7)` is refused, "'pick' expects 2 arguments, got 3"). Identical on the installed 6.7.2,
6.7.4 and 6.7.6 compilers.
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x;
a const-evaluator parser bug, in the release that repairs the 6.7.7 follow-ons.
**Discovered:** 2026-10-09 by the 6.7.7 B6 lane (default and named arguments), bite 1b, outside its scope (listed in
the 6.7.7 CHANGELOG draft's "reported by the lanes in passing, NOT filed"); filed 2026-10-09.
**Severity:** Medium — a valid const call is refused, and a call with one argument too many is accepted silently in a
const context while the run-time call is refused. The workaround is a parameter type with no comma (an untyped
parameter, or a non-generic struct).
**Affects:** cycc 6.7.2 (`const fn`) through the merged 6.7.7.

## Summary

The const evaluator counts and binds a const fn's parameters with paren depth only. A comma inside `<..>`, as in
`p: Pair<i64, i64>`, splits that parameter in two. In a const context `pick` therefore takes three arguments:
`pick(0, 7)` is refused, and `pick(0, 1, 7)` binds `p = 0`, a phantom parameter named `i64` = 1 (by reading) and
`b = 7`. The parser's own parameter walker is `<`-aware, so the same fn takes two arguments at run time. A pointer
type (`p: *Pair<i64, i64>`) and a generic parameter in last place (`pick(b, p: Pair<i64, i64>)`) are refused the same
way.

## Reproduction

`docs/development/issues/repros/2026-10-09-const-fn-generic-param-comma-miscounted.cyr`:

```cyrius
struct Pair<A, B> { a: A; b: B; }
const fn pick(p: Pair<i64, i64>, b) { return b; }
const N = pick(0, 7);
syscall(60, N);
```

```
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
actual:   error:<source>:6:21: a const fn called with the wrong number of arguments   (rc 1)
expected: builds, exits 7
```

With `pick(0, 1, 7)` the file builds and exits 7. It should be refused, because the run-time call is:
`fn main(): i64 { var q: Pair<i64, i64>; q.a = 1; return pick(q, 1, 7); }` reports `'pick' expects 2 arguments,
got 3`.

**This bug does not cause the run-time crash.** `fn main(): i64 { return pick(0, 7); }` exits 139. The cause is the
integer `0` passed to a by-value struct parameter over 8 bytes. The callee copies the struct from that address on
entry, as the guide documents (cyrius-guide.md § "A by-value struct PARAMETER is a COPY": "an argument that is not a
struct (`take(0)` for a `q: P3`) now faults there"). A non-generic `struct P { a: i64; b: i64; }` with `fn pick(p: P,
b)` exits 139 the same way. A real `Pair<i64, i64>` value gives 7 through both `fn` and `const fn`.

## Root cause

All locations are in `src/frontend/parse_fn.cyr` at the merged tip:

- `_ce_nparams` (:8453) counts depth-0 commas with `(` / `)` depth only.
- `_ce_bind_params` (:7827) steps each parameter with `_tok_item_end` (:2452), which balances `( [ {` but not `<`.
  Its 6.7.7 comment (:7846-7850) records why it was left this way: the count must agree with `_ce_nparams` at the
  definition check (`_ce_check_fn`, :8404, which pushes `_ce_nparams` frames and then binds). A `<`-aware bind alone
  would refuse the uncalled `const fn f(p: Pair<i64, i64>, b)`, gate row `tests/gates/frontend/const_checked.sh` C3.
- `_ce_tup_param` (:8438) walks the same list with `_tok_item_end`.
- The parser's walker `_pl_next` (:2482) balances the type with `_pl_tdepth` (:2472): `( [ { <` open, and `>` / `>>`
  / `>>>` close one, two or three levels. After a depth-0 `=` it uses `_pl_dflt_end`, where `<` is an operator. That
  is the rule the run-time arity check uses.

## Proposed fix

Walk a const fn's parameter list with `_pl_next` in all three places at once: `_ce_nparams`, `_ce_bind_params` and
`_ce_tup_param`. The definition-check count and the bind then still agree, and the walk matches the run-time arity.

Add `const_checked.sh` rows:
- `pick(0, 7)` exits 7.
- `pick(0, 1, 7)` is refused.
- `*Pair<i64, i64>` and the generic parameter in last place are accepted.
- `Vec<Vec<i64>>` (the `>>` close) is accepted.
- A default holding `<` (`c = 1 < 2`) is still one parameter.
- C3 stays green.

⚠ Ask in one line at the open: refusing `const N = pick(0, 1, 7);` makes code that compiles today (exit 7) stop
compiling. The refusal is the arity the run-time call already enforces.
