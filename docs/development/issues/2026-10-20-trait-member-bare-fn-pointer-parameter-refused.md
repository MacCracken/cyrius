# A trait member's bare `*fn` parameter (`cb: *fn`) is refused "expected '(', got ')'", where a fn's and an impl method's compile — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-20 by the 6.7.16 gensig lane (unit GS2), reading the trait signature reader's
`*fn` arm for issues/2026-10-18-trait-member-fn-pointer-parameter-u128-return-refused.md. Pre-existing: identical on
the lane's compiler before this unit (7a6df215c) and since 6.7.11 — 6.7.11's D34 (b) gave a fn's parameter "`_trs_type`'s
grammar plus bare `*fn`", and the trait reader (`_trs_type`) kept the grammar without the bare `*fn`.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 gensig lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16") — never 7.x.
**Severity:** Low — a valid trait member is refused (no wrong code); the impl's own method with the same parameter
compiles and runs.
**Kind:** bug (a valid signature refused: the trait reader is documented as PARSE_FN_DEF's grammar, 6.7.8, and
6.7.11 widened PARSE_FN_DEF's parameter grammar with a bare `*fn` without widening the reader). Changes what compiles
(a refused program would compile), so it is filed, not repaired in passing.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P { x; }
trait T { fn e(self, cb: *fn): i64; }
impl T for P { fn e(self, cb: *fn): i64 { return 3; } }
fn main(): i64 { var p = P { 1 }; return p.e(0); }
syscall(60, main());
```

```
$ build/cycc < bf.cyr > bf; echo rc=$?
error:<source>:3:29: expected '(', got ')'
    trait T { fn e(self, cb: *fn): i64; }
                                ^
rc=1
```

`--syntax-only` reports the same line (it is a grammar refusal). The method alone, in an inherent impl
(`impl P { fn e(self, cb: *fn): i64 { return 3; } }` and `p.e(0)`), compiles and exits 3; so does a fn
`fn ap(cb: *fn): i64` (the guide's § Functions: "a `*fn( .. )` with an optional `: T`, a bare `*fn`").

## Root cause

`_trs_type` (src/frontend/parse_fn.cyr), at `*fn`, requires the `(`: `if (TOKTYP(S, i + 1) != 10) { return
_trs_err(S, i + 1, 10); }`. The fn parameter reader `_pty_fn` takes a bare `fn` behind a `*` (`if (TOKTYP(S, i) !=
10) { return i; }`).

## Fix direction

In `_trs_type`'s `*fn` arm, return the token after `fn` when no `(` follows (a bare `*fn`), as `_pty_fn` does. The
member's own return is out of this (a fn cannot return a `*fn` of either shape; 6.7.16's D9). Rows: the repro (exit
3); a bare `*fn` as a member's return stays refused; a `*fn( .. )` parameter unchanged.
