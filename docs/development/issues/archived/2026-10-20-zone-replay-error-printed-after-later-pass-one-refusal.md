# A declaration-zone initializer's error is printed after a LATER line's pass-1 refusal (`var p = g(1 2);` then `const X;` prints 3:8 before 2:13) — RESOLVED

> ✅ **RESOLVED in v6.7.17** (zr lane, unit ZR1, `e3d59ddc1` (P1a), `7785bfd3d` (P1b), `4fc427213` (P1c), `f22d4a2b3` (P2), met `a46882ed7`; no decision needed — diagnostic order): the parse's diagnostics print in SOURCE ORDER — every exit the parse can reach goes through one `_die`, the diagnostics from pass 1's start to the last parse's end (PARSE_PROG and the declaration-zone replay) are held as records and written stably sorted by their token's position, so the zone entry's error prints before a later pass-1 refusal; an exit or a vec abort mid-parse, and a compiler fault on Linux, write what is held first (macOS / Windows / cx under CYRIUS_DIAG_UNBUFFERED=1); the bytes are unchanged, only their order. The gates that pinned the old order were re-pinned to source order. Rows: dx_multi_error.sh ZO1-ZO10 (ZO1 the filed repro verbatim) on the x86_64, aarch64, cx and PE compilers. CHANGELOG [6.7.17])

**Status:** ✅ **RESOLVED in v6.7.17** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone at aa0d05620, x86_64; the shared
front end, every target) against the slot-open compiler (b73e8d5fe's build/cycc).
**Placement:** 6.7.17 — the cleanup of the remaining issues (zr lane, wave 3, unit ZR1; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Severity:** Low — a refused program's diagnostics out of source order; nothing that compiles changes.
**Kind:** bug (diagnostic order).
**Discovered:** by the 6.7.16 zone lane's review, checking issues/2026-10-18-zone-replay-reports-only-first-latched-
error.md's fix (7a4f9ecdf: EMIT_GVAR_INITS releases the panic latch at each replayed zone entry). Through b73e8d5fe
the second error was swallowed (one error printed); now both print, pass 1's first. Same class (pass 1 reports before
the replay), a different reporter: staged zone 2026-10-20-zone-sweep-reports-type-argument-refusal-out-of-source-
order.md (the zone sweep's `_gu_xlist`).

## Reproduction

```sh
printf 'fn g(): i64 { return 1; }\nvar p = g(1 2);\nconst X;\nvar q = 3;\nsyscall(60, 0);\n' | build/cycc > /dev/null; echo rc=$?
# lane (aa0d05620):
# error:<source>:3:8: expected '=', got ';'
# error:<source>:2:13: expected ')', got number 2
# rc=1
# b73e8d5fe:
# error:<source>:3:8: expected '=', got ';'                (2:13 swallowed)
```

The same lines after a first statement, or in a fn, print in source order on both compilers:

```sh
printf 'fn g(): i64 { return 1; }\nvar z = 1;\nz = 2;\nvar p = g(1 2);\nconst X;\nvar q = 3;\nsyscall(60, 0);\n' | build/cycc > /dev/null
# error:<source>:4:13: expected ')', got number 2
# error:<source>:5:8: expected '=', got ';'
printf 'fn g(): i64 { return 1; }\nfn f(): i64 { var p = g(1 2); return 0; }\nconst X;\nsyscall(60, f());\n' | build/cycc > /dev/null
# error:<source>:2:27: expected ')', got number 2
# error:<source>:3:8: expected '=', got ';'
```

## Root cause

A declaration-zone initializer is parsed only by the replay (EMIT_GVAR_INITS, src/frontend/parse_decl.cyr), which runs
after pass 1's top-level walk; `const X;` is refused BY pass 1 as it registers the const, so its error is printed
before any zone entry's, whichever line comes first. After the first statement both lines are parsed by PARSE_PROG in
order.

## Fix direction

Either defer pass 1's top-level refusals that sit below a zone entry until the replay reaches their line (pass 1
records the error and the replay — or PARSE_PROG — prints it at its place), or collect the zone's diagnostics and print
them sorted by position once the replay ends. Rows: the repro prints 2:13 then 3:8 (rc 1) on x86_64 / aarch64 / cx /
PE; one error per mistake kept (const_checked.sh M1, dx_multi_error.sh's K rows).
