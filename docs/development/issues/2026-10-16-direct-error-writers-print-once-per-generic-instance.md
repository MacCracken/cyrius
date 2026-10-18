# The error writers outside util.cyr's emitters still print once per generic instance: an arity error three times, a second subscript twice — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.14 generics lane (unit G5) on the lane's tree after the
per-instance error latch (the `_err_once` / `_err_dup` commit for issues/archived/2026-10-10-generic-body-errors-reported-per-instance.md),
x86_64; the same counts on the slot-open compiler.
**Placement:** 6.7.15 — repair 5 (generics lane; filed from the 6.7.14 generics lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-16, 6.7.14 generics G5. That issue's fix latches the plain emitters (src/common/util.cyr ERR,
ERR_EXPECT, ERR_IDENT, ERR_MSG, ERRDUPVAR) and the five undefined-name writers (now ERR_UNDEF); the frontend's other
direct writers (`syscall(SYS_WRITE, 2, "error:", 6)` followed by their own text — 61 on the lane tree: parse_fn.cyr
30, parse_decl.cyr 8, parse.cyr 7, parse_expr.cyr 7, parse_types.cyr 5, parse_ctrl.cyr 2, lex.cyr / lex_pp.cyr /
aarch64 emit.cyr 1 each) were outside its filed surface.
**Severity:** Low — every input is refused (rc 1, no binary); one defect reads as several lines.

## Reproduction

```cyrius
struct I { a; b; }
fn h(a): i64 { return a; }
fn g<T>(v: T): i64 { return h(1, 2); }
fn main(): i64 { var x = I { 1, 2 }; return g(1) + g(x); }
syscall(60, main());
```

```
error:<source>:3: 'h' expects 1 argument, got 2
error:<source>:3: 'h' expects 1 argument, got 2
error:<source>:3: 'h' expects 1 argument, got 2
```

(one is right; the base, the instance `g$I` and an inline replay each print it — the arity writer in
src/frontend/parse_fn.cyr, which has no panic latch by design: every bad call of a compile is reported.)

```cyrius
struct I { a; b; }
fn g<T>(v: T): i64 { var a: i64[2]; return a[0][1]; }
fn main(): i64 { var x = I { 1, 2 }; return g(1) + g(x); }
syscall(60, main());
```

```
error:<source>:2:48: a subscript's result is an element, not an array - a second [..] is not supported
error:<source>:2:48: a subscript's result is an element, not an array - a second [..] is not supported
```

(`_psub_err`, src/frontend/parse_expr.cyr.)

## Fix direction

Route each direct writer's head through the 6.7.14 latch — `if (_err_once(S, <identity>) == 0) { return ..; }` for
a writer that takes the panic latch, `_err_dup` (as ERR_UNDEF does) for one that does not, the identity being what
its text names — and keep a note it prints after the error behind `_err_quiet`. The frontend lane's
issues/archived/2026-10-14-private-call-reported-once-per-body-replay.md is one of these writers.
