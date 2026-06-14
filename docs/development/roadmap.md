# Cyrius Development Roadmap — v6.2.x (active minor)

**Scope** — the **current active minor only** (v6.2.x — Platform
Expansion), opened at the v6.1.x → v6.2.0 cut (2026-06-12). This is the
slot-pinning working artifact. The rest of the v6.x cycle (framing,
budgeting, minors v6.2.x → v6.5.x, and the closed v6.0.x/v6.1.x
summaries) lives in [roadmap_6.md](roadmap_6.md); items beyond the cycle
(v7.0+ aspirations, unpinned language refinements, speculative work) live
in [roadmap-future.md](roadmap-future.md).

> **v6.1.x is CLOSED.** Its Backend-Codegen multi-arc shipped to .41 (PIE
> x86/aarch64, `.gnu.hash`, TS/TSX→JS emit, agnos-target HIGH-sev fixes,
> Windows pillar, TLS/alloc/LSP, bayan/ganita carve, Phase-F security
> hardening). Per-patch detail is the [`CHANGELOG.md`](../../CHANGELOG.md)
> source of truth; the arc summary is in [roadmap_6.md](roadmap_6.md). The
> v6.1.x items that did **not** land are carried forward below under
> [Carry-in from v6.1.x](#carry-in-from-v61x-unpinned).

> **Reading order**: this file (active minor) →
> [roadmap_6.md](roadmap_6.md) (rest of the v6.x cycle) →
> [roadmap-future.md](roadmap-future.md) (beyond v6.x).

## See also

- [roadmap_6.md](roadmap_6.md) — the **whole v6.x cycle** reference
  (framing, per-minor budgeting, v6.2.x → v6.5.x, the closed v6.0.x +
  v6.1.x summaries).
- [roadmap-future.md](roadmap-future.md) — long-term watching list.
- [cycle-discipline.md](cycle-discipline.md) — durable operating
  principles (slot acceptance, bottom-to-top priority, premise-check at
  slot entry, cross-host smoke, cycle-close shape).
- [state.md](state.md) — volatile current state (version, cycc size,
  in-flight slot, recent shipped patches). Refreshed every release.
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth.

---

## v6.2.x — Platform Expansion

**Theme**: 4th platform peer (RISC-V rv64) + bare-metal target
codification, opened onto a growable-region compiler foundation. A
two-arc platform minor (bare-metal first — it carries the
kernel-freestanding-TLS deliverable the AGNOS-kernel goal needs — then
RISC-V, now hardware-unblocked). Substantial new-code minor.

Per cycle discipline: premise-check each arc at slot entry
([[feedback_premise_check_at_slot_entry]]); cross-arch propagation is
mandatory for any compiler-emit change
([[feedback_cross_arch_propagation_mandatory]]); 4-host cross-OS
self-host verify before every cut, even lib-only work
([[feedback_cross_os_verify_always_even_lib]],
[[reference_verification_hosts_ssh]]); benchmark every release
([[feedback_benchmark_every_release]]). Window open to change
([[feedback_minor_window_at_arc_open]]) — minors flex long (v6.0.x ran
to 91; "no worries about patch size, just hardening and adding
features", user 2026-06-10).

---

## Pinned slot sequence

| Slot | Item | Phase |
|---|---|---|
| **v6.2.0** ✅ | **Phase 0 — growable-region foundation** (ends the cap-raise treadmill + AR-03 split-brain): `fixup_tbl` → `_fixup_base`/grow (64M ceiling), fn-tables (16 parallel tables + 2 hashes + `live[]` → `_fnt_*`/`_fnt_cap`, grow+rehash, 32768 ceiling; was at 79 % of 8192), codebuf → `_codebuf_base`/grow (64 MiB). **+ `cyrius init` CI/release alignment** (canonical `install.sh` one-liner, `git archive` source tarball + `SHA256SUMS`, `VERSION` as single source of truth). Each migration byte-identical + forced-grow on x86 **and** real-ARM (pi) + check.sh 89/89 + cross-OS 4/4. | 0 — substrate |
| **v6.2.1** ✅ | **Element-typed fixed arrays `var a: T[N]`** — resolves the address-taken-local byte-vs-slot footgun (daimon route-404). `i64[N]` is the unambiguous SLOT spelling (fixes the `store64(&a+i*8)` idiom), `u8[N]` an explicit byte buffer; widths i8..i64/u8..u64/u128. Pure frontend (element width → var-size table → every backend inherits it). + daimon-class slot-array sweep: 10 cyrius-owned sites (5 in cycc itself via two-step bootstrap, 5 native stdlib). | 0 — language/safety |
| **v6.2.2** ✅ | **aarch64/macOS annotation-token codegen fix + ecosystem stdlib fold-in.** The fn-attribute tokens (109/122/124/125/126/127 — `#regalloc`/`#must_use`/`#deprecated`/`#pure`/`#io`/`#alloc`) were only consumed in `main.cyr`; the 3 non-x86 forks dropped an annotated fn into their catchall, leaving the next `enum` unregistered → `error: unexpected enum` (blocked `bayan` on aarch64+macOS). Ported the consume into **both** pass-1 + pass-2 of `main_aarch64.cyr` / `main_aarch64_macho.cyr` / `main_x86_macho.cyr` (consume-and-ignore; opts gated off per CO-03). x86 cycc byte-identical. **+** re-folded all 12 vendored `lib/*.cyr` to released 6.2.1-pinned versions; api-surface re-snapshotted (4236 fns, +26/−1). qemu exit-0 + cross-OS 4/4 + check.sh 89/89. | 0 — frontend/fold |
| **v6.2.3** ✅ | **AGNOS net/entropy/clock syscall peer (#45–#55) — the TLS + net-tools enabler.** Mirrors the eleven ring-3 syscalls AGNOS 1.45.0–1.45.4 froze into the `CYRIUS_TARGET_AGNOS` stdlib peer (`sys_time_unix`/`sock_*`/`udp_*`/`icmp_echo`; `sys_getrandom` un-fail-closed → #45). **Option A** (surgical adapter): tagged fd↔conn_id table routes the BSD-shaped `net`/`tls_native`/`http` (which bottom out at `sys_read`/`write`/`close`) onto the conn_id model, source-identical. **+ discovered prereq:** `lib/thread_agnos.cyr` single-threaded threading serial-fallback (tls→sigil→thread.cyr; agnos has no clone/futex) with TLS save/zero/restore around inline workers. Pure stdlib + agnos-`#ifdef`-gated → x86 cycc byte-identical. http/net/dig/yo + tls_native now build for agnos. 13-agent adversarial review caught 2 real bugs pre-cut. | agnos-target |
| **v6.2.4** ✅ | **TLS transport-vtable refactor (Option C).** Decoupled `tls_native` from raw `sys_read`/`sys_write`/`_tn_now_unix` via a **module-global** transport vtable (3 fn-ptr globals, 0=default; `tls_native_set_transport` setter) routed in the 2 leaf I/O helpers + `_tn_now_unix`; per-conn handle still flows via `TLS_CTX_OFF_SOCK_FD`. **Global over per-ctx deliberately** → ZERO change to the 25 `_tn_sock_*` call sites (a missed site is impossible by construction; the 6.2.3 `sock_connect` near-miss class), and the 1.2 driver + app-data I/O ride the same leaf helpers (covered free). Strictly logic-preserving (all TLS gates green; default byte-identical; cycc byte-identical). Hermetic `tls_native_transport_vtable.tcyr` proves the dispatch. Unblocks the bare-metal kernel-freestanding-TLS slot (the kernel plugs its TCP send/recv). 4-agent review: no real bugs. | agnos-target / refactor |
| **v6.2.5** ⏳ | **`tls_native.cyr` full module split + cleanup** (user-directed, 2026-06-14) — the 5,786-line monolith is a liability (a missed I/O site is a silent hole — see the 6.2.3 `sock_connect` near-miss). Carve into focused modules: `tls_native_transport.cyr` (the 6.2.4 vtable + `_tn_sock_*`), `tls_native_record.cyr` (record layer / AEAD seal-open), `tls_native_hs13.cyr` (TLS 1.3 client+server handshake), `tls_native_hs12.cyr` (TLS 1.2 driver), `tls_native_x509.cyr`/verify, with `tls_native.cyr` the thin include-hub + public API. **STRICTLY logic-preserving** — pure fn-relocation, zero behavior change; the [[feedback_logic_preserving_refactor_verification]] recipe is the gate (old-vs-new corpus cmp + DCE-torture + unchanged self-compile + Linux TLS live round-trip + agnos build + cross-OS). Lands AFTER 6.2.4 so the carve operates on already-clean transport code. Fits the v6.x lib-streamlining arc. | refactor / lib-streamlining |
| **v6.2.x** ⏳ | **Bare-metal target formalization** — codify the ad-hoc bare-metal mode (agnos has used since first boot) into a first-class `--target <arch>-bare-metal-elf` triple. 7 deliverables: target triple, ELF no-libc output (no PT_INTERP/DT_NEEDED/libc-init `_start`), interrupt-handler emit conventions (`naked_fn`), no-runtime-assumptions codegen, **kernel-freestanding TLS linkage** (the AGNOS-kernel crypto prereq — consumes the v6.2.4 transport vtable), linker-script/section control, and the cross-OS + agnos boot acceptance gate. Bottom-to-top priority — lands before RISC-V. | bare-metal |
| **v6.2.x** ⏳ | **RISC-V rv64 backend** — 4th platform peer (hardware in-hand). New `backend/riscv/{emit,jump,fixup}.cyr` + syscalls peer + real-hardware self-host gate (SSH-host wiring). Inherits the v6.2.0 growable-region pattern (no fixed-cap re-duplication). | RISC-V |

> **Indicative sizes** (roadmap_6.md, not a budget cap): bare-metal ~9–10,
> RISC-V ~12–14, cross-arch harness/CI ~3–4. Deep-dive hardening rides
> bug-bandwidth as surfaced.

---

## Next items — frontend / DX hardening (pull into a v6.2.x later line)

Not yet pinned to a slot; land on a bug-bandwidth line or fold into an
adjacent compiler change.

- **DRY the four pass-1/pass-2 top-level scanners** (`main.cyr`,
  `main_aarch64.cyr`, `main_aarch64_macho.cyr`, `main_x86_macho.cyr`). The
  v6.2.2 `unexpected enum` fix was the **3rd instance** of an annotation
  token (or any new top-level token) landing on only one fork's scanner
  (v5.8.20 `#io`, now v6.2.2 `#pure`). Each fork hand-maintains a parallel
  pass-1 pre-scan + pass-2 parse loop; a 7th annotation token, or any new
  top-level construct, will desync again. Extract the token-dispatch into a
  shared `common/`-hosted helper (mirror the v6.1.4/.5 `_emit_fmt`/DCE
  hoist pattern) so the cases live in one place. Logic-preserving →
  byte-identical self-host on all 4 hosts is the gate. MEDIUM (DX /
  recurring-bug-class). See [[project_v622_annotation_fork_desync]].
- **Undefined-function call should hard-error, not emit `ud2`.** A call to
  a missing fn compiles with `exit 0` + a warning, then SIGILLs at runtime
  — so a consumer that didn't migrate to a carved sibling (e.g. bayan)
  ships a "successful" build of a crashing binary, repeatedly misdiagnosed
  as a toolchain bug. Make a *reachable* undefined-fn call a hard compile
  error; keep genuinely-dead undefined stubs as warnings (so the cass
  self-host's `fmt_int_buf` doesn't break). High DX value — ends the
  silent-ud2/SIGILL class. (Carried from the v6.2.0-open carry list.)
- **Local-array byte-vs-slot convention decision.** Largely resolved by the
  v6.2.1 `var a: T[N]` slot spelling, but the *bare* `var a[N]` convention
  (local = N bytes, global = N slots) remains a latent footgun. Decide:
  lint the address-taken-per-slot idiom on a bare local array, or audit
  stdlib/consumers for remaining bare-array slot writes. MEDIUM (DX).
  [`issues/2026-06-11-addr-taken-local-array-static-underreserve.md`](issues/2026-06-11-addr-taken-local-array-static-underreserve.md).
- **Permanent syscall-write byte-length gate** — the `.39` audit missed a
  multi-line syscall (single-line regex); make the byte-length check a
  standing gate using DOTALL. (Carried from v6.2.0-open.)

---

## Carry-in from v6.1.x (unpinned)

v6.1.x items that did **not** land — they ride the bug-bandwidth budget,
landing on consumer pressure or explicit user direction
([[feedback_no_unilateral_scope_decisions]]), not as pinned releases.

- **Kernel-PIE ELF boot-test for AGNOS KASLR.** The RIP-relative codegen +
  `ET_DYN` `EMITELF64_KERNEL` wrapper **shipped v6.1.7** (structurally
  validated, never boot-tested). **Consumer-gated** on an AGNOS `--pie`
  boot harness (won't ship blind); the harness ask is filed
  (`agnos/.../2026-06-10-cyrius-pie-boot-harness-ask.md`). AGNOS isn't
  pulling yet (data-only KASLR @ v1.28.0). [[project_v616_bugband_then_full_pie]].
- **x86-macOS usable-toolchain arc tail.** Phase 1 (argv prologue) shipped
  v6.1.30; remaining `ach`-gated layers: env reading (`HOME`/uname), the
  wrapper's macOS arch-default (detect x86 on Intel), cycc-finding, the
  layer-6 native self-compile miscompile (tools ship cross-built until
  fixed), packaging. **`ach` is the supported macOS-x86 verify host**; the
  v6.2.2 `main_x86_macho.cyr` annotation fix is verified there
  (`SELFHOST_OK`).
  [`issues/2026-06-02-macos-x86-release-no-compiler.md`](issues/2026-06-02-macos-x86-release-no-compiler.md),
  [`issues/2026-06-07-x86-macho-byte-array-literal-no-compile.md`](issues/2026-06-07-x86-macho-byte-array-literal-no-compile.md).
- **Cyim regex unblock** (mabda C6) — consumer-gated; lands when cyim
  updates + re-tests against v6.x.

---

## Deep-dive hardening spread (rides v6.2.x+ bug-bandwidth)

From the 2026-06-10 deep-dive review
([`docs/audit/2026-06-10-deep-dive-review.md`](../audit/2026-06-10-deep-dive-review.md)).
The urgent set landed in the v6.1.x Phase-F tail (CVE-14/15/16/17/18/19/22/
23/24/25/26/27/28/30/31, CO-02/03, AR-03 — all shipped v6.1.33–.41). The
remainder spreads here and to later minors per "urgent now, rest spread":

- **Release / trust-chain integrity** (CVE-20/21) — v6.2.x bug-bandwidth +
  the v7 trust-story.
- **Thread-stack guards** (CVE-29) — v6.2.x.
- **Verification coverage** (VR-01…04) — VR-03 differential corpus gates
  v6.4.x; the rest as surfaced.
- **Monomorphization substrate** (AR-01 / CO-01) — v6.3.x Phase-0 (AR-02
  growable tables already landed at v6.2.0).
- **v7 readiness gates** (LEGAL-01 licensing, diagnostics) — tracked for
  the v7 cut.

Audit cadence + the CVE-09…13 re-file tail:
[overdue-security-audit-cve-tail](issues/2026-06-10-overdue-security-audit-cve-tail.md)
— this deep-dive IS the overdue full audit.
