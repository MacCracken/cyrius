# 2026-07-07 — cycc_cx (the cx bytecode compiler) doesn't run cross-native on macOS/Windows — RESOLVED

> **RESOLVED v6.4.22 — archived 2026-07-08.** Root cause: `main_cx.cyr`'s arena used
> `syscall(SYS_BRK,...)`, and neither XNU nor Win32 has `brk` (the 2 "not routed" warnings
> were the 2 brk calls). Fixed with flat per-target `#ifdef` blocks (mmap on macho flags
> `0x1002` / PE flags `0x22`, brk on Linux/agnos) — mirrors `main.cyr`/`main_win.cyr`.
> Verified on real hardware: native `cycc_cx` on **ecb** (macOS) + **cass** (Windows)
> compiles a `.cyr`→118 B `.cyx` that the native `cxvm` runs to exit 42 (was signal-12 on
> macOS). Re-added to all 3 tarball builders; a native compile→run round-trip is gated per
> host in `cross-os-selfhost.sh` (ecb/pi/cass). cycc byte-identical. See CHANGELOG [6.4.22].


**Status:** OPEN — filed during cx Release C (v6.4.20). NOT a Release C blocker;
Release C ships the portable-`.cyx` **runtime** (cxvm) cross-OS, which is the
actual deliverable. This tracks the separate "build `.cyx` natively on
macOS/Windows" convenience.

## Context

cx Release C made the portable-`.cyx` **runtime** (`cxvm`) work on all four
hosts (x86-Linux, aarch64/pi, macOS/ecb, Windows/cass — verified on real
hardware, both write+exit and full file open→read→write→close). `cxvm` now
ships in the macOS/Windows release tarballs so a binary-install user can
`cyrius run *.cyx`.

The portable-bytecode model is **build-once / run-anywhere**: you compile a
`.cyr` → `.cyx` with `cycc_cx` on any host where it runs (today: x86-Linux),
and the resulting portable `.cyx` runs on every host via the native `cxvm`. So
the cx **compiler** (`cycc_cx`) is NOT required on every host, and is
deliberately **not** shipped in the macOS/Windows tarballs.

## The bug

`cycc_cx` (source `src/main_cx.cyr`, a fork of `main.cyr`) cross-compiles to
Mach-O ARM64 and PE32+ **without error**, but the Mach-O build emits:

```
warning: syscall not routed by the Mach-O ARM translation (ESYSXLAT/__got);
         will fault on macOS. Add an ESYSXLAT entry or use a stdlib wrapper.   (×2)
```

and **faults at runtime on macOS** — verified on ecb: `cat x.cyr |
./cycc_cx_macho` returns **signal 12** (rc 140), 0-byte output. So a natively
cross-emitted `cycc_cx` is broken on macOS. Two syscalls in `main_cx.cyr` use
numbers `ESYSXLAT` (`src/backend/aarch64/emit.cyr`) doesn't renumber for XNU.
(By contrast `cxvm` itself emits **0** such warnings and runs clean — its I/O
syscalls are all routed.)

PE (Windows) `cycc_cx.exe` cross-compiles too but was **not** runtime-tested on
cass; it likely has an analogous `EPE_SYSCALL_DYNAMIC`/routing gap.

## Fix (when scheduled)

1. Find the 2 unrouted syscalls in `main_cx.cyr` (compare its syscall sites to
   `main_aarch64_macho.cyr`'s; the fork likely kept a raw Linux number a sibling
   fork already routes). Add `ESYSXLAT` entries **or** switch to a stdlib
   wrapper that is already routed.
2. Do the **same for PE** (`main_cx.cyr` → `cycc_cx.exe`), and runtime-verify on
   cass — do NOT ship half (macho-only) per "one bug ships complete."
3. Re-add `cycc_cx` to `build-macos-arm64-tarball.sh` /
   `build-macos-x86-tarball.sh` / `build-windows-tarball.sh` (the bin-build loop
   + the magic-validation loop — the exact lines this issue's release removed,
   grep `cx Release C: cxvm`).
4. Verify the NATIVE `cycc_cx` on each host compiles a `.cyr` → `.cyx` that the
   native `cxvm` runs (exit-code round-trip), and wire that into
   `cross-os-selfhost.sh` (a `cycc_cx` build-a-.cyx leg alongside the existing
   cxvm run-a-.cyx leg).

Any src/-side ESYSXLAT change re-triggers aarch64 self-host + `seed-derive`.

## Acceptance

Native `cycc_cx` on ecb/ach/cass compiles `fn main(){...}` → `.cyx` that the
native `cxvm` runs to the expected exit code; all three tarballs ship `cycc_cx`;
`cross-os-selfhost.sh` gates the compile-and-run round-trip per host.
