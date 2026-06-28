# Cyrius Development Roadmap — v6.3.x (active minor)

**Scope** — the **current active minor only** (v6.3.x — Language
Refinements), opened at the v6.2.x → v6.3.0 cut (2026-06-28). This is the
slot-pinning working artifact: the **proposed v6.3.x release workflow**
(the eight-release sequence below). The *fuller* per-cluster design (closures
/ generics / async / native-float), the rest of the cycle (v6.4.x → v6.6.x),
and the closed-minor summaries live in [roadmap_6.md](roadmap_6.md).

> **v6.3.0 shipped** the var-family growable migration — the last fixed
> compile-time cap (closes the v6.2.0 Phase-0 / AR-03 growable-region arc).
> See [CHANGELOG.md](../../CHANGELOG.md).

> **v6.2.x is CLOSED** (Platform Expansion — bare-metal core + dependency-model
> lever 1; shipped .0 → .52). **v6.1.x CLOSED** (Backend Codegen multi-arc,
> .0 → .41). **v6.0.x CLOSED** (Language Cleanup + Stdlib + Native TLS, .0 → .91).
> Per-slot detail is canonical in [CHANGELOG.md](../../CHANGELOG.md); the
> closed-minor summaries live in [roadmap_6.md](roadmap_6.md).

> **Reading order**: this file (active-minor release workflow) →
> [roadmap_6.md](roadmap_6.md) (full v6.x cycle + fuller v6.3.x cluster
> design) → [roadmap-future.md](roadmap-future.md) (beyond v6.x).

## See also

- [roadmap_6.md](roadmap_6.md) — the **whole v6.x cycle** reference
  (framing, per-minor budgeting, the fuller v6.3.x cluster design,
  v6.4.x → v6.6.x, the closed v6.0.x / v6.1.x / v6.2.x summaries).
- [roadmap-future.md](roadmap-future.md) — long-term watching list.
- [cycle-discipline.md](cycle-discipline.md) — durable operating
  principles (slot acceptance, bottom-to-top priority, premise-check at
  slot entry, cross-host smoke, cycle-close shape).
- [state.md](state.md) — volatile current state (version, cycc size,
  in-flight slot, recent shipped patches). Refreshed every release.
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth.

---

## v6.3.x — Language Refinements

**Theme**: the language-level trio the v5.x cycle held out explicitly —
**closures with lexical capture, real generic instantiation
(monomorphization), and async/await sugar** — gated behind a **Phase 0
substrate** prerequisite. Native-float Tier A continues here. Riding the
language minor: the **dependency-model lever 2** (Required/Optional deps) and
the **bare-metal design-deliverable tail** (#5/#6/#7), both pinned in 2026-06-27.

Per-cluster design (scope, acceptance bars, touched surfaces) is in
[roadmap_6.md § v6.3.x](roadmap_6.md). This file pins what we execute now.

**Near-term committed focus** (the opening releases → **v6.3.1–.3** in the
workflow below, in order):

1. **Required vs Optional Dependencies (lever 2)** — the scoping layer on top
   of the v6.2.x modules/groupings foundation (lever 1). [v6.3.1]
2. **Undefined-fn reachable-call hard-error** — bundled with lever 2 (safe
   only once cross-module refs are resolvable / declarable-optional). [v6.3.1]
3. **Bare-metal deliverable completion (#5/#6/#7)** — the structured pass over
   the three open bare-metal *design* deliverables, split #5+#6 then #7. [v6.3.2–.3]

Per cycle discipline: premise-check each arc at slot entry
([[feedback_premise_check_at_slot_entry]]); cross-arch propagation is
mandatory for any compiler-emit change
([[feedback_cross_arch_propagation_mandatory]]); 4-host cross-OS self-host
verify before every cut, even lib-only work
([[feedback_cross_os_verify_always_even_lib]],
[[reference_verification_hosts_ssh]]); seed-derive after any `src/` change
([[feedback_seed_derive_mandatory_cybs_limits]]); benchmark every release
([[feedback_benchmark_every_release]]). Window open to change
([[feedback_minor_window_at_arc_open]]) — minors flex long.

---

## v6.3.x release workflow (proposed sequence)

Eight releases, derived 2026-06-28 from a 3-lens sequencing pass
(dependency-topological / bottom-to-top-consumer-pressure / risk-first) +
your three sequencing decisions (recorded below). The spine honors your
stated near-term order **A+B → C**, gates generics behind the non-negotiable
Phase-0 substrate, and lands the language trio last (weakest live consumer
pull). Sizes indicative; minors flex long. **v6.3.x is expected to grow well
beyond these eight** (user 2026-06-28): this is the committed spine, and
issue-repairs + items that become necessary get pulled in as they surface
through the minor — inserted between or alongside these releases, not capping
them. Only the user re-scopes ([[feedback_no_unilateral_scope_decisions]]);
reactive pull-ins follow the bare-metal open-window pattern
([[feedback_bare_metal_open_reactive_window]]). Per-cluster design lives in
[roadmap_6.md § v6.3.x](roadmap_6.md).

| Release | Content | Folds / riders | ~bites |
|---|---|---|---|
| **v6.3.0** ✅ | **var-family growable migration** — SEVEN `vcnt`-indexed tables → `_base` + chained `_var_grow` (byte-identical under cap). Closes the v6.2.0 Phase-0 / AR-03 arc — last fixed compile-time cap. | — | shipped |
| **v6.3.1** | **Deps lever 2 (A)** — `optional = true` + `[features]` + `--features`/`--no-default-features` + platform-conditional `target=` keys (axes combine; builds on lever 1) **+ undefined-fn reachable-call hard-error (B), default-on** — bundled because B is unsafe until A lets loosely-coupled builds declare cross-module refs optional. [[project_v6_3_x_required_optional_deps]], [`issues/…undefined-fn-reachable-call-hard-error.md`](issues/2026-06-25-undefined-fn-reachable-call-hard-error.md). | DRY the 4 pass-1/pass-2 scanners (B edits them) | ~8 |
| **v6.3.2** | **Bare-metal #5 + #6 (C-1)** — `#5` `[sections]` linker/section-placement block in `cyrius.cyml`; `#6` inline-asm primitive completion (`cli`/`sti`/`hlt`, port I/O, `mfence`/`lfence`/`sfence`, `cpuid` — beyond `asm{}`+`iretq`/`eret` shipped .28). `issues/2026-06-19-naked-fn-safety-and-inline-asm.md`. | opt-in bounds-checked `store*`/`load*` (`CYRIUS_BOUNDS=1`, OFF) | ~5 |
| **v6.3.3** | **Bare-metal #7 (C-2)** — kernel-freestanding `lib/tls_native` link + in-kernel handshake smoke (cyrius-side link + smoke; *live* in-kernel boot stays AGNOS-consumer-gated). | syscall-write byte-length gate (DOTALL); kernel load-base settability rider (`issues/2026-06-19-kernel-load-base-settable.md`) | ~5 |
| **v6.3.4** | **Phase 0 substrate (D)** — AR-01 monomorphization token-replay revival (`_INLINE_OK=0` dead; **root-cause the ARM metadata corruption**, harden) + CO-01 order-independent call ABI (pass-1 fn-signature prescan). AR-02 growable tables already in place. Non-negotiable groundwork before generics. [`issues/…monomorphization-substrate-prereqs.md`](issues/2026-06-10-monomorphization-substrate-prereqs.md). | local-array bare `var a[N]` slot-write lint (prescan territory) | ~7 |
| **v6.3.5** | **Closures with lexical capture (E)** — closure literals + lexical-capture analysis + closure-env lowering (allocate-on-construct, vtable-shaped indirect call). The capture substrate async (G) reuses. | — | ~7 |
| **v6.3.6** | **Real generic instantiation / monomorphization (F)** — type-param recognition + emit-time substitution + instantiation dedup, on Phase 0. **HARD self_compile delta budget as a release gate** (perf-refactor is v6.5.x, 2 minors out — cost can't defer). | — | ~7 |
| **v6.3.7** | **Async/await (G)** — `async fn`/`await` → CPS state machines over the epoll runtime (captures across await reuse E's env lowering) **+ native-float Tier A tail (H)** — aarch64 NEON + f32/conversions (f64 type+operators+NaN shipped .18/.19/.41). | x86-macOS usable-toolchain tail (ach-gated) | ~8 |
| **v6.3.8** | **Closeout** — cross-feature integration tcyr (generic closures, async closures capturing a generic) + the minor-close pass (heap-map audit, dead-code, refactor, code-review, cleanup, doc/vidya sync). Ships code, not docs-only. | — | ~4 |

**Per-release gates & risks** (the places these bite):

- **v6.3.1 (B blast radius):** gate on **all 192 `.tcyr` green under default-on
  hard-error WITH lever-2 resolution** + `mabda`-without-`samvada` builds. If any
  can't be made green, that's **STOP-and-ASK**, not a quiet `--allow-undef` sprinkle
  (one-bug-one-complete-fix). Manifests round-trip + pre-existing manifests
  byte-identical.
- **v6.3.2 (#6 cross-arch emit, ABI-leak class):** disasm-verify each primitive on
  x86 **and** aarch64; guard x86-privileged ops (`cli`/`sti`/`hlt`/`in`/`out`/`cpuid`)
  on non-x86 paths; 4-host self-host mandatory — a green CI check is **not**
  verification.
- **v6.3.4 (cycle's load-bearing unknown):** AR-01 must **root-cause** the ARM
  metadata corruption that disabled `_INLINE_OK`, not paper over it — regression
  probe proving correct emit on **real pi** (aarch64-native tcyr). If un-revivable,
  surface it (it gates generics).
- **v6.3.6 (perf cliff):** the self_compile budget is a **hard** gate with in-scope
  dedup + cap-headroom — the v6.x cycle already ate a +65 % growth-tax once.
- **Every release:** seed-derive after any `src/` change (cybs limits — small fns,
  no tail calls; the v6.3.0 seed-break lesson, [[feedback_seed_derive_mandatory_cybs_limits]]),
  bench delta in CHANGELOG, 4-host cross-OS for emit changes, premise-check at entry.

**Sequencing decisions on record (user, 2026-06-28):** (1) Phase-0 substrate lands
**after** bare-metal (your literal A+B → C order), not as an early risk-spike;
(2) the **full** language trio (closures + generics + async) executes inside v6.3.x;
(3) bare-metal splits **#5+#6 then #7** (isolates the cross-arch emit change from the
stdlib-link for cleaner verification).

**Open inputs (pin at slot entry, not blocking):** the v6.3.6 self_compile ceiling
number (current ~508 ms, 500–549 ms jitter band) and the expected v6.3.x patch count
(minor-window convention, for packing density).

---

## Open carry-in / DX hardening (ride bug-bandwidth)

Not pinned to a slot — these land on a bug-bandwidth line, fold into an
adjacent compiler change, or move on consumer pressure / explicit user
direction ([[feedback_no_unilateral_scope_decisions]]), not as standalone
releases.

- **DRY the four pass-1/pass-2 top-level scanners** (`main.cyr`,
  `main_aarch64.cyr`, `main_aarch64_macho.cyr`, `main_x86_macho.cyr`). The
  v6.2.2 `unexpected enum` fix was the **3rd instance** of a new top-level
  token landing on only one fork's scanner (v5.8.20 `#io`, v6.2.2 `#pure`).
  Each fork hand-maintains a parallel pass-1 pre-scan + pass-2 parse loop; a
  7th annotation token, or any new top-level construct, will desync again.
  Extract the token-dispatch into a shared `common/`-hosted helper (mirror the
  v6.1.4/.5 `_emit_fmt`/DCE hoist pattern). Logic-preserving → byte-identical
  self-host on all 4 hosts is the gate. MEDIUM (DX / recurring-bug-class).
  See [[project_v622_annotation_fork_desync]].
- **Local-array byte-vs-slot convention decision.** Largely resolved by the
  v6.2.1 `var a: T[N]` slot spelling, but the *bare* `var a[N]` convention
  (local = N bytes, global = N slots) remains a latent footgun. Decide: lint
  the address-taken-per-slot idiom on a bare local array, or audit
  stdlib/consumers for remaining bare-array slot writes. MEDIUM (DX).
  [`issues/2026-06-25-bare-local-array-slot-write-lint.md`](issues/2026-06-25-bare-local-array-slot-write-lint.md).
- **Permanent syscall-write byte-length gate** — the `.39` audit missed a
  multi-line syscall (single-line regex); make the byte-length check a
  standing gate using DOTALL.
  [`issues/2026-06-25-syscall-write-byte-length-gate.md`](issues/2026-06-25-syscall-write-byte-length-gate.md).
- **Opt-in bounds-checked `store*` / `load*`** (added 2026-06-22 from a
  downstream report). An OFF-by-default `CYRIUS_BOUNDS=1` / `#bounds` sanitizer
  that guards each raw `store*`/`load*` against the heap-map live regions and
  aborts `_vec_die`-style instead of corrupting silently. Design + open
  questions in [roadmap_6.md § "Opt-in bounds-checked memory primitives"](roadmap_6.md).
- **x86-macOS usable-toolchain arc tail.** Phase 1 (argv prologue) shipped
  v6.1.30; remaining `ach`-gated layers: env reading (`HOME`/uname), wrapper
  macOS arch-default, cycc-finding, the layer-6 native self-compile miscompile
  (tools ship cross-built until fixed), packaging. `ach` is the supported
  macOS-x86 verify host.
  [`issues/2026-06-02-macos-x86-release-no-compiler.md`](issues/2026-06-02-macos-x86-release-no-compiler.md).
- **Cyim regex unblock** (mabda C6) — consumer-gated; lands when cyim updates
  + re-tests against v6.x.

---

## Deep-dive hardening spread (rides v6.3.x+ bug-bandwidth)

From the 2026-06-10 deep-dive review
([`docs/audit/2026-06-10-deep-dive-review.md`](../audit/2026-06-10-deep-dive-review.md)).
The urgent set landed across v6.1.x Phase-F (CVE-14…31, CO-02/03, AR-03) and
v6.2.x (CVE-20/21 trust-chain .30/.31 + seed→cybs→cycc derivation, CVE-29
thread-stack guard .44, CVE-32 modular-resolver closeout .51). The remainder
spreads here and to later minors per "urgent now, rest spread":

- **Monomorphization substrate** (AR-01 / CO-01) — **v6.3.x Phase 0** (the
  growable-tables half, AR-02, already landed v6.2.0 / v6.3.0).
- **Verification coverage** (VR-01…04) — VR-01/02 shipped v6.2.29; VR-03
  differential corpus gates v6.4.x; the rest as surfaced.
- **v7 readiness gates** (LEGAL-01 licensing, diagnostics) — tracked for the
  v7 cut.

Audit cadence + the CVE-09…13 re-file tail:
[overdue-security-audit-cve-tail](issues/2026-06-10-overdue-security-audit-cve-tail.md)
— this deep-dive IS the overdue full audit.
