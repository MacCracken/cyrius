# Windows atomic-write residuals: file_create_exclusive O_EXCL→CREATE_NEW + on-failure temp unlink (DeleteFileW)

**Filed:** 2026-07-12 (v6.4.57 — surfaced verifying the portable atomic-write feature on Windows).
**Severity:** P3 (two Windows-only edge residuals; the core crash-safe write works everywhere).
**Component:** `src/backend/x86/emit.cyr` (EOPEN_PE), `lib/io.cyr` (xunlink / file_write_atomic).

## Context

v6.4.57 shipped portable `file_rename` / `file_write_atomic` / `file_create_exclusive`, with the
Windows rename via a new `MoveFileExW` reroute (0xF034). The crash-safe write itself works on
Windows. Two documented Windows residuals remain:

## Residual A — `file_create_exclusive` is not truly atomic on Windows

`file_create_exclusive(path, mode)` uses `O_CREAT | O_EXCL` (atomic no-clobber on Linux/macOS).
But `EOPEN_PE` (the Win64 open emitter) derives `dwCreationDisposition` from the `O_CREAT` bit only
(`OPEN_ALWAYS` = 4 / `OPEN_EXISTING` = 3) and **ignores `O_EXCL`** — so on Windows the call degrades
to an open-or-create with NO kernel-enforced exclusivity (a concurrent creator can win). Fix: map
`O_CREAT | O_EXCL` → `CREATE_NEW` (1) in EOPEN_PE (fails with ERROR_FILE_EXISTS if the target
exists), so `file_create_exclusive` is atomic on Windows too. Verify on real cass.

## Residual B — on-failure temp unlink is a no-op on Windows

`file_write_atomic` unlinks its `.cyrtmp.<pid>.<ctr>` temp on any write/close/rename failure via
`xunlink`, but `xunlink` returns `-1` without calling `DeleteFileW` on Windows (unwired, like
`xstat`/`xgetdents`). So a *failed* atomic write on Windows **leaks the temp file** (harmless — no
corruption, the original is intact — but litter). The success path is fine (`MoveFileExW` consumes
the temp). Fix: wire a `DeleteFileW` reroute + route `xunlink` through it on Windows.

## Also (inherent, not a bug)

AGNOS `file_create_exclusive` is a `file_exists` pre-check + plain create (non-atomic) because
AGNOS's `AO_*` syscall set has no exclusive-create bit — an inherent platform limitation, documented
in `lib/io.cyr`, not fixable without an AGNOS kernel `AO_EXCL`.

## Acceptance

- Windows `file_create_exclusive` fails on an existing path atomically (CREATE_NEW).
- A failed `file_write_atomic` on Windows leaves no temp file.
- Both verified on real cass.

---

**RESOLVED — v6.4.58** (2026-07-12). See CHANGELOG [6.4.58]. Verified: x86 self-host byte-identical + seed-derive, cross-OS self-host on ecb/cass/pi, and (for the cx items) the `_cx_v6458_modulo_immediate_gate` cxvm exit-code gate; (for the Windows items) `vr01_atomic_write.tcyr` 23/23 on real cass.
