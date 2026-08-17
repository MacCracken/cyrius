# Cross-OS full-corpus residuals: **ecb, ach and pi are at ZERO — only cass remains, at 7**

**Status:** 🟡 LARGELY SHIPPED — kept open as the gate for one decision, not as a bug.
**Placement:** **v6.5.25 — band D.** Take the `CYRIUS_CROSS_OS_FULL=1` decision AND close the cass residual in the same release.

> **⟳ Re-stamped 2026-08-14 at v6.5.21 (backlog re-triage).** ⭐ RE-MEASURED ALL FOUR HOSTS AT 6.5.21 ON THE FULL 271 CORPUS: **ecb 271/0 · ach 271/0 · pi 271/0**; cass carries the residual. Cost of flipping ecb/ach/pi to full corpus: **+547 s** per release gate. ⛔ The linkage to `2026-07-03-macos-threading-workers-dont-run` is REFUTED — ecb is 271/0, nothing is downstream of it.

> ## ✅ 2026-08-11 re-measurement, v6.5.19, all four hosts, real hardware: **ecb 0 · ach 0 · pi 0 · cass 7**
>
> **The title of this file was dead and has been rewritten.** ecb is not at 23, or 11, or 6 —
> it is at **ZERO**, and so are ach and pi. Measured with
> `CYRIUS_CROSS_OS_FULL=1 sh scripts/cross-os-selfhost.sh <host> crossos`, **one host at a
> time, sequentially** (fixed `/tmp` + remote paths clobber under concurrency):
>
> | host | result |
> |---|---|
> | **ecb** (macOS arm64) | `SELFHOST_OK` · corpus ALL 269 of 269 · **ran 269 passed, 0 failed** · `LIBTEST_OK` · EXIT=0 |
> | **ach** (Intel-Mac) | `SELFHOST_OK` · **ran 269 passed, 0 failed** · `LIBTEST_OK` · EXIT=0 |
> | **pi** (aarch64) | `SELFHOST_OK` · **ran 269 passed, 0 failed** · `LIBTEST_OK` · EXIT=0 |
> | **cass** (Windows PE) | `SELFHOST_OK` · **ran 262 passed, 7 failed** · 1 HANG at the 90 s timeout · `LIBTEST_FAIL` · EXIT=1 |
>
> The ecb leg was independently re-run a second time by the 2026-08-11 re-triage before this
> rewrite landed, and reproduced **269/0** exactly. state.md's standing instruction — "settle
> it with a real `CYRIUS_CROSS_OS_FULL=1` run on ecb before archiving, do NOT close it on the
> CHANGELOG line alone" — is hereby **answered**, and extended to all four hosts. The v6.5.18
> CHANGELOG's "267/0 on Linux, ecb and ach" was *not* the crossos subset as was suspected; it
> holds under a real full-corpus run. **pi had never been measured this way before** — this
> file's own "the pi leg is owed" is now discharged.
>
> ### The failure COMPOSITION changed, not just the count
>
> This file's central claim — a "**portable core** of 4 tests failing on EVERY non-x86-Linux
> host" — **is gone.** `include_quote_comment` and `preprocessor_past_cap` now pass everywhere
> (closed by the v6.5.11 tar packaging fix). What remains is **2 tests on 1 host**, plus a TLS
> cluster:
>
> ```
> capacity pair   large_input.tcyr   large_source.tcyr
> TLS cluster     tls12_handshake  tls12_handshake_msgs  tls_native_alpn
>                 tls_native_ed25519  tls_native_freestanding (HANG)
> ```
>
> Down from **31** measured 2026-08-07. The capacity pair is the **same shape that fails under
> `CYRIUS_IR=3`**, so this file's "cheapest thread to pull" correlation survives — on cass.
>
> ### ⚖️ MAINTAINER DECISION — the acceptance criterion is now met on 3 of 4 hosts
>
> This file's stated acceptance criterion is: *"when it reaches zero, flip
> `CYRIUS_CROSS_OS_FULL=1` to default and delete the env var."* That is now reachable for
> **ecb, ach and pi**. Two defensible calls, and it is the maintainer's:
>
> 1. **Flip full-corpus to default for ecb/ach/pi now**, hold the `crossos` selector for cass
>    until its 7 close. Gets three hosts' worth of coverage immediately and makes any future
>    regression on them a hard gate failure.
> 2. **Hold all four behind the cass 7**, flip once, keep the gate uniform across hosts.
>
> Option 1 buys coverage now; option 2 keeps one rule for all hosts. Either way the env var
> survives until cass is clean.
>
> ---
>
> ## 📉 (historical) v6.5.11 re-measurement on real ecb: **23 → 11 failures**
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

> ## 🔬 v6.5.15 re-measurement: still **11**, and the stated root cause is DISPROVEN
>
> `CYRIUS_CROSS_OS_FULL=1 sh scripts/cross-os-selfhost.sh ecb crossos` at v6.5.15:
> **`ran 252 passed, 11 failed`** of 263. The corpus grew 261 → 263 (two new cross-host tests,
> both passing), so **the failure count did not move: the same 11 tests, by name.**
>
> ⛔ **This release FIXED all ten macOS-arm64 constant divergences** (signals, errno, mmap flags —
> `2026-08-07-macos-arm64-inherits-linux-signal-and-errno-constants`, verified on real ecb and
> mutation-proven) **and it changed NOTHING here.** The paragraph above — *"these are almost
> entirely process/syscall surface, which is the macOS-arm64 constant-peer problem"* — was a
> plausible reading of the test NAMES, and it is wrong. Do not re-derive it.
>
> **What one of them actually is.** `stdlib/result_stdlib.tcyr` on ecb: `24 passed, 5 failed`,
> first failure `chain on /etc/hostname is Ok (got 0, expected 1)`. **macOS has no
> `/etc/hostname`** (confirmed on ecb; `/etc/hosts` exists and is the portable alternative).
> That is a TEST-FIXTURE portability defect — a Linux-only path hardcoded in a test — not a
> platform, constant, or codegen defect. The test is asserting the OS, not the language.
>
> **So the 11 are not one family.** At minimum they split into (a) tests hardcoding Linux-only
> paths/behaviour, which want fixing in the TEST, and (b) whatever genuinely needs platform work.
> Triage each against its actual output before assuming which. The remaining 10 have not been
> individually diagnosed at v6.5.15 — that is the next step, and it is cheap now that the corpus
> stages on ecb at `~/_cyaud` and a single test can be run there directly:
> `cd ~/_cyaud && cat tests/tcyr/<t>.tcyr | ./_co_m > /tmp/t && codesign -s - -f /tmp/t && /tmp/t`.
>
> ### All 11 diagnosed (v6.5.15) — FOUR causes, none of them the constant peer
>
> | # | test | actual failure | class |
> |---|---|---|---|
> | 1 | `stdlib/result_stdlib` | `chain on /etc/hostname is Ok` — **macOS has no `/etc/hostname`** | **TEST** hardcoded a Linux path — ✅ **FIXED v6.5.15**: writes its own `/tmp` fixture (the convention the bayan cases in the same file already used). Re-run on real ecb: **29/29**, was 24/5. |
> | 2 | `stdlib/result_stdlib_pass2` | `self uid is Ok` fails | **PLATFORM**, not test (corrected after probing ecb): `pwd_getpwuid_r` parses `/etc/passwd`, and macOS keeps real accounts in **Open Directory** — uid 501 is absent, the highest uid in that file is 441 (system accounts only). A `/etc/passwd` parser cannot resolve a normal macOS user; closing this means Directory Services integration. |
> | 3 | `platform/sys` | `sys_uname returns 0 (got -38)` — **-38 = ENOSYS**, `SYS_UNAME` has no Darwin mapping in ESYSXLAT | **PLATFORM** — unmapped syscall |
> | 4 | `platform/process` | `pipe read 4 (got -9)` — Darwin's `pipe()` returns **both fds in registers (rax/rdx)**, not through a caller buffer like Linux | **PLATFORM** — ABI shape differs |
> | 5 | `platform/process_exec_str` | captures 0 bytes | downstream of #4 |
> | 6 | `platform/process_run_capture_args` | captures 0 bytes | downstream of #4 |
> | 7 | `platform/sandbox_syscalls` | `sys_fchmod (got -9)` after the open fails; `prctl PR_GET_DUMPABLE` | **PLATFORM** — `prctl` is Linux-only |
> | 8 | `platform/socket_syscalls` | `AF_UNIX, SOCK_DGRAM\|SOCK_CLOEXEC` | **PLATFORM** — Darwin has no `SOCK_CLOEXEC` in the type field |
> | 9 | `platform/syscalls_at_family` | `sys_openat` / `sys_lstat` fail | **PLATFORM** — NOT `AT_FDCWD`; see below |
> | 10 | `platform/fdlopen` | `dl_setjmp` saves a zero rip/rsp; `dl_longjmp` returns | **PLATFORM** — hand-rolled setjmp asm |
> | 11 | `crypto/tls_native_freestanding` | **SIGSEGV (139)** at `mmap MAP_SHARED loopback region` | **PLATFORM** |
>
> ⚠ **`AT_FDCWD` IS NOT THE CAUSE OF #9, THOUGH IT LOOKS LIKE IT.** `syscalls_aarch64_linux.cyr`
> greps as `AT_FDCWD = -100` and the macOS peer never defines it, which reads exactly like the
> inherited-Linux-value bug. **Probed on real ecb: it compiles to `-2` (Darwin's value) and
> `openat(AT_FDCWD, "/etc/hosts", O_RDONLY)` returns a valid fd.** There is a `#ifdef` arm the
> grep does not resolve. This is the SECOND time this file's own warning has caught someone —
> resolve the preprocessor or probe the hardware; never grep a peer file for a value.
>
> ## ✅ v6.5.15 RESULT — 11 → 6 on real ecb (`ran 257 passed, 6 failed` of 263)
>
> Closed by the macho-ESYSXLAT gap fix: `platform/process`, `process_exec_str`,
> `process_run_capture_args`, `syscalls_at_family`, `sandbox_syscalls` (+ `result_stdlib`
> earlier). ⚠ A first full-corpus run reported `245 passed, 6 failed` but the gate's own
> honesty check fired — `ecb ran 251 test(s) but 263 were selected` (partial staging race).
> The re-run is complete at 263/263. **Quote the 257/6 run, not the 251 one.**
>
> ### ⭐ `crypto/tls_native_scaffold` newly RED — a de-masking, not a regression
> It is a pre-existing test that was NOT in the failing 11, and it now fails. It is not a
> regression: both its OpenSSL-interop blocks are gated on
> `if (sys_access("/usr/bin/openssl", 0) == 0)`, and **`sys_access` returned -22 on every
> macOS call** until this release (the wrapper passed 3 args; Darwin's `faccessat` takes 4
> and validates the flags word off the stale register). The guard was therefore permanently
> false and the whole block **never executed** — a vacuous pass. Fixing the wrapper made the
> dormant body run, and the real failures surfaced.
> ⚠ Before chasing them as TLS bugs: ecb ships **LibreSSL 3.3.6**, not OpenSSL. The
> assertions expect OpenSSL `s_client` behaviour (TLS 1.3 handshake, `negotiated TLS 1.2`
> = 771), so triage test-portability FIRST. Same accidental-skip shape as v6.5.11's
> `MAP_ANONYMOUS`, where a wrong constant was the safety net hiding a missing backend.
>
> **Remaining 6:** `tls_native_freestanding`, `tls_native_scaffold`, `fdlopen`,
> `socket_syscalls`, `sys`, `result_stdlib_pass2`.
>
> **Consequence for the flip-to-default question:** **10 of 11 are genuine macOS platform gaps**
> (unmapped `uname`, Darwin's register-returning `pipe`, Linux-only `prctl`/`SOCK_CLOEXEC`, the
> setjmp asm, an mmap segfault, `/etc/passwd`-only pwd) and exactly **1 was a Linux assumption
> baked into a TEST** — now fixed, leaving **10**. They are independent: no single fix moves more
> than the three `pipe`-dependent ones together, so this is an arc, not a patch.

*(Historical header, superseded by the 2026-08-11 measurement at the top of this file. Retained
for the audit trail; the live Status/Placement are the ones in the header block above. ⚠ Every
`vr01_` reference and line number below is stale — the selector became the `tests/tcyr/crossos`
**directory** at v6.5.11, and `release-gate.sh:115` now passes `crossos`.)*

**Status (2026-08-07, superseded):** 🟡 **OPEN — re-measured on REAL hardware, all four hosts.** The original
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
**Placement (2026-08-07, superseded):** unpinned — 6.x-line, never 7.x. No dedicated slot in
`roadmap.md` at 6.5.10; the largest cluster is downstream of Slot 11 (macOS-arm64 concurrency,
`.39`), and the **pi** full-corpus leg is tracked as W1 item 7. Needs its own arc once those land.
⛔ **Refuted 2026-08-11:** ecb, ach AND pi are all at **269/0**, so nothing is downstream of
Slot 11 any more and this needs no arc — only the cass 7 and the default-flip decision remain.
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
