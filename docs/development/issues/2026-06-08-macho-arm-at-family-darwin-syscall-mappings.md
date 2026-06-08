# macho-arm: POSIX *at()/stat/utimensat stdlib wrappers lack Darwin ESYSXLAT mappings

- **Filed**: 2026-06-08 (v6.1.3, surfaced by the POSIX `*at()` family slot)
- **Affects**: `src/backend/aarch64/emit.cyr` `ESYSXLAT` (the `_TARGET_MACHO == 2` branch), for native arm64-macOS (ecb) consumers of `lib/syscalls.cyr`.
- **Severity**: Medium / latent. **PRE-EXISTING for `sys_stat`** (broken on macho-arm before this slot — no Darwin `newfstatat` mapping). No in-tree consumer calls these on macОS today, so nothing regresses; the toolchain/compiler itself does not use them. arm64-macOS is the supported macOS target (x86-macOS HELD).

## Summary

v6.1.3 added the POSIX `*at()` family + bare-name peers (`sys_openat`/`mkdirat`/
`fstatat`/`unlinkat`/`linkat`/`renameat`/`fchmodat`/`utimensat`, `sys_link`/
`sys_lstat`/`sys_rename`) and fixed the **aarch64-Linux** ESYSXLAT collision
(newfstatat/utimensat now emit x86 262/280, renumbered to 79/88 — see
CHANGELOG [6.1.3]). On **macho-arm** (which reuses `syscalls_aarch64_linux.cyr`),
several of these emit syscall numbers the macho ESYSXLAT branch does not map:

| Wrapper | Emitted num | macho ESYSXLAT? | Status on macho-arm |
|---|---|---|---|
| `sys_openat` | 56 | 56→Darwin open (mapped) | ✅ works |
| `sys_mkdirat` | 34 | 34→mkdir (mapped) | ✅ works |
| `sys_unlinkat` | 35 | 35→unlink (mapped) | ✅ works |
| `sys_fchmodat` | 53 | 53→chmod (mapped) | ✅ works |
| `sys_fstatat`/`sys_lstat`/`sys_stat` | 262 | **none** | ❌ broken (pre-existing) |
| `sys_utimensat` | 280 | **none** | ❌ broken |
| `sys_linkat`/`sys_link` | 37 | **none** | ❌ broken |
| `sys_renameat`/`sys_rename` | 38 | **none** | ❌ broken (note: macho maps x86 rename 82→128, but the aarch64 stdlib now uses renameat 38) |

## Fix sketch (its own slot — needs ecb verification)

Add macho ESYSXLAT entries in the `_TARGET_MACHO == 2` branch:
- `262 → Darwin fstatat` (470) — pure renumber (arg layouts match).
- `38 → Darwin rename` (128) — or renameat if Darwin exposes it (Darwin renameatx = 488).
- `37 → Darwin link` (9) with the linkat→link arg-shift (drop dirfds), or linkat if available.
- `280 → utimensat`: **Darwin has no `utimensat` syscall.** Needs a real-binary
  decision on ecb — `setattrlist`/`setattrlistat`-based emulation, or leave
  `sys_utimensat` unsupported on macОS with a clear error. Design before coding.

Each entry must be llvm-mc/`-arch arm64`-verified and tested on **ecb** (run the
relevant `tests/tcyr/syscalls_at_family.tcyr` subset cross-emitted as Mach-O).

## Why not in v6.1.3

The v6.1.3 scope (user direction 2026-06-08) was the **aarch64-Linux ESYSXLAT
collision** — done + verified on real pi. The macho-arm Darwin surface is a
separate, larger area (Darwin lacks several at-family syscalls outright) and has
no current consumer. Filed so it isn't silently skipped.
