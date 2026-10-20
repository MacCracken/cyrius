# simd_valueform_no_avx_transition.sh axis 2a reads 27 ms / 18 ms (150 %) under host load and fails a check.sh run — OPEN

**Status:** 🟡 **OPEN** — seen 2026-10-19 on the 6.7.16 libfix lane (unit L3, branch l6716-libfix at 55a20ac20) in
the second of two full `sh scripts/check.sh` runs on the same tree, with the box's load average ~20 from other
sessions. The unit touches only cbt/, programs/, scripts/check.sh's registry and one new toolchain gate — nothing
this gate compiles (it includes only lib/simd.cyr and lib/syscalls.cyr).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 libfix lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; p16 lane, wave 3, unit PP4) — never 7.x.
**Severity:** Low — a gate flake: a full suite went red with no code change behind it; nothing a user meets. Same
class as the archived 2026-10-16-simd-valueform-axis2b-reads-100-percent-under-host-load.md (axis 2b, fixed in
6.7.14 by longer fixtures timed in microseconds); axis 2a kept its millisecond-scale fixtures.

## Reproduction

`sh scripts/check.sh` on a box under external load (load average 17-27 on 16 CPUs, other sessions' work):

```text
FAIL simd_valueform_no_avx_transition axis2a: _ptr chain 27ms vs dispatch-free reference 18ms (150%, bound 135%).
  A per-call simd_has_avx2() dispatch is back in the fixed-lane _ptr wrappers (that cost ~25% from v6.5.24 to .61).
```

The gate rerun alone three times right after, load average ~20: run 1 FAIL again (the same axis), runs 2 and 3
PASS — `_ptr 26ms/24ms (108%)` and `_ptr 31ms/34ms (91%)`. The same tree's first full run passed it.

## Root cause

Axis 2a times two 500,000-iteration fixtures (a 6-link `f64v4_add_ptr` chain against a dispatch-free reference)
with `best` in whole milliseconds; each runs ~15-35 ms, so a few milliseconds of preemption on either side moves
the ratio by tens of percent, past the 135 % bound that sits between the honest ~100 % and the per-call-dispatch
mutant's ~160 %. `# check: serial` keeps check.sh's own pool off it but not other processes on the box.

## Fix direction

As 6.7.14 did for axis 2b: more passes per fixture (so each runs well past 100 ms), timed in microseconds, best of
5, and a named `too-fast` refusal; re-measure the dispatch mutant against the new bound so the axis still fires
for its own target (the file's header records why the chain depth is load-bearing).
