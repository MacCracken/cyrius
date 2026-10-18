# `_win_widen` / `_win_widen_n` in lib/syscalls_windows.cyr have no caller left — RESOLVED

> ✅ **RESOLVED in v6.7.14** (PL-7, `e359d2b43` (the user's decision D56, 2026-10-16: "Remove both"): `_win_widen` and `_win_widen_n` and their two comment blocks are deleted from `lib/syscalls_windows.cyr` (76 lines). The two comments that cited the old decoder (`src/backend/x86/emit.cyr`'s `_pe_wp_slashes`, `pe_open_posix_semantics.sh`'s header) now say "the stdlib's former `_win_widen_n`, removed 6.7.14". The repro's grep now finds only those two comments. A PE stdlib hello's dead-code note drops by the two fns: 280 → 278 unreachable fns, 85,515 → 83,676 B, and hello.exe 108,544 → 106,496 B, printing `hello` under wine. cycc_win.exe is byte-identical (2,450,944 B; its wine self-host byte-identical), and seed-derive is OK. Rows: `tcyr_corpus_cross_compiles.sh` (628 files, PE allowlist 0); `removed_symbol_census.sh` (0 removed: the names are private); `pe_open_posix_semantics.sh` (54 native / 58 PE path rows under wine). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — found by the 6.7.12 windows lane (W2, 1a7aa2ff) and its review (2026-10-15). Kept by the
lane: removing a stdlib fn changes what compiles for anyone calling it, which is the user's call.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (platform lane, wave 1, unit P3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D56 — Remove both.
**Severity:** Low — dead code (input for the closeout's dead-code pass); no behaviour is wrong.
**Affects:** `lib/syscalls_windows.cyr` `_win_widen_n` (:647) and `_win_widen` (:703), and the comment above them.

## Summary

`sys_symlink` was the last caller. Since 1a7aa2ff the CreateSymbolicLinkW reroute (0xF03E) takes NARROW UTF-8 paths and
the emitter widens them (`ESYMLINKW_PE`, `_pe_widen_path` / `_pe_wp_target`), as every other path reroute has since
6.6.11 / 6.6.12. Nothing in the tree calls either helper now, and the comment above `_win_widen_n` ("It is the ONE
stdlib decoder, behind `_win_widen` below … the one decoder lives here for the other modules to call") describes a
role nothing uses.

## Reproduction

```
$ grep -rn "_win_widen" --include='*.cyr' --include='*.tcyr' --include='*.sh' . | grep -v '^./build'
lib/syscalls_windows.cyr:643:# stdlib decoder, behind `_win_widen` below. No path reroute takes a wide path any more: the
lib/syscalls_windows.cyr:647:fn _win_widen_n(dst, src, n, cap): i64 {
lib/syscalls_windows.cyr:698:# `_win_widen_n`. Returns the unit count, or -1 when the path does not fit or is not valid
lib/syscalls_windows.cyr:703:fn _win_widen(dst, src, cap): i64 {
lib/syscalls_windows.cyr:709:    return _win_widen_n(dst, src, n, cap);
src/backend/x86/emit.cyr:3329:# not read '/' as a separator (the stdlib's `_win_widen_n` made the same swap before 6.7.12).
tests/gates/platform/pe_open_posix_semantics.sh:75:# … The stdlib's own widens (`_win_widen_n`) decode the same way and are
```

Both are underscore-private (not in `docs/api-surface.snapshot`), so removal does not touch the public surface or
`removed_symbol_census`; a consumer could still call them by name.

## Fix

The user's call: remove both (and repoint the two comments that cite `_win_widen_n` as the old decoder), or keep them
with the comment rewritten to say they are unused. Either way the closeout's dead-code floor records the result.
