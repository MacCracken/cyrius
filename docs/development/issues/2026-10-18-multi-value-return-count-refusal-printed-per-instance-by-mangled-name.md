# A generic multi-value fn's wrong-count `return` is refused once per instance, each line naming its mangled instance (`'gr$P' returns 2 values - return (a, b)`) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 generics lane (l6715-generics at d76d2e5cb, unit G6), x86_64
(the frontend: every target alike); the same on the lane's base compiler. Found while landing
issues/2026-10-16-direct-error-writers-print-once-per-generic-instance.md (the per-instance latch for the parser's own
writers): this refusal goes through ERR_IDENT, whose 6.7.14 latch keys on the names it prints — and each instance
prints its own mangled name, so no two lines are one report.
**Placement:** unplaced — filed from the 6.7.15 generics lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Low — every input is refused (rc 1, no binary); one mistake reads as one line per instance, under a
name the source never wrote.
**Kind:** bug (diagnostic).

## Reproduction

```cyrius
struct P { a; b; }
fn gr<T>(x: T): (i64, i64) { return 1; }
fn run(): i64 { var u = P { 1, 2 }; var a, b = gr(1); var c, d = gr(u); return a; }
syscall(60, run());
```

```
error:<source>:2:37: 'gr' returns 2 values - return (a, b)
    ...
error:<source>:2:37: 'gr$P' returns 2 values - return (a, b)
    ...
```

One line naming `gr` is right. The same body with `return 1, 2;` (the comma form) gives three lines for one mistake,
and two different texts: the base `expected ';', got ','` at 2:38, then `'gr$P' returns 2 values - return (a, b)` and
`'gr$Q' ...` at 2:37 for two struct instances (the base parse reports the comma first; an instance, parsed with
`_had_error` already set, takes `_mret_ret_check`'s other arm). A non-generic `fn gr(x): (i64, i64) { return 1, 2; }`
prints the one `expected ';'` line.

## Root cause

`_mret_ret_err` (src/frontend/parse_fn.cyr) names `L64(_fnt_names + _cur_fn_ix * 8)` — inside an instance, the
instance's `gr$P` — through ERR_IDENT, whose identity includes that name; and `_mret_ret_check` reports through
`_mret_ret_err` only once `_had_error` is set, so the base and its instances take different arms for one statement.

## Fix direction

Name the base generic (the instance's base, its name cut at `$`, or the source spelling) and key the report on the
base's name, so every parse of the body is one report; and make the base and an instance judge `return 1, 2;` alike.
Rows in tests/gates/frontend/generic_body_error_once.sh: `return 1;` in a 2-value generic at two instances, one line
naming `gr`; the comma form, one line.
