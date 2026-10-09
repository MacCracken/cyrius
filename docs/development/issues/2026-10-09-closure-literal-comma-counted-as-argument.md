# A closure literal's `|a, b|` comma is counted as an argument separator — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against 6.7.6 @ e44470b7 with the tree's `build/cycc`:
- a generic call with a two-parameter closure before its struct argument is refused with a false "has no i64 …
  instance" error;
- a `return sl(|a, b| a + b, "hello");` tail call to a `: Str` parameter passes the raw literal where a Str handle is
  expected, and returns 0 where the non-tail call returns 5.
**Placement:** unpinned — 6.x-line backlog — never 7.x. The 6.7.7 B6 lane adds `_arg_next`, an argument walker that
skips a closure's bars. Moving the three scanners below onto it is the fix.
**Discovered:** 2026-10-09 during the 6.7.7 B6 (default and named arguments) planning (repro
`closure_comma_generic.cyr`); the tail-call shape was found while filing this issue.
**Severity:** Medium — one shape is a silent wrong result (shape 2); the other refuses valid source (shape 1).
**Affects:** cycc ≤ 6.7.6. Measured on the installed compilers:
- shape 2 exits 5 on 6.6.0, 6.6.5, 6.6.10, 6.6.16, 6.7.0, 6.7.3 and 6.7.6;
- shape 1 is refused on 6.6.10, 6.6.16, 6.7.0, 6.7.3 and 6.7.6, and returned 0 (a wrong value) on 6.6.0 and 6.6.5.

`_CALL_ARGC_PEEK` has had the same rule since 6.5.1.

## Summary

Three scanners find "argument k" of a call on the raw token stream. Each one counts a depth-0 `,` as an argument
boundary and tracks only `( [ {` for depth. A closure literal's parameter list `|a, b|` has a depth-0 comma, so every
argument after the closure is numbered one too high.

| Scanner | Location | Used for | Effect |
|---|---|---|---|
| `_call_arg_start` | `src/frontend/parse_fn.cyr:8406` | generic type-argument inference: `_gen_infer_tp` (:8518), `_gs_arg_named` (:8396), `_tok_gen_ret_sid` (`src/frontend/parse.cyr:325`) | reads the closure's `b` as argument 1, so T is inferred from a scalar and the call is refused (shape 1) |
| `_tc_str_literal_arg` | `src/frontend/parse_fn.cyr:2112` | the tail-call divert for a string literal into a `: Str` parameter (`_tc_args_divert` :694, 6.6.5) | numbers the literal 2 instead of 1, so the call is not diverted and the tail arm jumps without the `str_from` wrap (shape 2) |
| `_CALL_ARGC_PEEK` | `src/frontend/parse_fn.cyr:4020` | the arity gate for overload routing (`_OV_ARITY_OK`, :4184 / :4214) | over-counts by one per extra closure comma (not probed for a visible symptom) |

A one-parameter closure (`|a| a`) has no comma, so it is unaffected. `||` is a single token.

## Reproduction

Shape 1: `docs/development/issues/repros/2026-10-09-closure-literal-comma-counted-as-argument-1-generic.cyr`.

```cyrius
struct Pt { x; y; }
fn gx<T>(c, v: T): i64 { return v.x; }
fn main(): i64 { var p = Pt { 7, 9 }; return gx(|a, b| a + b, p); }
var r = main();
syscall(60, r);
```

```
actual:   error:<source>:9:49: generic 'gx' has no i64 (or other scalar) instance: … (rc 1)
expected: compiles; exit 7.  With `|a| a` as the first argument it does.
```

Shape 2: `docs/development/issues/repros/2026-10-09-closure-literal-comma-counted-as-argument-2-str-tail-call.cyr`.

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
fn sl(c, t: Str): i64 { return str_len(t); }
fn viaret(): i64 { return sl(|a, b| a + b, "hello"); }
fn viavar(): i64 { var n = sl(|a, b| a + b, "hello"); return n; }
fn main(): i64 { alloc_init(); return viaret() * 10 + viavar(); }
var r = main();
syscall(60, r);
```

```
actual:   rc 0, exit 5   — viaret() is 0, viavar() is 5
expected: exit 55        — the same tail call with `|a| a` or `0` as its first argument returns 5
```

Run them from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Proposed fix

Teach the three scanners the closure-bar rule once, in a shared argument walker, and use that walker everywhere.

The rule: at an argument's start, a `|` (35) opens a closure's parameter list and the walk skips to the matching `|`.
Typed closure parameters are refused, so no `:` or nested bar appears inside. The 6.7.7 B6 lane's `_arg_next` (the
parameter-list / argument walkers of its bite 1b) is that walker.

Moving `_call_arg_start`, `_tc_str_literal_arg` and `_CALL_ARGC_PEEK` onto it turns shape 1's false refusal into a
compile and fixes shape 2's miscompile. Add a gate row for each shape and for an overload-routed call with a closure
argument.

## Consumer-side workaround

Bind the closure to a local first (`var c = |a, b| a + b; gx(c, p)`), or pass it last.
