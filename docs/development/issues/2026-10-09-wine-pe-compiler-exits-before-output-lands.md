# Under wine, the PE compiler returns rc 3 at once with empty output; the full output lands later — OPEN

**Status:** 🟡 **OPEN** — reported 2026-10-09 by the 6.7.7 merge step (`wine cycc.exe < in > out` with a private prefix on this box); not investigated. The late output is byte-identical to `CYRIUS_TARGET_WIN=1`.
**Placement:** 6.7.11 — Break 2, repair 2 (roadmap.md § *The releases after 6.7.7*) (the Windows lanes; cass is the authority) — placed 2026-10-09 — never 7.x.
**Discovered:** the 6.7.7 merge step (out of scope); filed 2026-10-09.
**Severity:** Low — test-harness hazard: a check of rc or size straight after the call is misled
**Affects:** the PE compiler under wine (this box)

## Summary

`wine cycc.exe < in > out` (the compiler built from `main_win.cyr`) returns rc 3 immediately with stderr and `out`
empty; the output then arrives in full. Anything that reads rc or the file size right after the call — a gate, a
probe loop — sees a failure that is not one (or, worse, reads a half-written file).

## Proposed fix

Find whether it is wine's process model (a detached child) or the PE runtime's exit path; make the gates that drive
wine wait on the real process (`wineserver -w`) and assert the output's content, not rc alone.
