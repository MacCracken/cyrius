# Position-Independent Executable (PIE) Codegen

**Filed:** 2026-05-11 during AGNOS v1.27.x → v1.28.x planning
**Severity:** Feature request — no current consumer is blocked, but AGNOS's full-binary KASLR (Option A in [`agnos/docs/development/proposals/2026-05-11-kaslr-scope.md`](https://github.com/MacCracken/agnos/blob/main/docs/development/proposals/2026-05-11-kaslr-scope.md)) is gated on this landing.
**Affects:** `src/backend/x86/emit.cyr`, `src/backend/aarch64/emit.cyr`, fixup-table machinery, every site that emits an absolute address into the binary. cycc ABI implications discussed below.
**Target slot:** v6.1.x — after the v6.0.0 rename + cleanup arc settles. Not blocking v6.0.0.

## Summary

cycc emits absolute addresses into the binary at most call/jmp/data-access sites. Functions can be called via `call rel32` (already RIP-relative — fine), but global-data accesses, function-pointer loads, jump tables, and most fixup-table entries bake in absolute addresses. This means a cyrius binary cannot run correctly at any address other than its link-time base (`0x100000` for AGNOS kernel; the standard `0x400000` / `0x401000` for userland on Linux x86_64).

This proposal asks cyrius to grow a PIE codegen mode — invoked via `cyrius build --pie src/main.cyr build/foo` or equivalent — that emits a binary whose internal references are all RIP-relative (or `adrp`+`add` on aarch64), so the loader (or a relocating boot shim, in the AGNOS case) can slide the binary to any address at boot time.

## Why this is a v6.x feature, not v5.x

- **Cross-cutting backend change.** Every code-emit site that produces an absolute address needs to be audited and converted. That's not a slot — it's a refactor of the same shape as the `_TARGET_*` consolidation already pinned to v6.0.0.
- **ABI implication.** Linking a PIE binary against a non-PIE binary (or vice versa) doesn't work in general. Once cyrius can emit PIE, the question of whether stdlib distfiles are also PIE-compatible has to be answered. v5.x is mid-arc on stdlib annotation + foldin work; perturbing the ABI mid-cycle would compound risk.
- **Major-bump signal to downstreams.** Same reasoning as the cycc → cyc rename at v6.0.0: downstreams need to re-pin and re-verify. PIE codegen is an opt-in flag (non-PIE remains the default through v6.x), so consumers aren't *forced* to migrate, but the option appearing in a major-version bracket is the right signal.

## Why not "just hand-roll relocation tables in the consumer" (the kludge alternative)

AGNOS could, in principle, emit a hand-rolled relocation table for its kernel binary and have the boot shim walk it before jumping to a slid entry point. The cyrius proposal sidelines this for three reasons:

1. **Every cyrius codegen change risks silently breaking it.** A new instruction-emission path that produces an absolute address has no compile-time signal that the relocation table is incomplete. The first sign of breakage is a triple fault at boot.
2. **It puts AGNOS in the business of tracking which addresses in its own binary are absolute.** That's parsing-the-ELF-yourself territory; brittle.
3. **Every other future cyrius binary that wants KASLR / ASLR support has to reinvent this.** Solving it at the compiler level is solving it once.

## Codegen scope — what changes

### x86_64

| Today (non-PIE) | PIE mode |
|---|---|
| `mov rax, 0x123456` (load absolute address) | `lea rax, [rip + rel32]` |
| `mov rax, [0x123456]` (data load by abs) | `mov rax, [rip + rel32]` |
| `call rel32` (function call) | Unchanged — already RIP-relative |
| `jmp rel8/rel32` (intra-fn) | Unchanged — already RIP-relative |
| `mov [rip + …], rax` (already exists for some sites) | Unchanged |
| Fixup tables (`fixup_t fixups[N]`) carrying absolute target addresses | Carry RIP-relative offsets; emit applies them at link time via the existing fixup machinery |
| Pointer-to-function stored as `dq 0xABCDEF` in a data table | `dq <offset-from-table-base>` plus a small runtime/loader hop to resolve |

The first two rows cover the bulk of the change. The last row — function pointers stored in data tables (vtables, dispatch tables) — is the awkward case. cyrius has these via `&fn_name` syntax that today resolves to an absolute address. Under PIE the value has to either be relative (and recipients have to know to add a base) or runtime-relocated by the loader. The simpler answer is **relative offsets from a known base**, with the consumer adding the base when dereferencing. That requires source-level changes in consumers that store fn pointers in tables — not transparent.

### aarch64

| Today (non-PIE) | PIE mode |
|---|---|
| `movz x0, #imm16; movk x0, …` (build absolute address in 4 chunks) | `adrp x0, sym; add x0, x0, #:lo12:sym` |
| Absolute data loads via 4-chunk constant + `ldr` | `adrp x0, sym; ldr x1, [x0, #:lo12:sym]` |
| `bl rel26` (branch-with-link, ±128 MB) | Unchanged — already RIP-relative |
| Pointer-to-function in data tables | Same relative-offset story as x86_64 |

aarch64 is actually slightly cleaner — `adrp` is the canonical PC-relative-page-load instruction and was designed for exactly this. The 4-chunk `movz`/`movk` sequence cyrius emits today for absolute addresses is what gets replaced.

### Where today's code is concentrated

- **`src/backend/x86/emit.cyr`** — every absolute-address emit. Estimated: 30-40 distinct call sites once the audit completes.
- **`src/backend/aarch64/emit.cyr`** — same shape, ~20-30 sites.
- **`src/backend/x86/fixup.cyr` / `src/backend/aarch64/fixup.cyr`** — fixup-table machinery. Has to learn whether each fixup is absolute (old mode) or RIP-relative (new mode).
- **`src/frontend/parse_expr.cyr`** — `&fn_name` and `&global_var` expression handling. Today these resolve to absolute symbol values; under PIE they have to produce relative offsets or trigger a relocation entry.
- **Heap map fields tracking emit cursors / fixup arrays** — possibly unchanged, possibly need a new "fixup kind" enum to distinguish abs vs rel.

## Scope options for v6.1.x

### Option A — Kernel-mode PIE only (recommended for first cut)

Add `--pie` (or `kernel; pie;` source-level directive) that emits PIE-compatible code only when in `kernel;` mode. AGNOS is the only known consumer. Userland binaries continue to use the non-PIE path. Stdlib distfiles don't need PIE (kernel doesn't link them).

- **Scope**: x86_64 first (AGNOS's primary target); aarch64 follows in a sub-patch.
- **Won't break**: userland builds, stdlib consumers, the entire v5.x → v6.0.x downstream stack.
- **Surface**: ~200-400 LOC across `src/backend/x86/emit.cyr` + `fixup.cyr`, plus a handful of fns in `parse_expr.cyr` for `&` expressions that need to emit relocation hints in kernel-PIE mode.
- **Pays for**: full-binary AGNOS KASLR (the original motivation).
- **Doesn't pay for**: userland ASLR, shared-library PIC, dynamic linking. Those wait for Option B.

### Option B — Universal PIE

Make PIE a build-mode flag available to any consumer. Stdlib distfiles also become PIE-compatible. Implies an ABI commitment: PIE binaries can be linked / loaded by anything.

- **Scope**: ~3x Option A. Stdlib audit + recompile required.
- **Surface**: every backend emit path + every consumer that stores fn pointers in static tables.
- **Pays for**: future userland ASLR, future shared-library scenarios, any cyrius binary that wants address-space randomization.
- **Cost**: bigger compatibility matrix; one minor's worth of churn across stdlib consumers.

**Recommendation:** ship Option A as **v6.1.0**. Option B is a follow-up — possibly v6.2.0 if the universal-PIE pressure ever materializes from a real consumer; if not, leave it open indefinitely. The "is this worth it for userland?" question is genuinely uncertain — AGNOS is the only current driver.

## Work breakdown — Option A (the v6.1.0 plan if approved)

1. **Mode plumbing.** Add `--pie` flag to `cyrius build` wrapper; thread through to `cycc` as a build-mode bit. In source, recognize `kernel; pie;` as the dual-flag form. Decision needed: separate flag or implied by `kernel;`? Per "kernel-mode PIE only" scope, implying it from `kernel;` is tempting but locks out non-PIE kernel builds (which AGNOS today still wants for the v1.28.0 data-only KASLR cut). Recommendation: **separate flag**.
2. **Absolute-address audit.** Grep `src/backend/x86/emit.cyr` and `src/backend/aarch64/emit.cyr` for every site that emits a 64-bit immediate that's a symbol/address. Catalog them. Per-site decision: convert to RIP-relative, or leave (rare cases that don't matter for KASLR — e.g. MMIO addresses in kernel-only paths).
3. **x86_64 emit conversions.** Convert the catalogued sites one at a time. Bracket each by: byte-identical fixpoint of the non-PIE path stays green, *plus* a new test that the PIE path emits the expected `lea rax, [rip + …]` shape. Use cyrius's existing byte-exact testing discipline.
4. **Fixup table extension.** Add a `FIXUP_KIND_REL32` (or similar) variant. The existing fixup walk applies these as RIP-relative deltas at link time. Non-PIE consumers ignore the kind field; PIE consumers emit only the relative kind.
5. **`&fn_name` / `&global_var` in PIE mode.** When in kernel-PIE mode, `&fn_name` produces an RIP-relative reference plus a relocation entry. The simpler implementation: emit the value into a data slot at a known offset, then load it via `lea rax, [rip + slot]` at use sites. Costs one indirect load per `&` use; acceptable for kernel hot paths.
6. **aarch64 emit conversions.** Same shape as x86_64 but using `adrp`+`add` / `adrp`+`ldr`. Smaller surface.
7. **AGNOS smoke test.** Build agnos kernel with `--pie`; verify it boots at `0x100000` (non-slid) — proves the PIE path is correct at the link-time base. Then slide via a hacked boot shim and confirm it still boots. This is the gate before tagging v6.1.0.
8. **Documentation.** New section in `docs/development/build.md` (or wherever build flags live) describing `--pie`. CHANGELOG entry. Vidya entry in `vidya/content/cyrius/language.toml`. Architecture note in `docs/architecture/` covering the codegen distinction.

## Open questions

- **Stdlib in PIE mode for kernel consumers.** AGNOS doesn't currently link stdlib (kernel `[deps] stdlib = []`); the question is moot for v6.1.0. If a future kernel consumer wants both PIE and stdlib, that's the trigger for Option B.
- **Fixup-table compatibility across modes.** Can a single binary mix PIE and non-PIE fixups? Probably not cleanly, but the question deserves a clear answer in the design: PIE is per-binary, not per-fixup. **Decision**: per-binary; the build mode is fixed at link time.
- **What if `&` of a fn is taken in non-kernel code that's then linked into a kernel binary?** Today the kernel doesn't link external code, so this doesn't arise. Document the constraint.
- **Cross-arch parity.** Should v6.1.0 ship both x86_64 + aarch64 PIE simultaneously, or x86_64 first with aarch64 as v6.1.1? Recommendation: **x86_64 first** (AGNOS's primary target), aarch64 follows when AGNOS's aarch64 boot harness is live.

## Decision required

Not blocking for v6.0.0. Slot for v6.1.x acceptance happens when v6.0.0 ships and the v6.x cycle's next item is being chosen.

- [ ] Approve PIE as a v6.1.x candidate (slot, not pin).
- [ ] Approve Option A (kernel-mode PIE only) as the v6.1.0 scope if/when slotted.
- [ ] Approve the 8-step work breakdown.
- [ ] Approve `--pie` as a separate build flag (vs implied by `kernel;`).
- [ ] Approve x86_64-first / aarch64-follows sequencing.

Promote this proposal to an ADR if approved before v6.1.0 implementation begins — the "why not hand-roll relocation in the consumer" reasoning carries enough "why not the other thing" content to deserve durable capture, especially because AGNOS engineers would otherwise face that exact temptation.

---

## Implementation findings (v6.1.6, 2026-06-08)

The slot-entry premise-check overturned this proposal's central assumption. **PIE
codegen was NOT greenfield** — it was ~80% pre-built and byte-proven:

- The `shared;` keyword (`lex.cyr` token 78 → `kmode==2`) and `object` (`kmode==3`)
  already drive a PIC-safe path via `_IS_OBJ(S)` (`x86/emit.cyr`), emitting
  `lea reg, [rip+disp32]` for variable (`_EVRCX`/`EVADDR`), string (`ESADDR`), and
  function (`ELOAD_FN_ADDR`) addresses, plus the switch jump table. The fixup walk
  (`x86/fixup.cyr`) already patches RIP-relative `rel = tgt - (entry + coff + 4)`
  under `if (kmode==2)`. A green check.sh gate (`_shared_dlopen_gate`) dlopen-proves
  it. The `mov→lea` conversions this proposal lists as the bulk of the work mostly
  existed.

**What v6.1.6 actually did** (x86_64): added a `_pie_mode` bit (`--pie` /
`CYRIUS_PIE=1`), widened `_IS_OBJ` + the 3 fixup rel32 branches to fire for
`_pie_mode`, taught `EMITELF_USER` to emit ET_DYN + `p_vaddr=0` + base-relative
`e_entry` (its previously-dead `etype=3` path), and **fixed the one ungated absolute
site the proposal's catalog missed — `EVADDR_X1`** (the `&var→rcx` base load for
struct-field / array-element access). Net result: a `--pie` build produces a
**working userland PIE executable** whose `.text` is byte-identical to the proven
shared-mode codegen (the `entry` term self-cancels in the rel32 math), validated by
running the entire 169-test `.tcyr` corpus as ASLR-loaded ET_DYN binaries.

**The "awkward case" (fn-ptr-in-data / vtables, §"Codegen scope" row 6) was a
non-issue.** Because `&fn` is computed at runtime via the PIC `ELOAD_FN_ADDR` (a
`lea [rip+...]`), runtime `store64(&fn)` into a table stores the correct runtime
address, and indirect `fncallN` dispatch works. fn-pointers, callbacks, interface
dispatch, and even address-valued global initializers (`var gp = &foo;`) all run
correctly under PIE with no relocation-table machinery. **Option B (universal PIE)
is therefore effectively already delivered for userland** — no stdlib recompile or
ABI commitment was needed; PIE stays an opt-in per-binary flag, non-PIE output
byte-identical.

**Still open (deferred from v6.1.6):**

1. **Kernel-PIE ELF for AGNOS KASLR** (the proposal's original Option-A motivation).
   The codegen is done; only the ELF *wrapper* remains — an ET_DYN + multiboot2
   variant of `EMITELF64_KERNEL` with a real `_start` and `p_vaddr=0` (the current
   kernel path is ET_EXEC at a fixed `0x100000`). Deliberately NOT shipped blind:
   AGNOS (v1.43.5) is not pulling on it (data-only KASLR shipped v1.28.0; full-binary
   PIE-KASLR is deferred/unscheduled), and it cannot be validated without an AGNOS
   `--pie` boot harness (a two-boot QEMU+OVMF base-diff exists in agnos CI, wireable
   to `--pie`). Lands on that harness, per "never trust a checkmark over running it
   on hardware."
2. **aarch64 PIE.** aarch64 `_IS_OBJ` covers only `kmode==3` (object); the `adrp`+`add`
   conversions for shared/PIE are unbuilt. A later sub-arc (x86_64-first per this
   proposal's recommendation).
