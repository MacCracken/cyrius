# `[embed]` / `${file:}` link race on Windows and Apple Silicon (the E-S3 residual) — OPEN

**Status:** 🟡 **OPEN** — verified 2026-10-08 against 6.7.6 @ 2fb6ad8b by reading the live code: `_embed_open` walks
the path with `openat` only where `walk == 1`; on `CYRIUS_TARGET_WIN` the walk is not compiled and on macOS arm64
`walk = 0`, so both open the whole path with `O_NOFOLLOW` (last component only). The arm64-Mach-O `openat` route still
drops the dirfd. Not re-verified on hardware (needs cass and ecb); the race itself was never run.
**Placement:** Break 2 candidate — the user picks (roadmap.md § Break 2) — never 7.x.
**Discovered:** 6.6.19 (2026-10-06, E-S3 — the residual stated in its CHANGELOG entry and *Known / not fixed*); filed
2026-10-08 from roadmap.md.
**Severity:** Medium — the `[embed]` rule "no link anywhere on the path; an untrusted checkout must not ship
out-of-project bytes in a release binary" holds on Linux and x86 macOS and is a check-then-open race on two targets.
The window needs concurrent write access to the checkout during the build.
**Affects:** 6.6.19 (`[embed]`'s path rules) through 6.7.6, Windows (PE CLI) and macOS arm64 builds.

## Summary

`_proj_path_bad` checks every prefix of an `[embed]` (and `${file:}`) path for a link (`is_symlink`,
`cbt/manifest.cyr:917-929`), then `_proj_read` opens the file once (`_embed_open`, `:948`). On Linux and x86 macOS the
open walks the path from a handle on the project root — `openat(dirfd, component, O_DIRECTORY | O_NOFOLLOW)` per
directory, `O_NOFOLLOW` on the leaf (`:958-986`) — so a directory swapped for a link after the check fails the open.
Elsewhere:
1. **Windows**: the walk is inside `#ifndef CYRIUS_TARGET_WIN`; PE opens `file_open(path, O_RDONLY | O_NOFOLLOW)`
   (`:988`), and `O_NOFOLLOW` → `FILE_FLAG_OPEN_REPARSE_POINT` (`src/backend/x86/emit.cyr:3389-3409`) guards the last
   component only. A directory replaced by a junction between the check and the open is followed.
2. **macOS arm64**: `walk = 0` (`cbt/manifest.cyr:952-957`) because the stdlib's `SYS_OPENAT` 56 is rerouted to BSD
   `open(5)` with an argument shift that DROPS the dirfd (`src/backend/aarch64/emit.cyr:900-901`,
   `_esx_arm_shift(S, 56, 5, 3)`); a straight row to Darwin `openat` would break every other open (Linux `AT_FDCWD`
   −100 ≠ Darwin −2, per the 6.6.19 entry).

## Reproduction

Not run — it needs a second writer racing the build on cass (a junction) or ecb (a symlink). The shape: a project
with `[embed] DATA = "assets/blob.bin"`; between `_proj_path_bad` and `_embed_open`, replace `assets/` with a
junction / symlink to a directory outside the project holding `blob.bin`. Expected: refused ("cannot be opened through
a link-free path"). Linux and x86 macOS refuse it (the walk); Windows and macOS arm64 open the outside file.

## Root cause

The two targets lack a dirfd-relative, no-follow open per component: PE has no `openat`, and the arm64 Mach-O
ESYSXLAT row for 56 discards the dirfd.

## Proposed fix

1. **PE**: after the whole-path open, `GetFinalPathNameByHandleW` on the opened handle (a new PE reroute) and require
   the final path to lie under the project root's own final path; refuse otherwise.
2. **macOS arm64**: a dirfd-preserving route for `openat` (Darwin `openat` = 463, with `AT_FDCWD` translated −100 →
   −2), then drop `walk = 0`; plus a `tests/tcyr/crossos/` companion for the new route (the rule for every new
   syscall route).
Both need cass / ecb at slot one.
