# Cyrius Development Roadmap — v6.x cycle

**Scope** — the **whole v6.x cycle** (cycle-open 2026-05-19). This is
the cycle-level reference: framing, per-minor budgeting, and the
remaining minors v6.1.x → v6.5.x. The **current active minor** is
broken out in detail in [roadmap.md](roadmap.md); items beyond the
cycle (v7.0+ aspirations, unpinned language refinements, speculative
work) live in [roadmap-future.md](roadmap-future.md). v5.x history and
the now-closed v6.0.x detail are canonical in
[`CHANGELOG.md`](../../CHANGELOG.md) per-patch and in
[completed-phases.md](completed-phases.md) for arc retrospective.

> **Reading order**: [roadmap.md](roadmap.md) (active minor) →
> this file (rest of the v6.x cycle) →
> [roadmap-future.md](roadmap-future.md) (beyond v6.x).

## See also

- [roadmap.md](roadmap.md) — the **current active minor**, in detail
  (slot-pinning artifact). Rotates at every minor cut.
- [cycle-discipline.md](cycle-discipline.md) — durable operating
  principles (slot acceptance, bottom-to-top priority, premise-check,
  cross-host smoke, cycle-close shape). Evergreen; not cycle-specific.
- [state.md](state.md) — volatile current state (version, cycc size,
  in-flight slot, recent shipped patches). Refreshed every release.
- [roadmap-future.md](roadmap-future.md) — long-term watching list
  (unpinned items, speculative type-system work, v7.0+ aspirations).
- [completed-phases.md](completed-phases.md) — pre-v5.11.x historical
  arc retrospective (Phase 0–11 foundation summary post-trim).
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth.

## v6.x framing

v5.x froze "what the language IS." **v6.x is what the language
gains** — new platforms, position-independent codegen, language
features (closures, generics, async syntax), Class B FFI fix,
cross-BB regalloc + the deferred optimization passes that gate on
it. Plus a dedicated middle-late perf-refactor minor to absorb the
accumulated growth-tax from v5.x feature work + early-v6.x platform
additions.

## v6.x cycle budgeting

**Per-minor target**: ~30-slot budget = 20 planned + 10 bug
bandwidth (per user direction 2026-05-19). Can flex to 40-50 like
late v5.x cycles when a minor's substantive new-code surface
warrants it (notably v6.2.x platform expansion + v6.4.x ABI+Perf
arcs).

Reference points: v5.11.x = 70 slots (longest in history),
v5.7.x = 49. v6.x cycles target a middle-ground — most minors
in the 30-40 range, with the substantive-new-code minors flexing
higher.

---

## v6.0.x — Language Cleanup + Stdlib + Native TLS arc — ✅ COMPLETE (v6.0.0 → v6.0.91)

The v6.0.x minor is **closed** (91 patches, 2026-05-19 → 2026-06-07).
Per-item detail has been removed from this roadmap per the clean-cut
discipline; the canonical record is [`CHANGELOG.md`](../../CHANGELOG.md)
per-patch and [completed-phases.md](completed-phases.md) for the arc
retrospective. The minor opened with the `cc5 → cycc` / `cyrc → cybs`
two-binary rename ceremony (v6.0.0) and shipped:

- **Sovereign native TLS** (`lib/tls_native.cyr`) — full TLS 1.2 + 1.3,
  client + server, over sigil primitives; ECDSA P-256/P-384 + RSA
  PSS/PKCS#1 + Ed25519; AES-128/256-GCM + ChaCha20-Poly1305; EMS, ALPN,
  OS trust-store + SNI verification. Live Cloudflare HTTPS + OpenSSL
  interop proven. `lib/tls.cyr` re-backed onto it behind
  `CYRIUS_TLS_NATIVE` (libssl stays the default backend). sandhi 1.4.x
  rewired off raw libssl onto typed verbs.
- **AGNOS userspace target** (`CYRIUS_TARGET_AGNOS`) — new ring-3
  compile target + `lib/syscalls_*_agnos.cyr` ABI peer; agnoshi
  cross-build gate; getenv/envp; verified boot-to-prompt on the real
  agnos 1.43.x kernel under QEMU.
- **Cross-OS platform hardening (the macOS-rot remediation)** — macOS
  (arm64 + x86) and Windows `cycc` now **self-host AND install to a
  working toolchain on real hardware** (ecb/ach/cass), not just
  hello-world smoke. Real self-host + functional CI gates replace the
  placebo jobs; Windows multi-DLL PE FFI + COM/DXGI GPU enum.
- **Backend + cleanup** — alloc/vec pull-in + return-patch→vec
  conversion; backend module collapse (`src/backend/common/`);
  `_TARGET_*` / `_emit_fmt` consolidation (first bite); byte-array
  literal peephole; global-allocator thread-safety; `programs/check.cyr`
  → `programs/checks/` modularization.
- **QoL / codegen P1s** — octal literals (`0o755`), TOML `[section]`,
  `cyrius tests` plural runner; nous-0001 typed-`vec_get` fix; kybernet
  aarch64 codegen-hang + DCE audit; deps correct-lock.

**Carried OUT of v6.0.x → v6.1.x** (now detailed in
[roadmap.md](roadmap.md)): bayan/ganita stdlib carve; x86-macho cycc
self-compile (HELD — Apple Intel EOL); TS/TSX → JS emit; and the
closeout judgment-pass carry-ins (aarch64 `EADDRA_IMM` 12-bit mask,
`_emit_fmt`/`_entry_base` shared hoist, DCE mark-and-sweep
consolidation).

---

## v6.1.x — Backend Codegen Multi-Arc

> **Active minor.** [roadmap.md](roadmap.md) is the authoritative,
> slot-by-slot view; the section below is the cycle-level summary kept
> here for the v6.x overview. When the two disagree, roadmap.md wins.

**Theme**: position-independent codegen + dynamic-link migration +
v6.0.x back-compat retirement + the v6.0.x → v6.1.x carry-ins. Pinned
2026-06-08 into a per-sub-arc sequence (primary expected items first):

| Phase | Slots | Items |
|---|---|---|
| **A — housekeeping** | v6.1.1–.3 | back-compat symlink drop · `aarch64 EADDRA_IMM` >4095 fix · POSIX `*at()` family |
| **B — backend prep** | v6.1.4–.5 | `_TARGET_*` decl move + `_emit_fmt`/`_entry_base` hoist · DCE mark-and-sweep consolidation |
| **C — PIE codegen** | v6.1.6–.8 | PIE x86_64 → PIE aarch64 → `.gnu.hash` migration + drop SysV `.hash` |
| **D — frontend emit** | v6.1.9 | TS/TSX → JS emit (`cycc --emit-js`) |
| **E — stdlib carve** | v6.1.10–.11 | bayan distfile carve · ganita distfile carve |
| *(bug bandwidth)* | — | x86-macho cycc self-compile (HELD) · cyim regex unblock · Windows deps `--lock` hash |

Primary expected ≈ **11 planned slots** + ~10 bug bandwidth. PIE is the
headline (its AGNOS KASLR consumer is uncertain-timing); the Phase-B
refactors are PIE prep (the `_emit_fmt` hoist needs the `_TARGET_*` decls
moved, and PIE extends the same `emit.cyr`/`fixup.cyr`). Full slot detail,
rationale, and the HELD-tail conditions live in
[roadmap.md](roadmap.md) — the authoritative active-minor view.

---

## v6.2.x — Platform Expansion (Bare-metal + RISC-V rv64 + Native TLS)

**Theme**: 4th platform peer (RISC-V rv64) + bare-metal target
codification. Substantial new-code minor; substrate prerequisites
all landed in v5.11.x close (parser-to-emit named-op refactor,
heap-map full reorg) + v6.1.x backend codegen.

Per user direction 2026-05-19: "previous C items lets break up
logically into prioritized proposals into 6.2.x and 6.3.x" —
platform work (bottom-to-top priority) takes v6.2.x.

### v6.2.0 — Bare-metal target formalization

Codify the ad-hoc bare-metal mode that agnos has been using
since first boot into a first-class
`--target bare-metal-x86_64-elf` (and aarch64 peer) triple.
Six deliverables:

1. Formal target triple (`<arch>-bare-metal-elf`)
2. ELF no-libc output format (no PT_INTERP, no DT_NEEDED, no
   _start expecting libc init)
3. Interrupt-handler emit conventions (`naked_fn` attribute —
   no prologue/epilogue, manual register save/restore)
4. Kernel-mode stdlib subset (forbidden-module check errors
   when bare-metal code pulls host-OS modules)
5. Linker-script / section-placement control via `[sections]`
   block in `cyrius.cyml`
6. Inline assembly primitives for kernel work: `cli`/`sti`/`hlt`,
   port I/O (`in`/`out`), memory barriers (`mfence`/`lfence`/
   `sfence`), `cpuid`

**Acceptance**: rebuilding the agnos kernel with `--target
bare-metal-x86_64-elf` produces a byte-identical artifact to the
current ad-hoc build; forbidden-module check errors clearly when
bare-metal code pulls host-OS modules;
`examples/firmware-hello.cyr` demonstrates the target outside
of agnos.

**Important framing**: bare-metal is **formalization, not
enablement**. The agnos kernel already builds and boots without
this target; v6.2.0 is a QoL feature for future bare-metal
Cyrius consumers (firmware, alt-kernels, embedded). It does NOT
gate AGNOS MVP.

### v6.2.x — RISC-V rv64 backend

First-class RISC-V 64-bit target. The 4th platform peer after
x86_64 / aarch64 / PE-x86_64. Substrate prerequisites already
landed: typed-simd ABI (v5.x), REAL TYPE SYSTEM (v5.10.x),
struct-byval ABI (v5.10.x), parser-to-emit named-op refactor
(v5.11.x close).

**Scope**:
- New backend: `src/backend/riscv64/{emit,jump,fixup}.cyr`
- New stdlib syscall peer: `lib/syscalls_riscv64_linux.cyr`
- New cross-entry: `src/main_riscv64.cyr`
- New test runner: QEMU + HiFive Unmatched (or equivalent rv64
  hardware) for self-host verify
- New CI matrix arm

**Acceptance gates**:
1. Cross-compiler `build/cycc_riscv64` emits valid rv64 ELF
   that `file(1)` identifies.
2. Single-syscall "exit 42" probe runs under
   `qemu-riscv64-static`.
3. Hello-world via `sys_write` + `sys_exit` runs under QEMU.
4. Self-host byte-identical on real rv64 hardware (hardware-
   gated like the aarch64 ssh-pi check).
5. `[release].cross_bins` in `cyrius.cyml` gets a
   `cycc_riscv64` entry.

### v6.2.x — Native TLS stack (`lib/tls_native.cyr`)

Per user direction 2026-05-27: build a **sovereign, pure-Cyrius TLS
stack** to replace the current `lib/tls.cyr`, which is a
**`libssl.so.3` / `libcrypto.so.3` wrapper via the fdlopen bridge**
(client-only; depends on a host OpenSSL + `ld.so`-bootstrapped glibc
TCB). Two consumers now justify the arc (the ≥2-consumer threshold,
[[project_testing_framework_split]]):

1. **The AGNOS kernel** — a freestanding/bare-metal kernel has **no
   `libssl.so.3` to dlopen and no `ld.so`** to bootstrap the glibc TCB
   the current wrapper requires, so the existing `tls.cyr` is
   *structurally unusable* in-kernel. This is the forcing function.
2. **sandhi** (`lib/sandhi.cyr`, folded at v5.7.0) — the larger
   service-boundary wrapper that composes the stdlib network
   primitives (`http`/`ws`/`tls`/`net`) into the full client+server
   surface. Re-points onto the native stack.

**Why v6.2.x**: the kernel consumer needs the **bare-metal target
(v6.2.0)** to compile freestanding crypto + protocol code at all, so
native TLS lands in the same minor, after the target formalizes.

**Scope** (per user direction 2026-05-27): **TLS 1.2 + 1.3, client +
server** — full parity with what the libssl wrapper exposes today,
including 1.2 for older-peer interop.

**Crypto base** — **stays in sigil**; the native TLS lib is a
*protocol layer* (handshake state machine + record layer + ciphersuite
negotiation + key schedule + X.509 chain-verify wiring) over sigil's
primitives. sigil 3.4.x already ships AES-GCM / ECDSA-P256+P384 /
X.509 / SHA-2 / HKDF / Ed25519 / RSA. The two genuine gaps for the
modern TLS 1.3 `ChaCha20-Poly1305 + X25519` suite — **ChaCha20** and
**X25519** — were added to **sigil's roadmap backlog 2026-05-27** with
this arc as the forcing function. The kernel folds sigil in
long-term the way it folds other select deps (per user analogy: a font
lib; agnoshi as primary shell vs tortuga as emergency shell in the
kernel codebase) — sigil is a kernel-folded crypto dep, not a
TLS-internal vendored copy.

**Sequencing within v6.2.x**: bare-metal target (v6.2.0) → sigil
ChaCha20 + X25519 land (separate sigil minor, gated on this slot
firming) → `lib/tls_native.cyr` record layer + handshake + cert verify
→ sandhi re-point → kernel integration smoke.

**Acceptance** (confirm shape at arc entry): native client handshakes
against a real TLS 1.3 + TLS 1.2 peer (OpenSSL `s_server`); native
server accepts a real client; X.509 chain verify via sigil; sandhi
suite green on the native stack; kernel links `tls_native` freestanding
(no `libssl`, no dlopen); `lib/tls.cyr` libssl path retained or retired
per a decision at arc entry. Cross-arch propagation mandatory
([[feedback_cross_arch_propagation_mandatory]]).

Memory pin: [[project_native_tls_arc_v6_2_x]].

### Slot estimate (v6.2.x)

| Cluster | Slots |
|---|---|
| Bare-metal target formalization (6 deliverables) | ~8 |
| RISC-V rv64 backend (new emit/jump/fixup + syscalls peer) | ~12 |
| Native TLS stack (`tls_native.cyr` — 1.2+1.3 client+server over sigil) | ~12-15 |
| Cross-arch test harness + CI matrix | ~3 |
| Hardware self-host gate (HiFive Unmatched or equivalent) | ~2 |
| **Total planned** | **~37-40** |
| Bug bandwidth | ~10 |
| **Budget** | **~47-50** |

Now the **largest minor of the v6.x cycle** — bare-metal + RISC-V +
native TLS is three substantial new-code arcs. Flexes well above the
30 target per user direction "larger patch bandwidth like the last few
minor cycles of 5.x."

**Priority within the minor** (user direction 2026-05-27): **native
TLS > RISC-V**. Native TLS is kernel-critical and sovereignty-bearing
(it removes the libssl external dependency and unblocks in-kernel TLS);
RISC-V is a 4th platform peer — valuable but not as load-bearing. So if
v6.2.x proves unwieldy at entry, **RISC-V is the flagged split-out
candidate** to defer into its own later minor (e.g. v6.2.x tail or a
dedicated platform minor) — TLS and bare-metal stay. Bare-metal stays
because it's the compile prerequisite for in-kernel native TLS.

---

## v6.3.x — Language Refinements

**Theme**: language-level closures + generics + async sugar.
Three syntactic/semantic additions the v5.x cycle held out
explicitly (per 2026-05-12 tight-close).

Per user direction 2026-05-19: language work (mid-priority,
above ABI/perf) takes v6.3.x.

### Closures with lexical capture

Today: function pointers + lambda-pattern workarounds (see
`lib/fnptr.cyr`). Gotcha #8 in v5.x Language Refinements table —
consumers feel the absence.

**Scope**: closure literals + lexical-capture analysis +
closure-environment lowering (allocate-on-construct, deallocate
when closure pointer goes out of scope; vtable-shaped indirect
call). Pairs with existing trait/vtable infrastructure
(`lib/trait.cyr`). v5.8.x ADTs (sum types + exhaustive match +
Result + ?) make captured-state encoding cleaner than it would
have been pre-v5.8.

### Real generic instantiation (monomorphization)

Today: generics parse (type params accepted at `SKIP_GENERICS`
in `src/frontend/parse_decl.cyr`) but erase at compile time —
no monomorphization, type-check semantics are weakest-applicable.
Test floor: `tests/tcyr/enum_generics.tcyr` (v5.8.21 syntax-
acceptance only).

**Scope**: type checker recognizes type parameters as
concrete-at-instantiation; emit-time substitution generates
per-monomorph code. Kavach was the original 1-vote consumer
(per v5.x Language Refinements table); re-verify pressure at
slot entry per [`feedback_premise_check_at_slot_entry`].

### Language-level async/await syntax

Today: callback-based async on epoll runtime (`lib/async.cyr`,
v5.11.15). Works but is verbose at consumer sites.

**Scope**: `async fn` / `await` syntax compiles to
CPS-transformed state machines over the existing epoll runtime.
Same runtime semantics, sugarier surface. Pairs with closures
(capture state across await points).

### Required vs Optional Dependencies

Today: `cyrius.cyml` has no required/optional distinction. Every
entry in `[deps].stdlib = [...]` auto-prepends; every `[deps.<name>]`
block resolves unconditionally via `cyrius deps`. No feature gating,
no target conditionals, no schema knob for "include this only when
needed." Consumers that want conditional code must wrap call sites
in `#ifdef` and hope the transitive resolver doesn't drag the dep
in anyway.

**Scope** (per user direction 2026-05-23 — combine feature +
platform axes):

1. **Feature-gated optional deps** (Cargo-style)
   - `optional = true` flag on `[deps.<name>]` blocks
   - `[features]` table declaring named feature sets +
     default-features
   - `cyrius build --features <list>` / `--no-default-features`
     CLI surface
   - Resolver only fetches+prepends deps whose feature gate is
     active for the current build
2. **Platform-conditional resolution**
   - `target = "<arch>"` / `target = "<os>"` keys on
     `[deps.<name>]` blocks (e.g. `target = "windows"`,
     `target = "aarch64"`, `target = "bare-metal"`)
   - Matches existing cross-arch story (`_TARGET_PE` / aarch64
     emit paths). Bare-metal target (v6.2.0) and RISC-V backend
     (v6.2.x) immediately benefit — kernel objects skip
     non-applicable userland deps without `#ifdef` gymnastics
3. **Axes combine** — a dep can be both feature-gated AND
   platform-conditional: `optional = true` + `target = "windows"`
   + listed under a feature

**Manifest schema delta** (illustrative):

```toml
[features]
default = ["std-io"]
std-io = []
gpu = ["wgpu"]
win-shell = ["mabda"]

[deps.wgpu]
git = "..."
tag = "..."
optional = true
target = "linux"            # AGNOS userland only

[deps.mabda]
git = "..."
tag = "..."
optional = true
target = "windows"          # win-shell feature gates further
```

**Touched surfaces**:
- `src/frontend/parse_decl.cyr` / cyml parser — schema additions
- `programs/cyrius_deps.cyr` — feature + target filtering before
  resolve
- `programs/cyrius_build.cyr` — `--features` / `--no-default-features`
  CLI surface, target detection passthrough
- Existing consumers (sakshi/patra/sigil/mabda/agnosys/etc.) —
  audit `[deps]` for entries that should become optional once the
  schema is available; consumer migration is opt-in (omitted
  `optional` defaults to required, preserving today's behavior)
- vidya — new `language.toml` entries for `[features]` block +
  optional/target keys; `field_notes/language.toml` for the
  "default = [...] vs --no-default-features" gotcha

**Acceptance bar**:
- Manifest parser round-trips a `[features]` block + optional/target
  keys byte-identical
- `cyrius build --features gpu` resolves wgpu, plain `cyrius build`
  does not
- `target = "windows"` deps skip resolution on aarch64-linux host
- Pre-existing consumer manifests (no `[features]`, no `optional`)
  build byte-identical to v6.2.x
- One vidya entry per axis (feature gate, target gate, combined)

**Out of scope for this slot**: feature unification across
transitive deps (Cargo's hardest semantic — defer to v6.4.x or
later if pressure surfaces); per-feature CHANGELOG/version
constraints; cross-package feature exports.

### Slot estimate (v6.3.x)

| Feature | Slots |
|---|---|
| Closures with lexical capture | ~7 |
| Real generic instantiation | ~7 |
| Language-level async/await syntax | ~5 |
| Required vs Optional Dependencies | ~5 |
| Cross-feature integration + tcyr suite | ~3 |
| **Total planned** | **~27** |
| Bug bandwidth | ~10 |
| **Budget** | **~37** |

---

## v6.4.x — ABI + Perf Arc

**Theme**: Class B FFI / wgpu fncall6 ABI fix + register
allocation upgrade + deferred peephole passes.

Held-forward through v5.9.x / v5.10.x / v5.11.x. The
*language-level* ABI work plus the regalloc-gated perf passes
that have been waiting for cross-BB liveness data.

### Class B FFI / wgpu fncall6 ABI fix

Fix Cyrius's `fncall6` vs SysV AMD64 calling convention bug that
mabda's wgpu integration needs. Lands here regardless of where
the mabda fold itself lands (likely already shipped in v6.0.x
clean-slate by this point per the mabda 3.0 GA timing).

### Cross-BB regalloc + liveness pass

Linear-scan register allocator with cross-BB liveness data.
Unlocks three deferred passes that all share the same gate:

- **Copy propagation** — deferred 2026-04-23 v5.6.18/.19. Stack-
  machine IR had no virtual registers for the classical wins;
  regalloc surfaces them. `ir_copyprop_recon` revival.
- **Extended cross-BB dead-store elimination** — deferred same
  date, same gate. Per-BB DSE shipped v5.6.18; cross-BB variant
  needs the liveness-out set per BB that regalloc builds.
  `ir_extdse_recon` revival.
- **Float peephole** (`float.cyr:41`, 5-instruction → 3-byte
  reduction) — worth landing here if bench delta justifies.

### Slot estimate (v6.4.x)

| Cluster | Slots |
|---|---|
| Class B FFI / wgpu fncall6 ABI fix | ~5 |
| Cross-BB regalloc + liveness pass | ~6 |
| Copy propagation revival | ~3 |
| Extended cross-BB DSE | ~3 |
| Float peephole | ~2 |
| Bench-delta evaluation + tcyr coverage | ~2 |
| **Total planned** | **~21** |
| Bug bandwidth | ~10 |
| **Budget** | **~31** |

---

## v6.5.x — Self-Compile Perf-Refactor

**Theme**: dedicated perf cleanup once accumulated growth
surfaces. Middle-late v6.x timing per user direction 2026-05-19:
"compile time can holdover until later in 6.x cycle probably
middle-late".

### Background

v5.11.x review queue (originally captured at v5.x cycle close,
referenced from CHANGELOG [5.11.69])
captured a perf-growth-tax finding: `bench-history.sh` tier-3
shows self_compile **244 ms → 404 ms (+160 ms / +65 %)** between
commits `a17a8de` (2026-04-18, post-v5.10.50) and `f60ec9b2`
(2026-05-18, post-v5.11.63). Growth-tax not regression — cycc
binary grew only +1,072 B over the same window, so the cost is
parse/codegen overhead from feature work (more parser tracking,
more dispatch checks, more cross-arch propagation), not output
bloat.

**v6.x adds its own growth-creating surfaces**: PIE codegen
(v6.1.x), bare-metal + RISC-V rv64 (v6.2.x), language
refinements (v6.3.x), Class B FFI + cross-BB regalloc (v6.4.x).
By v6.5.x the new baseline is established and a dedicated
perf-refactor minor can land without bumping capability work.

### First-step audit

Capture intermediate datapoints via on-quiet-box
`bench-history.sh` runs across the v6.x cycle so the trend has
more than 2 endpoints. Gradual-accretion vs one-patch-dominates
determines whether bisection is even productive (gradual is the
likelier shape given the work mix).

### Slot estimate (v6.5.x)

Open scope at v6.5.x slot entry — depends on the
accumulated-growth shape uncovered during the audit phase.
Target: ~20 planned + 10 bug bandwidth = ~30 budget. Could flex
to 40+ if the perf-refactor surface is wider than expected.

---

## What comes after v6.x

v7.x scope is open. Two known commitments per CLAUDE.md "Version
lives in `VERSION` + `--version`, never in binary names":

- **No binary rename at v7.0.0**. The v6.0.0 `cc5 → cycc` +
  `cyrc → cybs` rename was the LAST name-change penalty paid.
  Future major bumps run `version-bump.sh` and ship; no rename,
  no downstream sweep, no vidya `cc?` residue.
- **build/cc3 drops at v7.0.0** per the prior-major-seed
  retirement policy (cc3 stays through v6.x as the
  v5.0.0-era historical anchor; retires when v6.x → v7.x bump
  removes the legacy back-compat surface).

Beyond that, v7.x is open territory. Likely candidates: more
language refinements based on consumer pressure from v6.x ship;
toolchain improvements (LSP / formatter / linter evolution);
agnos v2.0 alignment if AGNOS's roadmap creates pull.
