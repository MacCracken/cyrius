# The x86-macOS peer `lib/syscalls_macos.cyr` declares `SYS_ACCEPT4 = 288`, which no macOS path emits — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the quick lane's bite 4; CHANGELOG [6.7.9]) Option (b), the decision (user, 2026-10-11):
> the name is KEPT, and the peer now says why — a comment at the declaration (Darwin has no accept4; `sys_accept4`
> composes accept 43 → BSD 30 + fcntl under `#ifdef CYRIUS_TARGET_MACOS`, so 288 is never emitted; kept for portable
> source) and a header paragraph, NAMES WITH NO ROUTE, for the whole class (declared for portable source, never emitted
> by the stdlib, a raw use warns at compile time and is SIGSYS / -78 at run time, each reason in the route gate's
> allow-list). The class had two worse members the filing missed: `SYS_WAITID = 247` and `SYS_SET_TID_ADDRESS = 218`
> had no route, no issuer and no reason anywhere — both now carry one. `platform/macho_route_parity.sh` axis 4: every
> name the x86-macOS peer declares with no EMACHO_SYSXLAT row carries an allow-list reason (floor 40) —
> RED before (WAITID, SET_TID_ADDRESS), green after; the ACCEPT4 reason, which named `lib/net.cyr`, now names
> `sys_accept4`. Nothing that compiles changes: an x86-macOS build naming all three is byte-identical before / after.

**Status:** ✅ **RESOLVED in v6.7.9** (option b, comment-only; see the banner). Was 🟡 OPEN — re-verified
2026-10-08 against 6.7.6 @ 2fb6ad8b by grep: the only reader of `SYS_ACCEPT4` in `lib/` is the
`#ifndef CYRIUS_TARGET_MACOS` arm of `sys_accept4` (`lib/syscalls_linux_common.cyr:1279-1281`); the macOS arm
composes `accept` (43 → BSD 30) + fcntl. The x86 Mach-O EMACHO_SYSXLAT has no 288 row. Not re-run on hardware (needs
ach) — nothing executes it.
**Placement:** 6.7.9 — the repair batch, the quick-fix lane (user, 2026-10-11) — never 7.x.
**Discovered:** before 2026-10-08 (carried in roadmap.md's backlog as cosmetic); filed 2026-10-08 from roadmap.md.
**Severity:** Low — cosmetic; a raw `syscall(SYS_ACCEPT4, …)` on x86-macOS fails closed with -ENOSYS (see below).
**Affects:** cycc ≤ 6.7.6.

## Summary

The x86-macOS peer (`lib/syscalls.cyr:64-67` includes it for `CYRIUS_TARGET_MACOS` + `CYRIUS_ARCH_X86`) keeps the
Linux number `SYS_ACCEPT4 = 288` (`lib/syscalls_macos.cyr:133`) although Darwin has no
accept4 and the stdlib never issues it there: `sys_accept4` builds the call from accept + `fd_set_nonblocking` /
`F_SETFD` under `#ifdef CYRIUS_TARGET_MACOS` (`lib/syscalls_linux_common.cyr:1262-1282`, CHANGELOG [6.6.8]). The
name only matters to user code that writes `syscall(SYS_ACCEPT4, …)` itself, and there it buys nothing: 288 has no
EMACHO_SYSXLAT row, so the x86 Mach-O chain tail (`_msx_tail`, `src/backend/x86/emit.cyr`, CHANGELOG [6.6.8])
rewrites it to Unix-class nosys and it returns -78. (arm64-macOS includes `lib/syscalls_aarch64_linux.cyr`
instead, `lib/syscalls.cyr:68-70`, where `SYS_ACCEPT4 = 242` is the real aarch64-Linux number — not this item.)
`tests/gates/platform/macho_route_parity.sh:68` allow-lists `SYS_ACCEPT4` for both Macs as "Darwin has no accept4".

## Reproduction

```sh
grep -rn "SYS_ACCEPT4" lib/ src/ | grep -v "syscalls_x86_64_linux\|syscalls_aarch64_linux"
# lib/syscalls_macos.cyr:133:    SYS_ACCEPT4 = 288;
# lib/syscalls_linux_common.cyr:1280:    return syscall(SYS_ACCEPT4, fd, srcaddr, srcaddrlen, flags);   (#ifndef CYRIUS_TARGET_MACOS)
# src/common/syscall_xlat.cyr:108:    if (n == 288) { return "SYS_ACCEPT4"; }   (a Linux name table)
```

Expected: a macOS peer declares only numbers some macOS path issues (or says why it keeps one). Actual: a dead
Linux number with no comment.

## Root cause

Speculation: the variant came with the rest of the Linux-numbered socket block (`lib/syscalls_macos.cyr:121-133`)
and was never pruned once `sys_accept4` gained its Darwin composition.

## Proposed fix

Two options — **the user's call**, because (a) changes what compiles:

- (a) Delete the variant (the `macho_route_parity.sh` row stays: the arm64 peer still declares the name; re-check
  the row's `both` scope against the gate's axes). Portable user code that names `SYS_ACCEPT4` would stop compiling for
  x86-macOS ("undefined variable") — Windows and agnos already do not declare it.
- (b) Keep it and add a one-line comment at `lib/syscalls_macos.cyr:133`: kept so portable source naming it
  compiles; never emitted by the stdlib on macOS; a raw use returns -ENOSYS.
