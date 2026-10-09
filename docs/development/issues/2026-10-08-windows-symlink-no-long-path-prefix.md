# Windows `sys_symlink` widens at 519 units with no `\\?\` prefix: a path over 260 units fails -1 — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b by reading `lib/syscalls_windows.cyr:721-768`
(no `\\?\` handling, no absolutisation, both paths capped at 519 units). Not re-verified on hardware (needs cass).
**Placement:** unpinned — 6.x-line backlog — never 7.x.
**Discovered:** 6.6.11, when `_win_widen` stopped CUTTING `sys_symlink`'s paths at 518 units and started refusing
them (CHANGELOG [6.6.11]); the residual over-MAX_PATH limit was carried in roadmap.md; filed 2026-10-08 from
roadmap.md.
**Severity:** Low — it fails honestly (-1), never links the wrong path; only long paths are affected.
**Affects:** cycc 6.6.9 (`sys_symlink` real on Windows) – 6.7.6.

## Summary

`open()` and `access()` on Windows reach long paths: their reroutes widen in the emitter and make a path of 248+
units absolute and `\\?\`-prefixed (`lib/syscalls_windows.cyr:573-577`, CHANGELOG [6.6.12]). `sys_symlink` widens
both of its paths itself with `_win_widen(…, 519)` and hands them to `CreateSymbolicLinkW` (reroute 0xF03E) as-is,
so on a Windows without process-wide long-path support a link path or target over MAX_PATH (260 units) fails -1,
and anything of 519+ units is refused before the call. The same long path works through `open()`.

## Reproduction

On cass (Developer Mode on, or elevated), from a PE build:

```
# a directory chain whose full path is ~300 units
var long = "C:\\cyrius-tests\\aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\…\\link";   # > 260 units
var rc = sys_symlink("target.txt", long);
```

Expected: 0 (the link is created, as `open(long, O_CREAT…)` creates the file). Actual (by code reading): -1.
Not run 2026-10-08 — needs cass.

## Root cause

`lib/syscalls_windows.cyr:722-723`: `var wl[1040]; var wt[1040];`, and `:725-726` `_win_widen(&wl, linkpath, 519)` /
`_win_widen(&wt, target, 519)`; `:765-766` pass `&wl` / `&wt` straight to `syscall(61502, …)`. No `\\?\` prefix and
no conversion to an absolute path (a `\\?\` path must be absolute and backslash-separated). The kind probe at
`:761` goes through the narrow GetFileAttributesW reroute, which already handles long paths.

## Proposed fix

Either move the widening into the 0xF03E reroute (take narrow paths, as 0xF019 has since 6.6.12) or do here what
that reroute does, for the LINK path: when it is 248+ units, make it absolute
(GetFullPathNameW semantics, `/` → `\`) and prefix `\\?\`, widening into a buffer sized for 32,767 units (heap, not
the 1,040-byte stack arrays). The TARGET is stored in the link verbatim and resolved later relative to the link, so
it must NOT be rewritten to absolute; only a target that is already absolute may take the prefix. Add a
`tests/tcyr/crossos/` row creating and reading back a > 260-unit link (runs on cass; SKIP-by-name where link
creation is not permitted).
