# Cross-OS: the full tcyr corpus measured on ALL FOUR hosts — 5 portable failures, the rest are macOS-specific

> ## 📉 v6.5.11 re-measurement on real ecb: **23 → 11 failures**
>
> The headline number in this file is stale — v6.5.11 fixed two of its causes. Measured with
> `CYRIUS_CROSS_OS_FULL=1 sh scripts/cross-os-selfhost.sh ecb crossos` at v6.5.11:
> **`ran 250 passed, 11 failed`** of 261.
>
> | stage | failures | what closed |
> |---|:--:|---|
> | filed / 6.5.10 | **23** | — |
> | + tar packaging fix | **18** | 5 tests whose INPUTS were never shipped to the host — `programs/vidya.cyr` (3 tests), `tests/fixtures/`, `tests/data/`. A PACKAGING bug counted as platform failures. `cross-os-selfhost.sh:108` now ships them. |
> | + macOS serial threading | **11** | 7 concurrency tests — `concurrency/{atomics,integration_closures_threads,thread_join_single_load,thread_local,thread_safety,threads}`, `memory/alloc_thread_safe`. macOS now routes to `lib/thread_macos.cyr` and thread bodies actually run. |
>
> The arithmetic closes exactly: 23 − 5 − 7 = 11.
>
> ### The 11 that remain — one coherent family, not a grab-bag
>
> ```
> crypto/tls_native_freestanding   platform/sandbox_syscalls   stdlib/result_stdlib
> platform/fdlopen                 platform/socket_syscalls    stdlib/result_stdlib_pass2
> platform/process                 platform/sys
> platform/process_exec_str        platform/syscalls_at_family
> platform/process_run_capture_args
> ```
>
> These are almost entirely **process / syscall surface**, which is the macOS-arm64 constant-peer
> problem: `lib/syscalls.cyr:69` imports `syscalls_aarch64_linux.cyr` on Darwin-arm64, and
> `ESYSXLAT` renumbers SYSCALLS but never VALUES. Tracked at
> [`2026-08-07-macos-arm64-inherits-linux-signal-and-errno-constants`](2026-08-07-macos-arm64-inherits-linux-signal-and-errno-constants.md).
> ⚠ That is the same "macOS tool-surface follow-up" `lib/syscalls.cyr:61` claims to track — and
> which never existed as a file, partly because its own reference contains a Cyrillic `О`.
>
> **Bearing on the flip-to-default question this issue exists to answer:** the blocker is now 11,
> not 23, and it is one root cause rather than several. The pi full-corpus leg (W1 item 7's second
> half) is still owed.

**Status:** 🟡 **OPEN — re-measured 2026-08-07 on REAL hardware, all four hosts.** The original
filing had one host and carried an explicit "ach/cass/pi have NOT been measured this way yet".
They have now. The result decomposes the problem in a way one host could not.
**Originally filed as:** filed 2026-08-05 from the v6.5.8 cross-OS widening work; the mechanism
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


## ⭐ Measured 2026-08-07 on real hardware — ALL FOUR hosts, full 260-file corpus

`CYRIUS_CROSS_OS_FULL=1 sh scripts/cross-os-selfhost.sh <host> vr01_`, one host at a time.

| host | | pass | fail |
|---|---|---|---|
| **pi** | Linux aarch64 | **255** | **5** |
| **ecb** | macOS arm64 | 237 | 23 |
| **ach** | macOS x86_64 (Intel) | 233 | 27 |
| **cass** | Windows PE | 229 | 31 (1 a genuine HANG) |

### A. The portable core — 4 tests fail on EVERY non-x86-Linux host

    include_quote_comment · large_input · large_source · preprocessor_past_cap

Nothing to do with Darwin, threading, or PE. ⚠ **Three of the four —
`large_input`, `large_source`, `preprocessor_past_cap` — are the SAME three that fail to
COMPILE under `CYRIUS_IR=3`** (measured the same day over the same corpus). All three are
capacity tests. That correlation is the cheapest thread to pull in this whole issue, and it
suggests a shared limit rather than four unrelated platform bugs.

(`unicode_normconf` fails on pi/ecb/ach but PASSES on cass, so it is not part of the core.)

### B. Per-platform clusters, once the core is subtracted

- **pi — 5 total, i.e. core + 1.** By far the cleanest non-x86 target. Linux aarch64 is
  effectively at parity; the earlier framing of this issue as "cross-OS rot" does not fit it.
- **ecb — 18 beyond the core.** Threading (`threads`, `thread_safety`, `thread_local`,
  `alloc_thread_safe`, `integration_closures_threads`, `thread_join_single_load`,
  `tls_native_freestanding`), process/exec (`process`, `process_exec_str`,
  `process_run_capture_args`), and a syscall-surface tail (`socket_syscalls`,
  `sandbox_syscalls`, `syscalls_at_family`, `sys`, `fdlopen`, `atomics`, `result_stdlib`,
  `result_stdlib_pass2`). Most are downstream of the open
  [`2026-07-03-macos-threading-workers-dont-run`](2026-07-03-macos-threading-workers-dont-run.md).
- **ach — 4 more than ecb, and they are a TIMING/CLOCK cluster the arm64 Mac does not have**:
  `bench_elapsed`, `chrono`, `clock_monotonic`, `fsync` (plus `sakshi_full`,
  `tls_native_realpeer`, `tls_native_scaffold`). Entirely invisible while only ecb was measured.
- **cass — 31, and mostly the expected POSIX surface**: TLS (`tls12_handshake*`,
  `tls_native_*`), fs/process (`fs`, `io`, `pwd_grp`, `shadow_pam`, `process`, `fsync`),
  sockets (`socket_syscalls`, `net_v6_connect`), plus a few language-level ones worth a look
  on their own (`defer`, `slices_indexing`, `expr_in_fn_args`, `flags`, `cyml`, `protobuf`).

## ⛔ The measurement was blocked by a harness bug, now fixed

The cass leg could not produce a number at all, for two independent reasons — both fixed at
v6.5.10 in `scripts/cross-os-selfhost.sh`:

1. **It was FAIL-FAST while every other host accumulated.** It exited at failure #1, so a
   full-corpus run reported "5 passed" and stopped. That is not a measurement.
2. **⚠ No per-test timeout on the remote command.** `ConnectTimeout` covers connection SETUP
   only. `tls_native_freestanding.tcyr` held a single ssh open for **33 minutes** with zero
   output before it was killed by hand, and the orphaned `_lt.exe` then held a file lock that
   made the NEXT run's `rmdir`/`mkdir` setup fail. Remote calls are now `timeout 90`-wrapped,
   a timeout COUNTS as a failure (a hang is a result, not a reason to abort), and progress
   prints every 25 tests — the silence is what made the hang look like ordinary slowness.

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
