# A fn that calls an inline-replayed `: stack` pair generic is flagged pair-returning ITSELF: a false "bind both" at its callers and a false mixed-return warning — RESOLVED

> ✅ **RESOLVED in v6.7.13** (MV-3 and MV-4, no decision needed. A `return` inside an inline replay no longer marks the CALLER pair-returning (MV-3), and the issue's own second item, the two `?` arms, is the same false flag (MV-4). A replayed `?`'s Err jump lands at the replay's end, the call's value, not the caller's epilogue. All three marks are guarded `GIDEP == 0`; the instance's own entry keeps its flag. The filed repro was refused "bind both" with a false mixed-return warning; it compiles and exits 7 on x86_64, aarch64, cx and PE. The variants: the top-level `var e = main();` is 7; `syscall(60, main())` has no warning; the T5b store reports one error; a replayed forwarder propagates (161). A caller of a replayed `?` binds one value: 31 for the expression `?`, 91 for the statement `?;`; the propagation itself is unchanged (73). A destructure of such a caller (`var a, b = main();`) now meets the one-value rule ("returns 1 value"); it bound a stale register. Rows: `frontend/stack_enum_lossy_context.sh` axis IR (IR1 the repro verbatim, IR2, IR4, IR5, IR5b) and IR6 (IR6a – IR6d), and `frontend/stack_enum_mixed_return_warning.sh` `ir_replay` / `ir_replay_q` (x86 + aarch64). Mutations MIR, MIRQe and MIRQs RED. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 returns lane (l6711-returns, the R3 tip after the
impl-method pair prescan); the same on the installed 6.6.0, 6.6.10, 6.6.16, 6.6.20, 6.7.0, 6.7.2, 6.7.5, 6.7.6
and 6.7.10 compilers.
**Placement:** 6.7.13 — repair 3: struct values (multivalue lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Severity:** Medium — valid code is refused (a false "bind both" on a one-value fn) and a false warning tells the
author to return a variant from a fn that returns an i64; nothing miscompiles silently. Met while writing the
6.7.11 D22 rows: a refusal row whose fn calls such a generic reports a second, false error at its caller.
**Affects:** cycc 6.6.0 – the 6.7.11 lane tip, x86_64 measured (frontend state).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
enum SR: stack { SOk(v); SErr(e); }
fn gg<T>(v: T) { return SOk(v); }
fn main(): i64 { var t, v = gg<i64>(7); return v; }
fn caller(): i64 { var x = main(); return x; }
syscall(60, caller());
```

```
actual:   error:<source>:5:26: a `: stack` enum returns two values — bind both: `var tag, val = f();`
          warning:<source>:4:41: `main` returns a `: stack` pair on another path but a SINGLE value here — ...
expected: compiles, exit 7 (`main` returns one value, v)
```

Variants (the same tip):

- `var e = main();` at top level instead of `caller`: the same false "bind both" at `main()`.
- `syscall(60, main());`: compiles and exits 7, with the false mixed-return warning on `main`'s `return v;`.
- `gg` with two returns (`if (v == 0) { return SErr(1); } return SOk(v);`): compiles, exit 7 — no false flag.
- `gg` not generic (`fn gg(v) { return SOk(v); }`, called `gg(7)`): compiles, exit 7 — no false flag.
- A refused store in `main` (`h.a = gg<i64>(7);`, T5b) reports TWO errors: its own, and the false one at
  `var e = main();`.

## Root cause

`_PARSE_RETURN_ARMS` (`src/frontend/parse_fn.cyr`, the v6.5.67 propagation: `if (_cur_fn_ix >= 0) { if
(_callee_returns_pair(S) == 1) { SFLG(S, _cur_fn_ix, .. | 256); } }`) marks the fn being parsed when a `return`
forwards a pair. When the one-statement generic instance `gg<i64>` is inline-replayed into `main` (GIDEP > 0 —
the same arm already disables the tail call there), `_cur_fn_ix` is still `main`, so the instance's `return
SOk(v)` marks MAIN as pair-returning. Measured: guarding that marking with `GIDEP(S) == 0` (a scratch build) makes
every variant above compile clean and exit 7, and the T5b refusal report one error.

## Proposed fix

Do not mark `_cur_fn_ix` from a `return` inside an inline replay (GIDEP > 0): the replayed fn's own entry carries
its flag (set when its body was parsed or by the pair prescan). Check the two `?` arms that mark `_cur_fn_ix`
(`src/frontend/parse.cyr` statement `?`, `src/frontend/parse_expr.cyr` expression `?`) for the same replay case.
Rows: the repro (7); the top-level bind; the warning gone; a replayed `?` inside the generic still propagating
correctly in its caller; the T5b store reporting one error.
