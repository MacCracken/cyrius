# dead_code_floor.sh axis 1 goes RED on the DCE byte scan's false-live: two unrelated globals flip `ir_emit1 cx` — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 by the 6.7.11 genfe lane gate (after the review fixes). Pre-existing:
the byte-scan design dates from v5.10.x; the floor gate from 6.6.20.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 genfe review) — never 7.x.
**Discovered:** 2026-10-14, the genfe lane's check.sh run after 783d795c (the pair-scan path fix).
**Severity:** Low — no miscompile (a false-live fn is only kept, never a live one dropped); the cost is a floor gate
that fails on a byte coincidence unrelated to the change, and a floor fixture edited to match noise.
**Affects:** tests/gates/codegen/dead_code_floor.sh with tests/fixtures/dead_code_floor.txt; the x86 fixup's DCE
call graph (src/backend/x86/fixup.cyr).

## Summary

cycc's DCE call graph is a byte scan: every `E8 rel32` whose target decodes to a fn start counts as a call, including
an E8 byte that sits inside an imm32 / disp32 (fixup.cyr: "False positives ... only OVER-estimate liveness, which is
SAFE for DCE"). Data addresses move whenever a global is added, so whether some reachable fn's immediate happens to
encode a call to a given dead fn depends on the global count. dead_code_floor.sh axis 1 fails when a floor entry
"stops being dead", so such a coincidence turns it RED.

## Reproduction

```sh
# from a tree at 09e06b72 (l6711-genfe), compiling the cx fork with that tree's build/cycc:
CYRIUS_DCE_VERBOSE=1 build/cycc < src/main_cx.cyr 2>&1 >/dev/null | grep -c 'dead: ir_emit1'    # 1
printf 'var _zz_g0 = 0;\nvar _zz_g1 = 0;\n' >> src/frontend/parse.cyr                          # two unused globals
CYRIUS_DCE_VERBOSE=1 build/cycc < src/main_cx.cyr 2>&1 >/dev/null | grep -c 'dead: ir_emit1'    # 0 — "live"
# one appended global: still 1. ir_emit1's only cx caller, _IR_REC1, stays dead throughout.
```

The genfe review fix 783d795c added two globals (`_tsp`, `_tsp_n`) and tripped exactly this; the lane dropped `cx` from
the fixture's `ir_emit1` row (1d04dd06), which a later unrelated global can flip back.

## Fix direction

Either make the floor gate's axis 1 tolerate an entry that went live only through the byte scan (cross-check a
"live" floor entry against a call-site census from the frontend — the fixup table plus ECALLTO targets — before
failing), or give the DCE call graph a precise edge set (record each emitted call's target at emission instead of
scanning bytes). Row: the reproduction above (two unused globals) leaves dead_code_floor green.
