# Unreviewed dimensions (completeness critic) — LEGAL-01, CVE-28/29, DX/AGNOS/LSP

> **✅ ARCHIVED at the v6.4.32 handoff sweep (2026-07-09).** All actionable items shipped by
> v6.3.23 (CVE-28 v6.1.38, CVE-29 v6.2.44, DX-01/02 + SEC-AGNOS-01 v6.3.23). The one remaining
> item — **LEGAL-01** (GPL-3.0-only stdlib source-included into consumers; a v7-release blocker
> needing legal sign-off) — is now tracked in [`roadmap-future.md`](../roadmap-future.md) under
> "~v7.0 — Public release", so this issue no longer needs to sit in the open working queue.

> **STATUS (v6.3.23): closed for this cycle except LEGAL-01 (v7).** CVE-28 RESOLVED
> v6.1.38; CVE-29 (thread-stack guard page) SHIPPED v6.2.44 (`PROT_NONE` guard below
> each thread stack, `lib/thread.cyr:67-92`); **DX-01, DX-02, SEC-AGNOS-01 all
> addressed v6.3.23** — see "## Resolution (v6.3.23)" below. **STILL OPEN:** LEGAL-01
> (GPL-3.0-only vs sigil's dual-BSD/GPLv2 GPL-leg — a v7-release blocker needing
> legal sign-off, deliberately deferred to near public release).

**Discovered:** 2026-06-10 during the deep-dive review ([`docs/audit/2026-06-10-deep-dive-review.md`](../../audit/2026-06-10-deep-dive-review.md))
**Severity:** Mixed (LEGAL-01 is a v7 blocker; CVE-28 is a real concurrency bug)
**Affects:** licensing, debug-info, atomics, thread stacks, the AGNOS security
model, and the LSP/editor tier — areas no dimension analyst owned, flagged by
the completeness critic.

## LEGAL-01 — GPL-3.0-only stdlib statically source-included into consumers (v7 blocker)

`LICENSE` is pure GPL-3.0-only with **no Runtime Library Exception**, and
`lib/*.cyr` is *source-included* into every consumer program — arguably forcing
GPL on all downstream binaries (GCC ships an RLE for exactly this so that linking
libgcc/libstdc++ doesn't infect the output). Separately, `lib/sigil.cyr:533-537`
elects the **GPLv2-only** leg of dual BSD/GPLv2 kernel SHA-NI code — GPLv2-only
is GPL-3-**incompatible**, an internal license conflict.

**Action:** legal review before public release; decide whether to add an RLE-style
linking exception to the stdlib license (so consumers can ship non-GPL binaries)
and resolve the sigil GPLv2 leg (switch to the BSD leg, or relicense the file).
This is a v7 ("Cyrius ONE") gate, not a code fix.

## CVE-28 — aarch64 atomics are not barriers; unfenced vtable publish (P2)

`lib/atomic.cyr:19-26` documents `atomic_cas`/`fetch_add` as "full barriers on
both arches", but the aarch64 bodies are bare `ldxr/stxr` — **no `dmb`/acquire/
release**. `default_alloc()` CAS-publishes a just-built 40-byte vtable with no
fence (`lib/alloc.cyr:622-631`): on Pi (a real self-host target) a peer thread can
observe the pointer before the vtable contents are visible. Lock paths fence
explicitly; code relying on the bare contract does not. This is the concurrency
substrate for the v6.3.x async arc.

**Fix:** add the appropriate `dmb ish` (or LSE acquire/release variants) to the
aarch64 `cas`/`fetch_add` bodies to honor the documented contract, and add a
release fence before the `default_alloc` vtable CAS-publish. Verify on pi.

**RESOLVED v6.1.38 (Phase F pack F3).** `atomic_cas`/`atomic_fetch_add` switched
from bare `ldxr`/`stxr` to `ldaxr`/`stlxr` (acquire/release exclusive — ARMv8.0-A
safe, no LSE needed; a 1-bit opcode change so the LL-SC branch offsets are
untouched, vs `dmb` which would have shifted them). Added `atomic_fence()` before
the `default_alloc` vtable CAS-publish. Docs corrected (the old "full barriers"
claim over-promised a `dmb ish` that was never emitted). **Verified on real pi**
(atomics.tcyr 4-thread contention) + `ldaxr`/`stlxr` disasm-confirmed. See
CHANGELOG [6.1.38].

## CVE-29 — thread stacks have no guard page; stack probe PE-only (P3)

`mmap_stack` maps the whole stack `PROT_READ|PROT_WRITE` with no `PROT_NONE`
guard page or `MAP_STACK` (`lib/thread.cyr:50-55`) — a thread stack overflow
silently writes adjacent mappings (e.g. the 256 MB allocator chunks) instead of
faulting. The `ESUBRSP` page probe exists only on PE (`x86/emit.cyr:2037`).

**Fix:** map a `PROT_NONE` guard page below each thread stack; consider a
portable stack-probe in the prologue for large frames on non-PE targets.

## DX-01 — no debug-info on any target; crash-localization x86-ELF-only

`grep src/` shows no DWARF/line-info emission anywhere; the `CYRIUS_SYMS` symbol
dump exists only in `src/backend/x86/fixup.cyr:125-129` (absent from
aarch64/fixup.cyr, pe/emit.cyr, macho). The official workflow
(`docs/development/crash-localization.md`) needs `coredumpctl` + a python3 snippet;
4 of 5 targets debug via exit-code probes. Material DX gap for the v7 onboarding
surface.

**Action:** scope a minimal line-table emit (at least `CYRIUS_SYMS` parity across
all 5 backends; DWARF `.debug_line` is the larger v7 ask). Not pinned — surfacing.

## SEC-AGNOS-01 — the AGNOS userspace target has no security-model assessment

Beyond CVE-19's no-entropy finding, the frozen AGNOS syscall ABI + userspace
target got no W^X / ASLR / stack-hardening review. The flagship target runs the
default native-TLS stack with no RNG and unreviewed memory protections.

**Action:** a focused AGNOS-target security pass (entropy, W^X, ASLR/PIE
applicability, the alloc_agnos guard from
[memory-safety-parity-gaps](2026-06-10-memory-safety-parity-gaps.md)) — coordinate
the ABI parts upstream (cross-repo). Two AGNOS-side asks have been **filed
upstream** in `agnos/docs/development/issues/`:
`2026-06-10-cyrius-tls-entropy-syscall-gap.md` (the getrandom syscall) +
`2026-06-10-cyrius-pie-boot-harness-ask.md` (kernel-PIE boot validation, the
ASLR/PIE-applicability half).

## DX-02 — LSP / editor tooling tier unreviewed (the v7 onboarding surface)

`programs/cyrius-lsp.cyr` (81 KB JSON-RPC server with cross-file indexing) is
covered by exactly one check.sh gate (`programs/checks/services.cyr:397-417`);
`editors/vscode` (54-line extension) + `editors/neovim.lua` ship in-repo with zero
review of correctness, untrusted-workspace input handling, packaging, or
per-platform coverage.

**Action:** an LSP correctness + untrusted-workspace-input pass before v7; widen
the single gate.

## Resolution (v6.3.23)

**DX-01 — RESOLVED.** The `CYRIUS_SYMS` function-symbol dump (was x86-ELF-only, in
`src/backend/x86/fixup.cyr`) is hoisted to a shared `_emit_sym_dump(S, base)` in
`src/backend/common/runtime.cyr` and called from both the x86 and aarch64 fixup
passes, so crash-localization symbols now emit on **aarch64 (ELF + Mach-O)** at
parity with x86 — the aarch64 cross-compiler previously wrote nothing. The base VA
is passed in per-target; the x86 caller now uses the PE ImageBase+text-RVA base for
`_TARGET_PE` (the old block wrongly formatted the ELF `entry` for the PE crash
reporter). Portable syscalls (`SYS_OPEN`/`SYS_WRITE`/`SYS_CLOSE` + the aarch64
`openat` shim). Entirely behind the `CYRIUS_SYMS` env guard → emitted programs stay
byte-identical when unset. **cx is N/A** (bytecode VM; its `_read_env` is a `return
0` stub, so the env-driven dump is structurally inert there). DWARF `.debug_line`
remains the larger v7 ask, out of scope.

**DX-02 — RESOLVED (correctness + untrusted-input hardening + widened gate).**
`programs/cyrius-lsp.cyr`: (1) a genuine out-of-bounds stack write fixed — the
lone `var pipe_fds[2]` (2 bytes; `sys_pipe` writes 8) and `var status_buf[1]`
(1 byte; `waitpid` writes 4) grown to `[16]` to match every other caller in the
repo (the v6.3.18 undersized-array sweep had missed `programs/`); (2) untrusted
`Content-Length` now capped at 16 MB in `read_header` (was unbounded → huge
`alloc` / NULL-page read) and `read_body` null-checks the alloc; (3) `uri_to_path`
rejects any path with a `..` component (soft-fail to empty string), closing the
workspace-traversal read/index vector. The single happy-path check gate gained an
adversarial **Phase 4** (traversal-URI didOpen + missing-uri didOpen → a valid
`documentSymbol` still answers) proving the server survives hostile input.

**SEC-AGNOS-01 — ASSESSED; no cyrius-side code change needed.** Reviewed against
function bodies (not comments):
- **Entropy** — SAFE. All native-TLS randomness funnels through `_tn_rand_bytes`
  (`lib/tls_native_conn.cyr:446`) → `sys_getrandom` → AGNOS syscall #45
  (`lib/syscalls_x86_64_agnos.cyr:744`), real kernel CSPRNG, `flags=0`; every
  caller fail-closes on a short read. No fixed-seed / counter / uninitialized
  fallback. CVE-19 lineage closed for AGNOS.
- **W^X** — SAFE (cyrius side). AGNOS userspace is ELF (`_emit_fmt==0`) kmode 0, so
  `_wx_active` returns 1 by default → the 2-PT_LOAD text-`R E`/data-`RW ` split is
  emitted. Loader enforcement (mapping PF_X exec, non-PF_X NX) is an AGNOS-kernel
  property (cross-repo).
- **PIE / ASLR** — N/A by default on the cyrius side. AGNOS userspace is non-PIE
  ET_EXEC at fixed 0x400078 unless `--pie`/`CYRIUS_PIE=1` (orthogonal to the target
  flag). The userland PIE path is wired (ET_DYN via `EMITELF_USER(S,3)`); whether it
  yields real ASLR depends on the AGNOS kernel randomizing the ET_DYN load base
  (cross-repo, filed upstream: `2026-06-10-cyrius-pie-boot-harness-ask.md`).
- **alloc_agnos** — SAFE. `lib/alloc_agnos.cyr:67-74` shares the CVE-24/25/26
  guards (`size <= 0` reject, `size > ALLOC_MAX` reject) at full parity with the
  Linux/macOS/Windows allocators; it is the sole allocator under
  `#ifdef CYRIUS_TARGET_AGNOS`, no bypass.

Two stale comments corrected in passing (comments rot; the bodies were right):
`src/backend/aarch64/fixup.cyr` W^X "default OFF" → default ON, and `src/main.cyr`
`--pie` "ignored outside kernel" → userland PIE is wired.

## Status

Filed 2026-06-10. DX-01 / DX-02 / SEC-AGNOS-01 resolved v6.3.23 (above); CVE-28
resolved v6.1.38; CVE-29 shipped v6.2.44. **LEGAL-01 alone remains** — a v7-readiness
legal review (GPL RLE-style linking exception + the sigil GPLv2-leg conflict), not a
code fix. Cross-repo (AGNOS kernel) components stay filed upstream — don't edit AGNOS
here.
