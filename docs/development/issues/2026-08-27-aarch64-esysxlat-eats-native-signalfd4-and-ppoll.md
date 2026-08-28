# ESYSXLAT's ELF-aarch64 compat rows for x86 `73`/`74` also swallow the NATIVE aarch64 `ppoll`/`signalfd4` the stdlib emits — `sys_signalfd` issues `fsync`, `sys_pause` issues `flock`

**Status:** 🟡 **OPEN** — newly filed. Verified against live code at 6.5.35 on 2026-08-27 by reading the emitted rows in `src/backend/aarch64/emit.cyr` and by running a stdlib-only repro under `qemu-aarch64 -strace`. **No consumer-side workaround exists** — that is established below by experiment, not assumed.
**Placement:** unpinned — 6.x-line backlog, but see [Severity rationale](#severity-rationale); this one blocks a consumer's entire aarch64 target.
**Discovered:** 2026-08-27 during kybernet's P(-1) audit (kybernet v1.6.13, CRITICAL-1 / MEDIUM-9).
**Severity:** **Critical** for any consumer that uses `signalfd` or `pause` on aarch64; the affected consumer's aarch64 binary is 100% non-functional and every gate was green.
**Affects:** cycc 6.5.35 (observed). **Not bisected.** The `74→82` row is dated v6.2.14 in its own comment and the `73→32` row references an `io.tcyr` fix, so the collision has likely existed since those landed; I did not establish the range.
**Reporter:** kybernet (consumer, PID 1 init for AGNOS). Pinned to cycc **6.5.35** along with the rest of the AGNOS pack front.
**Related:** [`2026-08-23-darshana-aarch64-syscall-shadow-no-diagnostic.md`](./2026-08-23-darshana-aarch64-syscall-shadow-no-diagnostic.md) — same table, **opposite direction**, and that issue's central assumption is what fails here. It states the ELF-aarch64 arm passes unmatched numbers through and that "native aarch64 numbers must pass through untouched". For `73` and `74` they do not: they are *matched*, as x86 numbers, and rewritten.

## Summary

`lib/syscalls_aarch64_linux.cyr` defines **two constants with the value 74** and
relies on ESYSXLAT treating them differently, which it cannot:

| line | constant | meaning of the number | expects |
|---|---|---|---|
| `:54` | `SYS_FSYNC = 74` | the **x86_64** number, written deliberately | to be translated `74 → 82` |
| `:184` | `SYS_SIGNALFD4 = 74` | the **native aarch64** number | to pass through untouched |

ESYSXLAT sees `x8 = 74` and always takes the first branch, so **`sys_signalfd()`
issues `fsync(2)`**. The same shape hits `73`:

| line | constant | meaning | expects |
|---|---|---|---|
| `:111` | `SYS_PPOLL = 73` (commented "→ sys_pause") | native aarch64 | passthrough |
| — | ESYSXLAT row `flock 73→32` | the x86_64 number | translation |

so **`sys_pause()` issues `flock(2)` and returns immediately** instead of blocking.

Both are plain stdlib wrappers. **No consumer code, no shadowing, no hardcoded
number is involved** — which is what separates this from the 2026-08-23 issue.
The build is clean: no warning of any kind, on either arch.

## Reproduction

Repro file: [`repros/2026-08-27-aarch64-esysxlat-eats-native-73-74.cyr`](./repros/2026-08-27-aarch64-esysxlat-eats-native-73-74.cyr)
`cyrius.cyml` needs only `[deps] stdlib = ["syscalls"]`.

```sh
cyrius build --aarch64 src/repro.cyr build/r-a64
qemu-aarch64 -strace build/r-a64
```

Observed on 6.5.35 (trimmed to the syscalls at issue):

```
fsync(-1) = -1 errno=9 (Bad file descriptor)      <- this is sys_signalfd()
epoll_create1(524288) = 3                          <- control: correct
flock(0,0,0,0,0,0) = -1 errno=22 (EINVAL)          <- this is sys_pause()
write(1,...)pause: RETURNED (emitted flock)        <- pause(2) must never return here
```

The **x86_64 build of the same file** is correct on both: `signalfd: OK`, and
`pause` blocks (the process has to be killed by a timeout). So there is nothing
arch-conditional in the repro — the difference is entirely the emitted number.

### Scope: exactly two wrappers, not a general breakage

To bound the blast radius rather than guess at it, all **34** `sys_*` wrappers
kybernet reaches were swept under `qemu-aarch64 -strace`. **Exactly two are
wrong**; the other 32 are correct, including every one that legitimately *renames*
(`rmdir→unlinkat`, `epoll_wait→epoll_pwait`, `open→openat`, `dup2→dup3`,
`pipe→pipe2`, `mkdir→mkdirat`, `access→faccessat`, `waitpid→wait4`). The x86_64
control run is clean on all 34. This is a narrow collision, not a broken table.

## Root cause

Both rows are in the ELF-aarch64 arm of `fn ESYSXLAT` (`src/backend/aarch64/emit.cyr`),
and each is individually correct and well-commented; the defect is that neither
can know what the `74`/`73` in `x8` *meant*.

**`:1125`** — `EW(S, 0xF101291F); EW(S, 0x54000041); EW(S, 0xD2800A48);  # fsync 74→82`

Its own comment states the premise: *"lib/syscalls_aarch64_linux.cyr emits the x86
numbers (74/75) — the aarch64-native 82/83 collide (82 is x86 rename, remapped
82→128 above)"*. True for fsync. But `SYS_SIGNALFD4` in that same file is `74`
as a **native** number, and this row eats it.

**`:1033`** — `EW(S, 0xF101251F); EW(S, 0x54000041); EW(S, 0xD2800408);  # flock 73→32`

Its comment already shows the ordering hazard was understood: *"MUST stay BEFORE
the poll→ppoll block below, which sets x8=73 — placing this after it would
re-catch a remapped poll(73) and wrongly turn it into flock(32)."* That ordering
protects a **remapped** `poll`. It does not protect a **direct** `syscall(SYS_PPOLL, …)`,
which is what `sys_pause()` on aarch64 is (`syscalls_aarch64_linux.cyr:688`) — it
arrives at the top of the chain with `x8 = 73` and is turned into `flock(32)`,
precisely the outcome the comment says must not happen.

The general shape: the ELF-aarch64 arm is a **flat rewrite over a value**, but the
value's provenance ("this is an x86 number awaiting translation" vs "this is a
native number awaiting passthrough") is exactly what distinguishes the two cases,
and it is lost by the time `x8` is compared.

## ⚠ There is NO consumer-side workaround — checked, not assumed

This is the material difference from the 2026-08-23 issue, where deleting a local
`var` fixes it. Every avenue was tried on 6.5.35:

| attempt | result |
|---|---|
| `syscall(74, …)` — literal native number | `fsync` — rewritten |
| `syscall(289, …)` — the **x86_64** signalfd4 number, hoping for a reverse map | `Unknown syscall 289` — no row, passed through raw |
| `syscall(271, …)` — the x86_64 `ppoll` number | `process_vm_writev` — no row; 271 is that syscall natively |
| value in a **global** `var`, read with `load64` | `fsync` — still rewritten |
| value **computed at runtime** (`opaque(70) + opaque(4)`) | `fsync` — still rewritten |

The last two are the important ones: **the rewrite happens at runtime**, in the
emitted compare-and-branch chain, so a literal, a global and a computed value are
all treated identically. A consumer cannot route around it by obscuring the
number, and cannot reach `signalfd4`/`ppoll` by supplying the x86 number either,
because those have no rows. On aarch64 these two syscalls are currently
**unreachable from Cyrius source**.

## Consequence for the reporting consumer

kybernet is PID 1. `setup_signals()` calls `sys_signalfd`, gets `-EBADF`, and
`main.cyr` takes its phase-4 FATAL arm: `do_shutdown(SHUTDOWN_POWEROFF)` then
`sys_pause()` then `return 1`. So an aarch64 board:

1. powers itself off during boot, before config load, before any service; and
2. if the poweroff did not land, `sys_pause()` — the deliberate "halt forever"
   backstop that exists to stop PID 1 ever returning — **returns immediately**,
   making `return 1` reachable. An init that exits is `Attempted to kill init`, a
   kernel panic.

The published `kybernet-<tag>-aarch64-linux` artifact was 100% non-functional for
ten releases while every gate was green, because nothing in the release pipeline
ever *executed* aarch64 code — the cross-build exiting 0 was the whole evidence
base. kybernet has since added a `qemu-user` execution gate and made its release
refuse to publish an aarch64 binary that fails a boot-critical syscall probe, so
the consumer side is contained; the syscalls themselves cannot be fixed there.

## Proposed fix

Ranked by my confidence, not preference. I do not know the backend well enough to
prescribe, so **(A) is what I would ask for**; (B) and (C) are surfaced.

**A. Give the two native constants private aliases in the ≥1000 band, and add
passthrough rows.** This is the mechanism the tree already uses for exactly this
collision class — `SYS_CHDIR = 1049` and `SYS_FCHOWNAT = 1054` are both present in
the emitted chain. Concretely: `SYS_SIGNALFD4 = 1074` with a row `1074 → 74`, and
`SYS_PPOLL = 1073` with `1073 → 73`, placed after the existing `73`/`74` rows so
neither re-catches. Confined to `lib/syscalls_aarch64_linux.cyr` plus two rows;
no change to how any x86 number is treated; and it keeps the "stdlib values are
arch-aware, consumers should not hardcode" contract the 2026-08-23 issue relies on.

**B. Make the fsync/flock rows use private aliases instead, freeing 73/74 for
passthrough.** The mirror image of (A): `SYS_FSYNC = 1082` / row `1082 → 82`, and
likewise for flock, so the native numbers pass through as the 2026-08-23 issue
says they should. Cleaner in principle — the invariant becomes "every x86-sourced
number in the aarch64 stdlib is ≥1000" — but it touches more existing rows and I
cannot see all the callers, so more risk.

**C. A build-time diagnostic when a stdlib `SysNr` value collides with an existing
ESYSXLAT source row.** This is (A)'s safety net rather than a fix, and it is
checkable entirely within the compiler: the table is a compile-time constant and
so are the enum values. It would have caught both of these at the moment
`SYS_SIGNALFD4 = 74` was written. Complements proposal (A) in the 2026-08-23
issue, which escalates *consumer* shadowing; this escalates the same conflict
inside the stdlib itself.

⚠ **What will not work:** blanket-ENOSYS'ing unmatched numbers, for the reason the
2026-08-23 issue already gives — unrouted is the normal case on ELF aarch64.
Nothing here changes that.

## Prevalence

Any consumer calling `sys_signalfd` or `sys_pause` on aarch64. Both are
foundational for a long-lived process: `signalfd` is the standard way to take
signals on an epoll reactor, and `pause` is the standard "stop here forever".
The other 32 wrappers kybernet exercises are unaffected, so this is unlikely to
be visible as a general "aarch64 is broken" symptom — it will present as one
specific subsystem inexplicably failing, which is how it presented here (a board
that mounted filesystems, set up the console, enabled cgroup controllers and then
powered off).

A scan for other native aarch64 constants whose value collides with an ESYSXLAT
source row would be worth running; I checked only the 34 wrappers one consumer
reaches, and I did not audit the table exhaustively.

## Severity rationale

Filed **Critical** rather than High on three grounds, with the counter-argument
stated so triage can weigh it:

1. **No workaround exists.** The 2026-08-23 issue is Medium explicitly because
   "delete the line" fixes it. Here the defect is in the stdlib's own values, the
   rewrite is at runtime, and both the native and x86 numbers are unusable — the
   table above records five failed attempts. A consumer cannot ship around this.
2. **Silent.** No warning on either arch. The duplicate-value collision is between
   two constants in one stdlib file, so not even the duplicate-symbol diagnostic
   from the 2026-08-23 issue fires.
3. **The failure is total for the affected target**, and lands in the least
   recoverable process on the machine.

Counter-argument for High instead: the affected surface is two syscalls, the
consumer population on aarch64 is small, and it is caught immediately by anything
that *executes* aarch64 code — which arguably makes it a gate gap on the consumer
side as much as a compiler bug. kybernet has closed that gap on its own side
regardless.
