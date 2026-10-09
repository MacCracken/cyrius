# A constant `if` condition is tested at run time and its dead arm is emitted (DEAD-10) — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b with
`repros/2026-10-08-constant-if-arms-not-folded.cyr`: `if (SYS_OPEN == 2)` on an enum constant compiles to
`mov eax,2; push; mov eax,2; cmp; sete; test; je` plus the whole dead 5-argument `openat` arm, and the dead arm's
string is in the image. `const C = 2; if (C == 2)` and a bare `const C = 0; if (C)` are not folded either.
**Placement:** unpinned — 6.x-line backlog (roadmap.md § Potential backlog → *Size and platform internals*) — never 7.x.
**Discovered:** the 6.6.20 closeout planning (2026-10-07), deferred at planning as DEAD-10 (CHANGELOG [6.6.20]
*Known / not fixed*; REVBE-06's `#ifndef CYRIUS_TARGET_WIN` replaced the PE-warning symptom only); filed 2026-10-08
from roadmap.md.
**Severity:** Low — dead bytes and a compare per site; nothing wrong runs.
**Affects:** cycc ≤ 6.7.6, every backend.

## Summary

The compiler's own portability idiom `if (SYS_OPEN == 2) { open(path, …) } else { openat(-100, path, …) }` picks the
arm from an **enum constant** (`enum Sys { … SYS_OPEN = 2; … }` in each driver), so one arm is dead in every fork —
yet both arms and the compare are emitted. Live sites: **13** in `src/` (`grep -rn "if (SYS_OPEN == 2)" src/ | grep
-v ':\s*#'` — `src/main.cyr:777, 945`, `src/frontend/lex.cyr:470, 578, 775, 844, 874, 906`,
`src/backend/common/env.cyr:56`, `src/backend/common/runtime.cyr:217`, and one in each of `main_win.cyr:83`,
`main_aarch64.cyr:69`, `main_aarch64_native.cyr:75`); 10 of them are in `build/cycc`. The dead arm also reaches the
backend's diagnostics: the PE compiler's own build warned "syscall 2 with 4 argument(s) is not routed" four times
until 6.6.20 wrapped those arms in `#ifndef CYRIUS_TARGET_WIN`. 6.7.2's const evaluator (`_ce_*`) now gives the
parser the value of any constant expression, which makes the fold cheap.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
./build/cycc < docs/development/issues/repros/2026-10-08-constant-if-arms-not-folded.cyr > /tmp/d10 && chmod +x /tmp/d10
/tmp/d10; echo $?                              # 7 (correct result)
grep -a -c zzz-dead-arm-marker /tmp/d10        # 1 — the dead arm's string is in the image
objdump -d -M intel /tmp/d10 | grep -cE 'sete|syscall'   # the compare and BOTH arms' syscalls are there
```

Expected: no compare, no else arm, no marker string. Actual: all present.

## Root cause

`PARSE_IF` (`src/frontend/parse_ctrl.cyr:168`) always calls `ECOND(S)` and parses + emits both arms; nothing asks
whether the condition is a compile-time constant. The evaluator entry `_ce_eval_here`
(`src/frontend/parse_fn.cyr:7083`) reports a refusal on a non-constant expression, so it needs a non-reporting
"is this constant?" pre-check before `PARSE_IF` can use it.

## Proposed fix

In `PARSE_IF` (and `PARSE_ELIF`), when every atom of the condition is a literal, an enum constant, a `const` or a
const fn call, evaluate it with the `_ce_*` evaluator and emit only the taken arm; the dead arm is still PARSED (so
its syntax and scope errors stand) but emits nothing. ⚠ One behaviour question belongs to the user: today a call to
an undefined fn inside the dead arm is "a reachable undefined function" and the build is refused; if the dead arm
emits no call site, that program would start compiling. The default that keeps what compiles unchanged is to keep
counting the dead arm's references for that refusal. Gates: a probe like the repro carries no `sete` / dead string;
self-host and seed-derive (cybs compiles `src/`, and the fold changes `build/cycc`'s bytes); the PE compiler's build
stays warning-free with the REVBE-06 `#ifndef`s removed.
