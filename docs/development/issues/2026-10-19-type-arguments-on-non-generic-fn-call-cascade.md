# `f<i64>(2, 3)` on a NON-generic fn (or an intrinsic) is three errors that never say so — the `<` read as a comparison — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 frontend lane (unit F1) while measuring the D11 intrinsic
statement refusal (issues/2026-10-18-intrinsic-as-bare-statement-is-undefined-function.md, whose `IDENT (` arm this
shape never reaches). Measured on the slot-open compiler (480de63eb's build/cycc) and on the lane head 814a8fb36
(x86_64; the frontend, every target): identical. Not the type-position shape of
issues/2026-10-18-non-generic-type-arguments-unrefused-in-remaining-positions.md (`Pt<i64>` as a TYPE, 6.7.15's D6 /
6.7.16's D7): this is a CALL with explicit type arguments.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF6) — never 7.x.
**Severity:** Low — refused (rc 1), but none of the three errors names the mistake, two are invented.
**Kind:** bug (diagnostics).

## Reproduction

```cyrius
fn f(a, b): i64 { return a + b; }
fn go(): i64 { f<i64>(2, 3); return 0; }
syscall(60, go());
```

```
$ build/cycc < eg1.cyr > /dev/null
error:<source>:2:17: expected '=', got '<'
error:<source>:2:21: undefined variable 'i64' (missing include or enum?)
error:<source>:2:28: undefined variable 'f'
```

As a value, `var x = f<i64>(2, 3);`: "undefined variable 'f'", "undefined variable 'i64'", "expected ';', got '>'".
With an intrinsic, `mulh64<i64>(2, 3);`: the same three (…, "undefined variable 'mulh64'"); `var x = mulh64<i64>(2,
3);`: "expected '(', got '<'" + "undefined variable 'i64'".

## Root cause

`_stmt_explicit_generic` (src/frontend/parse.cyr) takes `NAME<..>(` only when NAME is a generic fn; for any other
callee it returns 0 and the `IDENT` statement arm falls to the assignment path ("expected '='"), whose expression then
reads `<i64>(2, 3)` as comparisons of undefined names. The factor does the same in a value.

## Direction (not decided here)

One error at the name — e.g. "'f' is not generic - it takes no type arguments" — with the `<..>` and the call stepped
in sync, in statement and value position, for a plain fn, a method and an intrinsic. Whether the call is then
compiled without its type arguments or refused is a language question for the user.
