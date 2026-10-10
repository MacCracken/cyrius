# A tail call that copies a by-value struct argument is an ordinary call — a per-fn "writes no memory" analysis would win its `jmp` back — OPEN

**Status:** 🟡 **OPEN** — the accepted cost of the 6.7.7 by-value argument fix (user, 2026-10-09: "accept the TCO
loss"). Measured 2026-10-09 on the 6.7.7 call-arguments lane (8d13c88f + the ruling's gate row): the repro below
exits 139 (SIGSEGV, the stack exhausted); the merged 6.7.7 compiler before the fix (l677-int @ 03455af0) exits 193.
`by_value_arg_copy.sh` row TU1 pins the current shape (the copying call is a `call`, a later self tail call keeps
its `jmp`); it flips when this lands.
**Placement:** 6.7.13 — the refactor / optimization review (roadmap.md § *The releases after 6.7.7*) — placed
2026-10-09 — never 7.x.
**Discovered:** 2026-10-09 in the review of the 6.7.7 call-arguments lane (the reviewer's `tco2` repro).
**Severity:** Medium — no wrong value. A deep self tail recursion whose by-value struct argument is copied ran in
constant stack before 6.7.7 and now uses one frame per call. At 3,000,000 deep it overflows the stack where it
used to run.
**Affects:** cycc 6.7.7 onward (the copy is new in 6.7.7: issue
`2026-10-09-struct-arg-sees-later-arg-side-effect`, CHANGELOG [6.7.7]).

## Summary

A parameter the callee copies in its prologue is passed by address: a plain struct over 8 B, or a Win64
value-form vector (`_pm_copies`). Since 6.7.7, such an argument is copied where it stands (`_sarg_snap`) when a
LATER argument may write memory (`_span_may_write`). Without the copy, the callee read that later write (`rd(b,
bump(&b))` read 11 where 1 is right).

In tail position the copy is a temporary in the caller's frame, which the `jmp` would free before the callee's
prologue reads it. So that call is diverted to an ordinary call (`_tc_snap_div`, 8d13c88f), and only that call:
every other tail call in the fn keeps its `jmp`.

`_span_may_write` is conservative. Any call among the later arguments counts as a write, because nothing records
whether a fn writes memory. In `return f(G, n - 1, g(acc));` the helper `g` writes nothing, yet the copy is taken
and the self tail call loses its `jmp`.

## Reproduction

```cyrius
struct Big { a: i64; b: i64; c: i64; }
var G: Big = Big { 1, 2, 3 };
fn g(x): i64 { return x + 1; }
fn f(s: Big, n, acc): i64 { if (n == 0) { return acc + s.a; } return f(G, n - 1, g(acc)); }
fn main(): i64 { return f(G, 3000000, 0) & 255; }
syscall(60, main());
```

```sh
cat tco2.cyr | build/cycc > /tmp/tco2 && chmod +x /tmp/tco2; /tmp/tco2; echo $?
# 6.7.7 (the by-value argument fix): 139 — f calls itself (`call`), one frame per level
# l677-int @ 03455af0 (before the fix):   193 — `jmp`, constant stack (3000001 & 255)
# expected once this lands:               193
```

The row that pins the shape today is `tests/gates/codegen/by_value_arg_copy.sh` TU1. In the same fn,
`return f6(G, n - 1, g6(acc))` is a `call` and `return f6(G, n - 1, acc + 1)` keeps its `jmp`.

## Root cause

- `src/frontend/parse_fn.cyr` `_span_may_write`: a `(` after `_tok_calls` (a name, `)`, `]`, a generic's `>`)
  answers 1 for every call. It has no per-callee answer.
- `_sarg_snap_ty`, through `_later_args_may_write`, therefore copies the argument.
- `_sarg_snap` with `tail` 1 sets `_tc_snap_div`, and `_tc_after_args_divert` turns the tail arm into
  `_tc_emit_call`.

## Proposed fix

A per-fn **writes no memory** summary that `_span_may_write` consults for a direct call `name(..)`, plus the
generic and method forms.

1. Record the summary at the callee's definition. Its body must have:
   - no store (an assignment to anything but its own scalar locals, `store8..64`, `memcpy` / `memset`-class
     builtins, a field or index store, `*p =`);
   - no `syscall` / `asm`;
   - no indirect call (`fncallN`, `callptr`, a closure call);
   - calls only to fns already summarized as writing no memory.
2. Make it visible to a call that precedes the callee's definition. The ordering problem is the one `#pure`'s check
   has (`2026-10-08-pure-check-misses-later-defined-callee.md`). Either record the summary in pass 1, or treat a
   not-yet-summarized callee as a writer (the conservative answer, which is today's).
3. Gate: TU1 flips (`f6` has two `jmp`s and no call). A writer helper (`g` storing into `G`) keeps the copy, the
   `call` and the right value (`by_value_arg_evaluation_order.tcyr`'s rows stay green). The summary is mutation-
   proved: forcing it to "writes nothing" must fail the evaluation-order tcyr.

Other ways to keep the `jmp` exist, such as copying into storage that survives the `jmp` (the incoming argument
area). They change each target's frame layout (SysV, Win64, aarch64, cx), so they are not proposed here.

## Consumer-side workaround (if any)

Bind the writing argument first: `var a2 = g(acc); return f(G, n - 1, a2);`. The later argument is then a name,
which `_span_may_write` reads as read-only, so no copy is taken and the call keeps its `jmp`.
