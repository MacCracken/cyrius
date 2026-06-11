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
| **A — housekeeping** | v6.1.1–.3 | back-compat symlink drop · `aarch64 EADDRA_IMM` >4095 fix · POSIX `*at()` family + ESYSXLAT collision fix |
| **B — backend prep** | v6.1.4–.5 | `_TARGET_*` decl move + `_emit_fmt`/`_entry_base` hoist · DCE mark-and-sweep consolidation |
| **C — PIE codegen** | v6.1.6–.9 | PIE x86_64 → PIE aarch64 → `.gnu.hash` migration + drop SysV `.hash` |
| **D — frontend emit** | v6.1.10–.12, .15 | TS-AST allocator fix · TS/TSX → JS emit (`cycc --emit-js`) · `--target=js` wrapper · `async`-node fix |
| **agnos fixes** | v6.1.12–.14 | `getenv`/`fnptr`/`argc/argv` HIGH-sev agnos-target fixes (agnoshi/bannermanor) |
| **Windows pillar** | v6.1.16–.18 | `cycc_win` tarball · PE var-syscall dispatch · `nanosleep` · `lib/sync.cyr` · dir-listing port |
| **TLS/alloc/LSP** | v6.1.19–.24 | brk→mmap chunked alloc · cert path-build · native-default flip (.21) · async arena-leak fix · LSP hover |
| **E — stdlib carve** | v6.1.25–.26 | bayan distfile carve · ganita distfile carve |
| **infra/security** | v6.1.27–.31 | output cap 2 MB→16 MB · `lib/sys.cyr` + dep-resolver fix · `fdlopen_init_trusted` · x86-macOS argv prologue · Ed25519 server certs |
| **F — security hardening tail** | v6.1.32+ | the 2026-06-10 deep-dive findings absorbed into the v6.1.x close (see below + [roadmap.md](roadmap.md)) |

Shipped well past the original ~11-slot estimate — and that's expected,
not a budget breach: minors flex long (**v6.0.x ran to 91 patches**), and
per user direction 2026-06-10 *"no worries about patch size, just hardening
and adding features."* PIE was the headline (x86 + aarch64, the `.gnu.hash`
dynamic-link cleanup tail); the TS→JS emit, Windows pillar, agnos-target
fixes, native-TLS-default flip, and bayan/ganita carve packed in as the
minor grew. **Phase F** is the new tail: the security-hardening arc from the
2026-06-10 deep-dive review (`docs/audit/2026-06-10-deep-dive-review.md`),
landing as packed releases before the cycle-close. Full slot detail lives in
[roadmap.md](roadmap.md) — the authoritative active-minor view.

---

## v6.2.x — Platform Expansion (Bare-metal + RISC-V rv64)

**Theme**: 4th platform peer (RISC-V rv64) + bare-metal target
codification. Substantial new-code minor; substrate prerequisites
all landed in v5.11.x close (parser-to-emit named-op refactor,
heap-map full reorg) + v6.1.x backend codegen.

Per user direction 2026-05-19: "previous C items lets break up
logically into prioritized proposals into 6.2.x and 6.3.x" —
platform work (bottom-to-top priority) takes v6.2.x.

> **Re-scoped 2026-06-10** (post deep-dive). The native-TLS stack that
> originally anchored this minor **already shipped** — full TLS 1.2 + 1.3,
> client + server, over sigil (v6.0.x), and it became the **default**
> backend at v6.1.21 (libssl is opt-out via `-D CYRIUS_TLS_LIBSSL`). So the
> ~12–15 phantom "native TLS" slots and the old "native TLS > RISC-V"
> split-out framing are gone (the doc-drift finding RM-01,
> [`issues/2026-06-10-roadmap-drift-and-stale-docs.md`](issues/2026-06-10-roadmap-drift-and-stale-docs.md)).
> The one piece that did NOT ship — **kernel-freestanding TLS linkage** — is
> re-homed below as a bare-metal acceptance deliverable (it's the
> AGNOS-kernel goal's tracking home). The deep-dive's lower-severity
> hardening items (supply-chain integrity, verification coverage, atomics
> barriers, thread-stack guards) ride this minor's **bug-bandwidth** per the
> 2026-06-10 "urgent now in v6.1.x, rest spread" direction; the urgent set
> lands in the v6.1.x hardening tail (Phase F).

### Phase 0 (v6.2.x opening) — growable-region foundation

**Lands first, before bare-metal + RISC-V** (user direction 2026-06-11: pull
this earlier than the v6.3.x arc). Migrate the three pressure tables —
fn-tables, `fixup_tbl`, and codebuf — from fixed heap regions to vec-backed
`rp_vec` storage, using the recipe **proven byte-identical at v6.0.7** (the
`ret_patches` → `rp_vec` migration; output embeds no compiler heap addresses
and allocation order is input-deterministic, so self-host stays byte-identical).

**Why now, why first:**
- **Ahead of backend #7.** RISC-V (below) is the 7th backend; landing growable
  tables *before* it means the new backend inherits the vec-backed pattern
  instead of re-duplicating the fixed-cap pattern that would then need a second
  migration. Pay the structural cost once.
- **Ends the cap-raise treadmill.** Fixed caps have been raised ~1/minor
  (str_data / codebuf / `output_buf` 2 MB→16 MB @ .27); generics (v6.3.x) would
  blow them N× per instantiation. Growable storage removes the recurring
  cap-bump and the class of silent overruns the deep-dive found on unguarded
  emitters.
- **Resolves the heap-registry rot (AR-03).** The fixup-cap split-brain
  (262144 vs 1048576, ~12 MB unreachable), stale fn-table labels, and the
  undocumented overlapping region all clean up as part of the migration.
- **De-risks v6.3.x.** It was originally v6.3.x Phase-0 groundwork; pulling it
  into v6.2.x-open means the language arc opens onto already-growable tables.

**Keeps the fixed map for scalars/scratch** (perf-positive — no per-access
indirection where it isn't needed). Structural multi-backend change → ecb/cass +
the in-hand rv64 self-host reverify. Issues:
[`2026-06-10-monomorphization-substrate-prereqs.md`](issues/2026-06-10-monomorphization-substrate-prereqs.md)
(AR-02) + [`2026-06-10-memory-safety-parity-gaps.md`](issues/2026-06-10-memory-safety-parity-gaps.md)
(AR-03).

### v6.2.0 — Bare-metal target formalization

Codify the ad-hoc bare-metal mode that agnos has been using
since first boot into a first-class
`--target bare-metal-x86_64-elf` (and aarch64 peer) triple.
Seven deliverables:

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
7. **Kernel-freestanding TLS linkage** (re-homed from the shipped
   native-TLS arc) — a kernel object **links `lib/tls_native`
   freestanding** (no `libssl`, no `dlopen`, no `ld.so`/glibc TCB) and
   **passes the forbidden-module check**. The native stack already works
   in userland; this proves it compiles + links into a bare-metal/kernel
   object, which the libssl wrapper structurally cannot. This is the
   **AGNOS-kernel goal's tracking home** in the active cycle (it was
   previously tracked only inside the now-deleted TLS arc — finding RM-03).

**Acceptance**: rebuilding the agnos kernel with `--target
bare-metal-x86_64-elf` produces a byte-identical artifact to the
current ad-hoc build; forbidden-module check errors clearly when
bare-metal code pulls host-OS modules;
`examples/firmware-hello.cyr` demonstrates the target outside
of agnos; **a kernel object links `tls_native` freestanding and a
freestanding TLS handshake smoke runs in-kernel** (deliverable 7).

**Important framing**: bare-metal is **formalization, not
enablement** for the existing agnos boot — the kernel already builds
and boots without the formal triple. But deliverable 7 (freestanding
TLS link) IS net-new capability the AGNOS-kernel flagship needs:
in-kernel TLS is structurally impossible through the libssl wrapper, so
it gates *in-kernel networking*, even though it does not gate the agnos
MVP boot. Bare-metal is also a QoL feature for future bare-metal Cyrius
consumers (firmware, alt-kernels, embedded).

> **Cross-repo follow-on (filed):** full-binary kernel KASLR needs an
> AGNOS `--pie` boot harness — cyrius shipped the kernel-PIE ET_DYN
> wrapper (`EMITELF64_KERNEL`, v6.1.7); the harness ask is filed at
> `agnos/docs/development/issue/2026-06-10-cyrius-pie-boot-harness-ask.md`.
> Lands when the kernel team wires it; not v6.2.x-gating.

### v6.2.x — RISC-V rv64 backend

First-class RISC-V 64-bit target. The 4th platform peer after
x86_64 / aarch64 / PE-x86_64. Substrate prerequisites already
landed: typed-simd ABI (v5.x), REAL TYPE SYSTEM (v5.10.x),
struct-byval ABI (v5.10.x), parser-to-emit named-op refactor
(v5.11.x close).

> **Hardware is in hand** (user 2026-06-10: *"I have a bunch of hardware
> already; was waiting for RISC-V to do it"*). The rv64 box is the gating
> resource the original plan flagged as a procurement risk (finding RM-04)
> — it's already available, so the **real-hardware self-host gate is live
> from the start** (no QEMU-only interim, no purchase decision blocking arc
> entry). Wire it into the SSH verification fleet alongside pi/ecb/ach/cass
> at arc open.

**Scope**:
- New backend: `src/backend/riscv64/{emit,jump,fixup}.cyr`
- New stdlib syscall peer: `lib/syscalls_riscv64_linux.cyr`
- New cross-entry: `src/main_riscv64.cyr`
- New test runner: `qemu-riscv64-static` for the bring-up probes +
  the **in-hand rv64 hardware over SSH** for the self-host verify
- New CI matrix arm

**Acceptance gates**:
1. Cross-compiler `build/cycc_riscv64` emits valid rv64 ELF
   that `file(1)` identifies.
2. Single-syscall "exit 42" probe runs under
   `qemu-riscv64-static`.
3. Hello-world via `sys_write` + `sys_exit` runs under QEMU.
4. Self-host byte-identical on the **in-hand real rv64 hardware**
   (hardware-gated over SSH like the aarch64 ssh-pi check) — the
   non-negotiable cross-OS self-host gate, on real silicon.
5. `[release].cross_bins` in `cyrius.cyml` gets a
   `cycc_riscv64` entry.

### Native TLS stack — ✅ SHIPPED (v6.0.x), default at v6.1.21

The sovereign, pure-Cyrius TLS stack (`lib/tls_native.cyr`) that
originally anchored this minor **shipped in v6.0.x** and became the
**default** backend at v6.1.21 — full TLS 1.2 + 1.3, client + server,
over sigil primitives (AES-128/256-GCM + ChaCha20-Poly1305; ECDSA
P-256/P-384 + RSA PSS/PKCS#1 + Ed25519; X25519/ECDHE; EMS, ALPN, SNI +
OS-trust-store verify; Ed25519 server-cert parse @ v6.1.31). Live
Cloudflare HTTPS + OpenSSL interop proven; sandhi re-pointed onto it
(1.4.x). `lib/tls.cyr` now defaults to native; libssl is opt-out via
`-D CYRIUS_TLS_LIBSSL`.

**What remains of the original arc, and where it now lives:**
- **Kernel-freestanding link** → re-homed as **bare-metal deliverable 7**
  (above) — the one piece that genuinely did not ship.
- **TLS authn-hardening gaps** surfaced by the 2026-06-10 deep-dive — no
  EKU(serverAuth)/keyUsage/pathLen enforcement, no revocation, a
  connected-but-unverified-by-default native API (hostname skipped when
  `host==0`), and post-handshake records (NST/KeyUpdate) collapsing to a
  false EOF — land in the **v6.1.x hardening tail (Phase F)**, not here:
  CVE-17/18/30,
  [`issues/2026-06-10-tls-chain-verification-gaps.md`](issues/2026-06-10-tls-chain-verification-gaps.md)
  + [`issues/2026-06-10-tls-post-handshake-false-eof.md`](issues/2026-06-10-tls-post-handshake-false-eof.md).
  These are sovereignty + v7-public-release prerequisites for the default
  backend.
- **Entropy on the AGNOS target** — the native stack has no RNG source on
  agnos (no getrandom syscall). Cyrius-side routing lands in Phase F
  (CVE-19); the kernel syscall is filed upstream
  (`agnos/docs/development/issue/2026-06-10-cyrius-tls-entropy-syscall-gap.md`).

Memory pin: [[project_native_tls_arc_v6_2_x]] (now an arc retrospective).

### Scope shape (v6.2.x)

| Cluster | Indicative size |
|---|---|
| **Phase 0 — growable-region foundation** (fn-tables / fixup_tbl / codebuf → rp_vec; lands first, before backend #7) | ~5–7 |
| Bare-metal target formalization (7 deliverables incl. kernel-freestanding TLS link) | ~9–10 |
| RISC-V rv64 backend (new emit/jump/fixup + syscalls peer + real-hardware gate) | ~12–14 |
| Cross-arch test harness + CI matrix + rv64 SSH-host wiring | ~3–4 |
| Deep-dive hardening riding bug-bandwidth (supply-chain, verification, atomics, thread-stacks) | as surfaced |

Sizes are indicative, **not a budget cap** — minors flex long (**v6.0.x
ran to 91**) and the working rule (user 2026-06-10) is *"no worries about
patch size, just hardening and adding features."* Removing the phantom
native-TLS arc (~12–15 slots) makes this a **two-arc platform minor**
(bare-metal + RISC-V), not the three-arc giant the stale plan described.

**Priority within the minor** (revised 2026-06-10): native TLS already
shipped, so the old "native TLS > RISC-V / RISC-V is the split-out
candidate" call is **retired** — the budget pressure that made RISC-V a
split risk is gone. Both arcs stay: **bare-metal first** (it carries the
kernel-freestanding-TLS deliverable the AGNOS-kernel goal needs, and is
the compile prerequisite for any in-kernel crypto), then **RISC-V** (the
4th platform peer, now hardware-unblocked). No split planned;
premise-check at arc entry per [[feedback_premise_check_at_slot_entry]].

---

## v6.3.x — Language Refinements

**Theme**: language-level closures + generics + async sugar.
Three syntactic/semantic additions the v5.x cycle held out
explicitly (per 2026-05-12 tight-close).

Per user direction 2026-05-19: language work (mid-priority,
above ABI/perf) takes v6.3.x.

### Phase 0 — substrate prerequisites (added 2026-06-10, deep-dive)

The 2026-06-10 deep-dive found that the closures/generics work below
**assumes substrates that don't currently exist or are broken**. Per user
direction, these land as an explicit **phase 0 before any language feature**
(issue:
[`2026-06-10-monomorphization-substrate-prereqs.md`](issues/2026-06-10-monomorphization-substrate-prereqs.md)).
The third substrate (growable tables) was **pulled forward to v6.2.x opening**
(user 2026-06-11) so it's already in place; the two below remain here:

1. **Revive the monomorphization substrate (AR-01)** — the only call-site
   re-parse mechanism the no-AST single-pass design ever had, inline token
   replay (`SFBS`/`SFBE`, `parse_fn.cyr:2226`), is **dead**: `_INLINE_OK=0`
   on both x86 (`emit.cyr:166`) and aarch64 (`emit.cyr:2090`), disabled
   after ARM metadata corruption. Generics have nothing to build on until
   this is revived + hardened (prove on inline fns first, root-cause the
   ARM corruption).
2. **Order-independent call ABI (CO-01)** — forward calls read Str/SIMD
   masks + struct-ret that are only written at fn-def parse, so a call
   before its definition silently miscompiles with mask 0
   (`parse_fn.cyr:730,949,2036`). Generic instantiations reference each
   other in arbitrary order, so this MUST be fixed (fn-signature capture in
   the pass-1 prescan) before monomorphization — and it's a public-v7 trap
   regardless (C-style bottom-of-file definitions miscompile today).
3. **Growable pressure tables (AR-02)** — ✅ **moved to v6.2.x opening** (user
   2026-06-11). Migrates fn-tables / `fixup_tbl` / codebuf to the proven
   `rp_vec` recipe so generics don't blow the fixed caps N× per instantiation.
   Lands as the v6.2.x growable-region foundation (before backend #7), not here
   — so v6.3.x opens onto already-growable tables. This phase only *confirms*
   they're in place before monomorphization stresses them.

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
per-monomorph code. **Builds on Phase 0** (token-replay revival +
order-independent ABI + growable tables — none of which exist today).
Kavach was the original 1-vote consumer (per v5.x Language Refinements
table); re-verify pressure at slot entry per
[`feedback_premise_check_at_slot_entry`].

**Acceptance gates** (added 2026-06-10 — the deep-dive found the generics
slot had *no* acceptance bar, unlike optional-deps): a **self_compile
delta budget** (monomorphization must not blow compile time past a stated
ceiling — and the v6.5.x perf-refactor lands two minors later, so this
can't be deferred); **cap-headroom checks** on fn-tables / codebuf /
`output_buf` with pre-sized raises (or the Phase-0 growable migration
done first); and **instantiation dedup** (identical monomorphs emit once)
as a correctness + size criterion. See
[`issues/2026-06-10-monomorphization-substrate-prereqs.md`](issues/2026-06-10-monomorphization-substrate-prereqs.md).

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

### Scope shape (v6.3.x)

| Cluster | Indicative size |
|---|---|
| **Phase 0 — substrate** (token-replay revival + order-independent ABI + growable tables) | ~5–7 |
| Closures with lexical capture | ~7 |
| Real generic instantiation (on Phase 0) | ~7 |
| Language-level async/await syntax | ~5 |
| Required vs Optional Dependencies | ~5 |
| Cross-feature integration + tcyr suite | ~3 |

**Phase 0 is non-negotiable groundwork** — the deep-dive proved the
generics arc has no working substrate without it. Sizes indicative, not a
cap; minors flex long.

---

## v6.4.x — ABI + Perf Arc

**Theme**: Class B FFI / wgpu fncall6 ABI fix + register
allocation upgrade + deferred peephole passes.

Held-forward through v5.9.x / v5.10.x / v5.11.x. The
*language-level* ABI work plus the regalloc-gated perf passes
that have been waiting for cross-BB liveness data.

> **Arc-open prerequisite (added 2026-06-10, deep-dive):** the **runtime
> bench harness is blind** — an integer-µs truncation floor flat-lines
> 37/42 micro-benches at exactly 1000 ns since 2026-04-16 (`bench.cyr:235`,
> finding PF-01,
> [`issues/2026-06-10-runtime-bench-suite-blind.md`](issues/2026-06-10-runtime-bench-suite-blind.md)).
> The pinned "bench-delta evaluation" slot below **cannot measure**
> regalloc / copy-prop / DSE wins with 1 µs resolution. Fix the harness
> (fractional-µs print + the dead tool-compile loop + the 8 orphan `.bcyr`)
> **before this arc opens**, or the perf work flies blind. Also decide the
> regalloc substrate at arc entry (AR-04: extend the x86 byte-peephole vs.
> activate real IR-level register allocation — the latter is the only path
> to aarch64/riscv64 regalloc parity).

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

> **Prerequisite (added 2026-06-10):** this audit is only meaningful once
> the bench harness is fixed (PF-01 — the µs-resolution floor) and
> per-phase attribution is captured (PF-03 — `CYRIUS_PROF` exists since
> v5.10.0 but `bench-history.sh` never runs it, so 40+ runs since 06-08
> hold zero phase data). Both land before/at v6.4.x; by v6.5.x entry the
> cycle should have a phase-resolved self_compile trend, not just two
> endpoints. Also fold the `alloc()` single-threaded fast-path (PF-02 —
> the v6.0.64 unconditional spinlock cost ~3–6× on the dominant
> single-threaded case) into the perf surface. Issue:
> [`2026-06-10-runtime-bench-suite-blind.md`](issues/2026-06-10-runtime-bench-suite-blind.md).

### Slot estimate (v6.5.x)

Open scope at v6.5.x slot entry — depends on the
accumulated-growth shape uncovered during the audit phase.
Target: ~20 planned + 10 bug bandwidth = ~30 budget. Could flex
to 40+ if the perf-refactor surface is wider than expected.

---

## What comes after v6.x

**v6.x is not capped at 6 minors.** Per user direction 2026-06-11, the cycle
**grows further before any major bump** — v6.2.x–v6.5.x are pinned, but more
v6.x minors can follow (consumer pressure, language refinements, platform work)
before v7.0.0. v7 is *further out* than the original "6 minors" framing implied;
don't treat v6.5.x as the cycle's hard end.

v7.x scope is open. Known commitments per CLAUDE.md "Version
lives in `VERSION` + `--version`, never in binary names":

- **No binary rename at v7.0.0**. The v6.0.0 `cc5 → cycc` +
  `cyrc → cybs` rename was the LAST name-change penalty paid.
  Future major bumps run `version-bump.sh` and ship; no rename,
  no downstream sweep, no vidya `cc?` residue.
- **Prior-major slot rotates at v7.0.0**. **cc3 was already dropped at
  v6.1.0** (corrected 2026-06-10 — the v6.0.0 cut should have rotated
  cc3→cc5 but didn't, leaving cc3 a stale prior-PRIOR; v6.1.0 fixed it).
  The prior-major slot now holds **cc5** (the last v5.x top compiler,
  5.11.69). At v7.0.0 it rotates to the last v6.x `cycc` — same binary
  name, so the slot effectively retires (no rename bridge). [Earlier
  drafts here and in roadmap-future.md said "cc3 drops at v7.0.0" — that
  was the RM-05 contradiction with CLAUDE.md; fixed.]

### Usability / adoption readiness (added 2026-06-10; reframed 2026-06-11)

**Whether v7 is a *full public* release is an open question** (user 2026-06-11:
"sovereign and usage — whether its full public is still in question"). Sovereign
+ usable is the committed direction; a public launch ("Cyrius ONE" book +
installer aimed at strangers) is **NOT a fixed gate**. So treat the debt below
as **usability/adoption readiness** — worth paying to make the toolchain
pleasant for more users (the existing ecosystem included) — and de-coupled from
any committed public-launch date. The deep-dive surfaced it
([`docs/audit/2026-06-10-deep-dive-review.md`](../audit/2026-06-10-deep-dive-review.md)):

- **Licensing (LEGAL-01) — a hard blocker *if/when* it goes public** (and worth
  resolving regardless). The GPL-3.0-only stdlib is *source-included* into every
  consumer binary with no Runtime-Library-Exception → arguably forces GPL on all
  downstream binaries; and `sigil.cyr:533` elects the GPLv2-only leg of dual
  BSD/GPLv2 code (GPLv2-only is GPL-3-incompatible). Needs legal review + an
  RLE-style linking-exception decision.
- **Trust-story prerequisites (CVE-12/13/20/21).** Release signing +
  bootstrap attestation — the shipped `cycc` is the de-facto trust root,
  disjoint from the seed chain `bootstrap.sh` verifies, and releases are
  unsigned with mutable-tag deps. The sovereignty story can't go public
  like that.
- **Diagnostics + debug-info** for strangers: no DWARF on any target,
  crash-localization is x86-ELF-only, errors are first-error-exit with no
  column/excerpt.
- **stdlib-reference** covers ~65/88 modules — the rest need authoring.

Beyond that, v7.x is open territory. Likely candidates: more language
refinements based on consumer pressure from v6.x ship; toolchain
improvements (LSP / formatter / linter evolution); agnos v2.0 alignment
if AGNOS's roadmap creates pull.
