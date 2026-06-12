# Unreviewed dimensions (completeness critic) — LEGAL-01, CVE-28/29, DX/AGNOS/LSP

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
upstream** in `agnos/docs/development/issue/`:
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

## Status

Filed 2026-06-10. LEGAL-01 and the AGNOS/DX items are v7-readiness work; CVE-28 is
a real bug fixable now. Several have cross-repo (AGNOS kernel) components — file
those upstream, don't edit AGNOS here.
