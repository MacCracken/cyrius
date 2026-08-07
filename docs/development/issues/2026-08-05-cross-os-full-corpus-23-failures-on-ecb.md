# Cross-OS: the full tcyr corpus fails 23 of 258 on macOS-arm64 — first measurement

**Status:** 🟡 **OPEN** — filed 2026-08-05 from the v6.5.8 cross-OS widening work; the mechanism
re-verified against live code on **6.5.10**, 2026-08-07. Still opt-in, still the glob by default:
`scripts/release-gate.sh:110` runs `cross-os-selfhost.sh "$H" "vr01_"` inside `for H in ecb ach cass
pi` (`:108`), and `cross-os-selfhost.sh:321` clears the glob only when `CYRIUS_CROSS_OS_FULL=1`.
⚠ **The two counts in the table below have both moved and are NOT re-measured here** — at 6.5.10
the corpus is **260** tcyr and the `vr01_` glob selects **36**, so the gate's blind region is
**224 unrun on every gated host**, not 224 of 258. The `235 pass / 23 fail` figure is a **6.5.8
measurement on ecb and has not been re-run since**; treat it as a floor-of-record, not a current
number. ⚠ `scripts/release-gate.sh:107` also still says the ach vr01 leg "fires its VR-01 libtest
(25 tests)" — that comment is stale too; the glob is 36.
**Placement:** unpinned — 6.x-line, never 7.x. No dedicated slot in `roadmap.md` at 6.5.10; the
largest cluster is downstream of Slot 11 (macOS-arm64 concurrency, `.39`), and the **pi**
full-corpus leg is tracked as W1 item 7. Needs its own arc once those land.
**Severity:** Medium — nothing regressed; this is **previously-unmeasured** territory now measured.
**Affects:** measured on cycc 6.5.8. Reproduce with `CYRIUS_CROSS_OS_FULL=1 sh scripts/cross-os-selfhost.sh ecb x`.

## What changed, and why this is newly answerable

Before v6.5.8 the cross-OS leg ran the `vr01_` glob only — **34 of 258** tcyr — and printed a
bare `LIBTEST_OK: <host>` with no numerator, denominator, or the word "subset", so a gate
covering 13 % of the corpus read as authoritative. It also opened a **fresh SSH connection per
test** (~1.8 s of handshake on cass, ~0.9 s on pi), which is what made a wider corpus look
unaffordable — the connections were the cost, not the tests.

v6.5.8 batched the loop into one ssh per host and made the report state its own coverage.
A full-corpus run then costs **75 s on ecb**, which is affordable. So for the first time
there is a number for the blind region:

| | at filing (6.5.8) | live 2026-08-07 (6.5.10) |
|---|---|---|
| corpus | **258** tcyr | **260** (`ls tests/tcyr/*.tcyr \| wc -l`) |
| run by the gate today | **34** (`vr01_*`) | **36** (`ls tests/tcyr/vr01_*.tcyr \| wc -l`) |
| full-corpus result on ecb | **235 pass / 23 fail** | **not re-measured** — needs a run on real ecb |

The two new corpus files and the two new `vr01_` files landed in .9/.10; whether either changes the
23 is unknown until someone re-runs it on ecb.

## The 23

  - `alloc_thread_safe.tcyr`
  - `atomics.tcyr`
  - `fdlopen.tcyr`
  - `include_quote_comment.tcyr`
  - `integration_closures_threads.tcyr`
  - `large_input.tcyr`
  - `large_source.tcyr`
  - `preprocessor_past_cap.tcyr`
  - `process.tcyr`
  - `process_exec_str.tcyr`
  - `process_run_capture_args.tcyr`
  - `result_stdlib.tcyr`
  - `result_stdlib_pass2.tcyr`
  - `sandbox_syscalls.tcyr`
  - `socket_syscalls.tcyr`
  - `sys.tcyr`
  - `syscalls_at_family.tcyr`
  - `thread_join_single_load.tcyr`
  - `thread_local.tcyr`
  - `thread_safety.tcyr`
  - `threads.tcyr`
  - `tls_native_freestanding.tcyr`
  - `unicode_normconf.tcyr`

## Why the default is still the glob

Flipping to full corpus today would wedge **every** release behind these 23, and they are not
regressions — they are pre-existing platform gaps in territory the gate never covered. The
largest cluster (`threads`, `thread_safety`, `thread_local`, `alloc_thread_safe`,
`integration_closures_threads`, `thread_join_single_load`, `tls_native_freestanding`) is
downstream of the already-open
[`2026-07-03-macos-threading-workers-dont-run`](2026-07-03-macos-threading-workers-dont-run.md):
there is no `lib/thread_macos.cyr` and no `bsdthread_*`/`__ulock_*` call anywhere in `lib/`,
so `thread_create` returns a null handle and no worker ever runs. A second cluster
(`process`, `process_exec_str`, `process_run_capture_args`) is fork/exec, and a third
(`socket_syscalls`, `sandbox_syscalls`, `syscalls_at_family`) is syscall-surface coverage.

So the widening shipped as **opt-in** — `CYRIUS_CROSS_OS_FULL=1` — with the glob's coverage
now printed on every run so the subset can no longer be mistaken for the whole. That is the
part that was a defect. Closing the 23 is a separate arc.

## Acceptance

- **Re-measure on ecb first.** The 23 is a 6.5.8 number and v6.5.7/.8 landed macOS-relevant fixes
  that plausibly touch the list — `link(86)` and `chdir` unmapped on macOS-x86, `symlinkat(36)` /
  `readlinkat(78)` unrouted on Mach-O ARM, `xrmdir` broken on macOS-arm64 since v6.5.2, the Darwin
  `AT_*` flag divergence, and the macOS-x86 `Stat` enum (all CHANGELOG [6.5.7], "found by ports").
  `sys.tcyr`, `syscalls_at_family.tcyr` and `process*.tcyr` are the candidates. **Do not size the
  arc off the stale 23.**
- Triage whatever the re-measurement gives into clusters and confirm each root cause (do not assume
  the threading issue explains all of them — three clusters are visible and at least six files were
  unclassified at filing).
- As each cluster closes, the count drops; when it reaches zero, make
  `CYRIUS_CROSS_OS_FULL=1` the default and delete the env var.
- ach/cass/pi have **not** been measured this way — ecb is the only host with a number, and it is a
  6.5.8 one. The **pi** leg is tracked separately as `roadmap.md` W1 item 7. Do those before sizing
  the arc.
