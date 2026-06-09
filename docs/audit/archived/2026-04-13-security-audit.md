# Cyrius Security Audit — 2026-04-13

> **ARCHIVED — baseline audit, superseded.** The P0s (CVE-01/02/03) + CVE-05
> (.65 tok_names mangle-path guard) + CVE-06 + CVE-07 (PIE, v6.1.6/.8) + CVE-08
> (.41) all shipped; the P2/P3 tail (CVE-09…13) is tracked as roadmap items or
> accepted design constraints. Kept as the security baseline of record — the next
> full audit (per CLAUDE.md "Security Audit Process") supersedes it. Archived
> 2026-06-09 (v6.1.18 doc sweep).

**Auditor:** Claude (Opus 4.6)
**Version:** cc3 4.2.1 (312,152 bytes)
**Scope:** Compiler (cc3), build tool (cyrius), stdlib, bootstrap chain
**Methodology:** Static source analysis + architectural review

---

## Critical (P0) — Fix in 4.2.x

### CVE-01: Command injection via `sys_system()` in dep resolver

**File:** `programs/cyrius.cyr:335`
**Vector:** The `sys_system(cmd)` function passes user-controlled strings to `/bin/sh -c`. The dep resolver constructs git clone commands from `cyrius.toml` fields (`git`, `tag`) without sanitization. A malicious `cyrius.toml` could inject shell commands:

```toml
[deps.evil]
git = "https://example.com/repo; rm -rf /"
tag = "1.0"
```

**Impact:** Arbitrary code execution during `cyrius deps` or `cyrius build`.
**Fix:** Validate git URLs (reject `;`, `|`, `$`, backticks). Or replace `sys_system` with direct `execve` of git with argv (no shell interpretation).
**Priority:** P0 — every `cyrius deps` with untrusted toml is vulnerable.

### CVE-02: Path traversal in include directives

**File:** `src/frontend/lex.cyr:1184`
**Vector:** `include "../../../etc/passwd"` is processed without path validation. The preprocessor reads any file accessible to the compiler process.
**Impact:** Information disclosure. In CI environments, could read secrets, env files, SSH keys.
**Fix:** Restrict includes to CWD subtree. Reject paths containing `..` or absolute paths starting with `/`. Allow explicit override with `--allow-absolute-includes`.
**Priority:** P0 — every compilation with untrusted source is vulnerable.

### CVE-03: Include-once table silent overflow

**File:** `src/frontend/lex.cyr:373`
**Vector:** `PP_MARK_INCLUDED` silently returns if count >= 64. The 65th unique include is NOT recorded, so subsequent `include "same_file"` directives will re-include it, leading to duplicate symbol definitions and unpredictable behavior.
**Impact:** Compilation corruption in large projects. kybernet has 42 deps — approaching the limit.
**Fix:** Error on overflow (not silent return). Expand table to 256 entries.
**Priority:** P0 — silent corruption in production builds.

---

## High (P1) — Fix in 4.2.x

### CVE-04: Unvalidated dep file writes

**File:** `programs/cyrius.cyr:787`
**Vector:** `_dep_copy_file(src, dst)` writes to `dst` without validating the path. A `cyrius.toml` with crafted module paths could write outside `lib/`:

```toml
[deps.evil]
modules = ["../../.ssh/authorized_keys"]
```

**Impact:** Arbitrary file overwrite during `cyrius deps`.
**Fix:** Validate that all dep destinations are within `lib/` directory. Reject paths containing `..`.
**Priority:** P1 — requires malicious cyrius.toml.

### CVE-05: Heap region overlap — no guard pages

**File:** `src/main.cyr` heap map
**Vector:** All compiler state lives in a single contiguous BRK region with no guard pages. A buffer overflow in one region (e.g., string data overflowing into the token array) corrupts adjacent data silently. The layout-dependent Heisenbug (libro PatraStore) may be this class of bug.
**Impact:** Silent data corruption, unpredictable codegen, potential code execution.
**Fix:** Add overflow checks at write boundaries for critical regions (str_data, tok_names, codebuf). Long-term: mmap separate regions with guard pages.
**Priority:** P1 — the Heisenbug may be a manifestation.
**Shipped v5.11.65** (2026-05-19) — split forward from .68 once the audit at slot entry confirmed the bulk of CVE-05's surface was already covered by earlier work (CVE-06 for str_data write-boundary, `EB()` for codebuf append on both arches, `NPOS_GUARD`/`LEXID` for the tok_names lex hot path). The remaining gap was tok_names mangle-path byte-copy loops where `NPOS_GUARD(S, 256)` was a magic-pessimistic budget that an over-long source identifier could exceed. v5.11.65 replaced each magic-256 with a `compute-source-length → NPOS_GUARD(S, actual_len + …)` shape across 11 sites (parse_decl.cyr `BUILD_METHOD_NAME`, parse_expr.cyr `BUILD_OP_NAME`, parse_fn.cyr `PARSE_FN_DEF` module-mangle, parse_types.cyr × 2 variant-ctor sites, main.cyr / main_aarch64.cyr / main_aarch64_macho.cyr / main_aarch64_native.cyr / main_cx.cyr / main_win.cyr use-alias mangle); the 4 non-x86 main_*.cyr variants had no prior tok_names guard at all on the use-alias path. `programs/check.cyr::_cve05_guard_gate` locks the magic-256 pattern out of every mangle-path source file (check.sh 75 → 76). Patch-path codebuf writes in `src/backend/*/fixup.cyr` + `src/backend/*/jump.cyr` are safe by construction — they target previously-`EB`-validated offsets. Long-term `mmap`-with-guard-pages remains tracked for v6.x heap-layout work.

### CVE-06: String data region overflow

**File:** `src/frontend/lex.cyr:1940`
**Vector:** String data region is 256KB. String interning scans and writes to this region. If total string literal data exceeds 256KB, writes corrupt the next heap region (preprocess_out at 0x44A000). No bounds check on the write side — only the scan position is checked.
**Impact:** Heap corruption in string-heavy programs.
**Fix:** Add bounds check before every `store8` to str_data. Error on overflow.
**Priority:** P1 — triggered by large programs with many string literals.

---

## Medium (P2) — Fix in 4.3.x

### CVE-07: No ASLR / no PIE

**Vector:** All compiled binaries are non-PIE ELF executables with fixed load address (0x400000). No address space layout randomization.
**Impact:** Exploitable if a binary has a memory corruption bug — all addresses are predictable.
**Fix:** PIC codegen (planned for v4.4.0). Generate PIE binaries by default.
**Priority:** P2 — affects all compiled binaries.

### CVE-08: `rep movsb` / `rep stosb` direction flag

**File:** `lib/string.cyr:29,37`
**Vector:** `rep movsb` and `rep stosb` depend on the direction flag (DF) being clear. The System V ABI requires DF=0 at function entry, but inline assembly or signal handlers could set DF=1. If DF=1, `rep movsb` copies backward, corrupting memory.
**Impact:** Memory corruption if DF is set by signal handler or asm block.
**Fix:** Add `cld` (clear direction flag, opcode 0xFC) before `rep movsb`/`rep stosb`.
**Priority:** P2 — requires unusual conditions but trivial to fix.

### CVE-09: Jump target table overflow

**File:** `src/backend/x86/jump.cyr:44`
**Vector:** Jump target table holds 1024 entries per function. Functions with >1024 jump targets (complex switch statements, deeply nested conditionals) silently stop recording targets. LASE may then incorrectly eliminate loads at unrecorded jump targets.
**Impact:** Incorrect code generation in very complex functions.
**Fix:** Error or warn on overflow. Expand table or use bitmap.
**Priority:** P2 — only affects pathologically complex functions.

### CVE-10: Temp file race condition

**File:** `programs/cyrius.cyr:243`
**Vector:** `cyrius build` writes to `/tmp/cyrius_cpp` — a predictable path. A local attacker could create a symlink `/tmp/cyrius_cpp → /target` and trick the build tool into overwriting an arbitrary file.
**Impact:** Arbitrary file overwrite by local attacker.
**Fix:** Use `mktemp` pattern or include PID in temp filename.
**Priority:** P2 — requires local access.

---

## Low (P3) — Track for future

### CVE-11: No stack canaries

**Vector:** Compiled binaries have no stack protector. Buffer overflows on the stack (e.g., from `var buf[N]` with unchecked indexing) are directly exploitable.
**Fix:** Emit stack canary check in function prologue/epilogue (post-4.x).

### CVE-12: Seed binary trust

**File:** `bootstrap/asm` (29,016 bytes)
**Vector:** The 29KB seed binary is the root of trust. It's committed as a binary blob. A compromise of this file compromises the entire toolchain silently.
**Mitigation:** SHA-256 checksum in README. Bootstrap closure verification (seed→cyrc→asm→cyrc matches). Reproducible from the Rust seed archive.
**Fix:** Publish checksum in a signed attestation. Add `cyrius verify-bootstrap` command.

### CVE-13: No signing of releases

**Vector:** Release tarballs are unsigned. A MITM attack on the download could substitute a compromised toolchain.
**Fix:** GPG-sign release artifacts. Publish checksums in a detached signature file.

---

## Summary

| Severity | Count | Fix Target |
|----------|-------|------------|
| Critical (P0) | 3 | v4.2.2–v4.2.4 |
| High (P1) | 3 | v4.2.x |
| Medium (P2) | 4 | v4.3.x |
| Low (P3) | 3 | Tracked |
| **Total** | **13** | |

## Action Items

### v4.2.2 (immediate)
- [ ] CVE-01: Sanitize git URLs in dep resolver (reject shell metacharacters)
- [ ] CVE-08: Add `cld` before `rep movsb`/`rep stosb` (one byte fix)
- [ ] CVE-10: Use PID-based temp file path

### v4.2.3
- [ ] CVE-02: Path traversal protection for include directives
- [ ] CVE-03: Include-once table expand to 256, error on overflow
- [ ] CVE-04: Validate dep write destinations within lib/

### v4.2.4
- [ ] CVE-06: String data bounds checking
- [ ] CVE-09: Jump target table overflow warning

### v4.3.x
- [x] CVE-05: Critical region overflow checks (str_data, tok_names, codebuf) — **shipped v5.11.65** (tok_names mangle-path guard; str_data + codebuf covered by earlier CVE-06 + EB work)
- [ ] CVE-07: PIE binary generation (tracked under PIC codegen) — **pinned v6.1.x** via `proposals/2026-05-11-pie-support.md`
- [ ] CVE-11: Stack canaries (post-CFG)
- [ ] CVE-12: Bootstrap attestation command
- [ ] CVE-13: Release signing
