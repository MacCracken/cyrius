# A generic multi-value fn's wrong-count `return` is refused once per instance, each line naming its mangled instance (`'gr$P' returns 2 values - return (a, b)`) — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GS-17, `f5fc13aae`, and GS-18 `b667c0c69` — no decision needed (diagnostics only). Inside an instance the refusal names the base generic (`_mret_fn`), and the instance judges the statement as the base does, decided per statement by a report counter (`_err_n`); `_inst_base_fi` is put back after a nested instance; a method is named as the source spells it, `'P.mv'` (GS-18). The filed program, verbatim, is refused once, `2:37: 'gr' returns 2 values - return (a, b)` (it printed a second line for `'gr$P'`); the comma form `return 1, 2;` at two struct instances is `expected ';', got ','` alone (three lines before); a stub base's instances give one `'gr'` line (they gave `'gr$P'` and `'gr$Q'`) — on x86_64, aarch64, cx and PE. Rows: `generic_body_error_once.sh` M1 (the filed program verbatim) – M9, MS1 / MS2; `destructure_one_value_refused.sh` `ret_method`. Mutants: the lane's previous compiler → RED 8 rows (M1 – M3, M5 – M9); MM1, MM2, MM3 each RED. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 generics lane (l6715-generics at d76d2e5cb, unit G6), x86_64
(the frontend: every target alike); the same on the lane's base compiler. Found while landing
issues/archived/2026-10-16-direct-error-writers-print-once-per-generic-instance.md (the per-instance latch for the parser's own
writers): this refusal goes through ERR_IDENT, whose 6.7.14 latch keys on the names it prints — and each instance
prints its own mangled name, so no two lines are one report.
**Placement:** 6.7.16 — Break 2, repair 6 (gensig lane, wave 2, unit GS5; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
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
