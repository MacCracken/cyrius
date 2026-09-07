# Mach-O structural lint — the surviving VR-04 residual

**Filed:** 2026-07-07 (extracted from the now-archived
[`2026-06-10-verification-coverage-gaps.md`](2026-06-10-verification-coverage-gaps.md)
so the deferral is a real issue, not CHANGELOG prose).
**Severity:** P3 — verification-bandwidth, not a correctness bug.
**Component:** `programs/checks/services.cyr` (`_binary_structural_lint_gate`).

## Context

The VR (verification-coverage) sweep from the 2026-06-10 deep-dive review closed
VR-01 (platform-variant tcyr + standing LIBTEST gate, v6.3.43), VR-02 (fuzz gate),
and VR-03 (differential corpus gate, `scripts/differential.sh`). VR-04 added
**ELF + PE** structural lint (`_lint_pe_buf`: MZ → `PE\0\0` → machine → PE32+ magic
→ section-table + each section's raw data in file bounds). The **Mach-O** arm was
deferred — CHANGELOG [6.3.43]: *"The Mach-O structural lint is deferred to the v6.4.x
Intel-Mac arc."* That deferral lived only in CHANGELOG prose; this issue makes it real.

## Problem

`_binary_structural_lint_gate` validates ELF and PE emitted binaries but does NOT
validate Mach-O. So a malformed Mach-O (bad magic / load-command / segment file-bounds)
emitted by the x86-macho or aarch64-macho backends would pass the structural gate —
exactly the "found by ports" class the gate exists to prevent, on the two Mach-O targets.

## Fix

Add `_lint_macho_buf` alongside `_lint_pe_buf`: MH_MAGIC_64 (`cffaedfe`) → cputype
(x86_64 `07000001` / arm64 `0c000001`) → `LC_SEGMENT_64` load-command walk → each
segment's `fileoff + filesize <= buf_len` and each section's raw data in file bounds.
Wire it into `_binary_structural_lint_gate`'s dispatch by output-format, and add a
gate assertion that a freshly cross-emitted Mach-O cycc passes.

## Roadmap home

Pinned to the **v6.4.x Intel-Mac (x86_64 Mach-O) toolchain tail — roadmap.md slot T**
(the arc that already owns the x86-macho packaging/lint residuals). Land it as a bite
inside that arc so the Mach-O lint ships with the rest of the macOS toolchain work.

## Acceptance

`_lint_macho_buf` validates both x86_64 and arm64 Mach-O; the structural-lint gate
rejects a corrupted Mach-O fixture and passes a real cross-emitted one; CHANGELOG's
"deferred to v6.4.x Intel-Mac arc" line is closed.

---

**RESOLVED — v6.4.59** (2026-07-12). `_lint_macho_buf` added to `programs/checks/services.cyr` (MH_MAGIC_64 + cputype + filetype + LC-table/LC_SEGMENT_64 file-range bounds + LC_UNIXTHREAD entry-in-executable), wired into `_binary_structural_lint_gate`'s 0xCF dispatch (was a skip), plus a Linux `_self_host_pipe_env(..., "CYRIUS_MACHO=1")` cross-emit leg so it runs without a macOS host. check.sh gate now reads "ELF + PE + Mach-O (cross-emit)". Part of the Intel-Mac revival arc — see CHANGELOG [6.4.59].
