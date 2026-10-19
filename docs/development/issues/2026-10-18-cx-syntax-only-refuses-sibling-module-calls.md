# The cx compiler under `--syntax-only` refuses every call to a fn this file does not define ("undefined function(s) called (cx backend)") — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S6) while adding the --syntax-only rows of
issues/2026-10-17-syntax-only-sibling-ptr-call-field-store-false-temporary.md. Pre-existing (the lane head's cx compiler
gives the same lines). Measured on the cx compiler built from the lane tree (`src/main_cx.cyr`).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — no tool runs the cx compiler with `--syntax-only` today (`cyrius lint` runs cycc); the flag's
contract (the guide: "`cyrius lint` (`--syntax-only`) accepts a file that calls a sibling module's fn by name") does
not hold on that compiler.
**Kind:** tooling (--syntax-only, cx).

## Repro

```cyrius
struct H { n; m; }
fn go(): i64 { gp().n = 5; var i = 0; for (i = 0; i < 3; gp().n += 1) { i = i + 1; } return 0; }
```

`gp` lives in a sibling module. `cycc --syntax-only` (x86_64), the aarch64 compiler and `CYRIUS_TARGET_WIN=1 cycc
--syntax-only`: rc 0, `warning: undefined function 'gp'` only. The cx compiler (`cat src/main_cx.cyr | cycc > cc_cx;
cc_cx --syntax-only < r.cyr`):

```
warning: undefined function 'gp'
error: undefined function(s) called (cx backend):
  - gp
  - gp
  refusing to emit .cyx — an unresolved call patches a garbage offset and restarts the program.
```

rc 1. (`gp` is also listed once per call site, where the native forks name a fn once.)

## Root cause

src/main_cx.cyr's post-parse undefined-call walk (`cx_undef`, "cx has no `--allow-undef` ... so this is
unconditional") runs whatever `_syntax_only` says; under `--syntax-only` no `.cyx` is wanted, so the refusal guards
nothing there.

## Proposed fix

Skip the `cx_undef` walk (or keep it a warning) under `_syntax_only`, as the native forks leave a sibling's fn a
warning; a row in a --syntax-only gate on the cx compiler.
