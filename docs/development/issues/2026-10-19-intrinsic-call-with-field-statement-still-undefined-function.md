# `mulh64(2, 3).n = 5;` / `sizeof(H).n;` as a statement still registers an undefined fn ("undefined function 'mulh64'", `sizeof(H)` "undefined variable 'H'") beside its "expected ';', got '.'" — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 frontend lane (unit F1) implementing D11
(issues/2026-10-18-intrinsic-as-bare-statement-is-undefined-function.md: `mulh64(a, b);` / `sizeof(T);` alone are now
one error at the name). A `.` after the call is not D11's shape ("a statement that is only `mulh64(2, 3);`"), so
`_stmt_intrinsic` stands down there and the call statement's field arm (`_stmt_call_field`) keeps 6.7.15's behaviour.
Measured on the slot-open compiler (480de63eb's build/cycc) and the lane head e27dea14d (x86_64; the frontend, every
target): identical.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Low — refused either way (rc 1, the first error names the real mistake); the undefined-function lines and
`sizeof`'s "undefined variable 'H'" are invented.
**Kind:** bug (diagnostics).

## Reproduction

```cyrius
struct H { n; m; }
fn go(): i64 { mulh64(2, 3).n = 5; return 0; }
syscall(60, go());
```

```
error:<source>:2:28: expected ';', got '.'
warning: undefined function 'mulh64'
warning: undefined function 'mulh64' (reachable call site)
error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)
```

`mulh64(2, 3).n;` the same. `sizeof(H).n = 5;` / `sizeof(H).n;`: "2:24 undefined variable 'H'", "2:25 expected ';', got
'.'", then the same undefined-function lines for `sizeof`.

tests/gates/frontend/call_ptr_field_store.sh's U14 control ("an intrinsic lowered by name is no undefined fn") passes
on this output: it greps only `^error` lines for "undefined function 'mulh64'", and the name appears on `warning:` lines
(the `error: refusing to emit binary` line does not name it) — a check that shares the defect reads green.

## Root cause

`_stmt_call_field` (src/frontend/parse.cyr, the call statement's `.field` / `.m()` arm) parses the callee through the
ordinary call path, which registers a fn under the intrinsic's name (a forward reference that never resolves); for
`sizeof` the type argument is read as an expression. The value position (`var x = mulh64(2, 3).n;`) lowers the
intrinsic by name and says only "expected ';', got '.'" (U15).

## Direction (not decided here)

Lower the intrinsic by name in the field arm too (as PARSE_FACTOR does), so the statement is its one "expected ';',
got '.'" error; tighten U14 to read `warning:` lines as well.
