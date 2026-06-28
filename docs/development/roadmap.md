# Cyrius Development Roadmap — v6.3.x (active minor)

**Scope** — the **current active minor only** (v6.3.x — Language
Refinements), opened at the v6.2.x → v6.3.0 cut (2026-06-28). This is the
slot-pinning working artifact: the **near-term committed v6.3.x work**.
The *fuller* v6.3.x arc (per-cluster design for closures / generics / async /
native-float), the rest of the cycle (v6.4.x → v6.6.x), and the closed-minor
summaries live in [roadmap_6.md](roadmap_6.md).

> **v6.3.0 shipped** the var-family growable migration — the last fixed
> compile-time cap (closes the v6.2.0 Phase-0 / AR-03 growable-region arc).
> See [CHANGELOG.md](../../CHANGELOG.md).

> **v6.2.x is CLOSED** (Platform Expansion — bare-metal core + dependency-model
> lever 1; shipped .0 → .52). **v6.1.x CLOSED** (Backend Codegen multi-arc,
> .0 → .41). **v6.0.x CLOSED** (Language Cleanup + Stdlib + Native TLS, .0 → .91).
> Per-slot detail is canonical in [CHANGELOG.md](../../CHANGELOG.md); the
> closed-minor summaries live in [roadmap_6.md](roadmap_6.md).

> **Reading order**: this file (active-minor near-term slots) →
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

**Near-term committed focus** (the primary v6.3.x work, in order):

1. **Required vs Optional Dependencies (lever 2)** — the scoping layer on top
   of the v6.2.x modules/groupings foundation (lever 1).
2. **Undefined-fn reachable-call hard-error** — bundled with lever 2 (safe
   only once cross-module refs are resolvable / declarable-optional).
3. **Bare-metal deliverable completion (#5/#6/#7)** — the structured pass over
   the three open bare-metal *design* deliverables.

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

## Pinned slot sequence

| Slot | Item | Phase |
|---|---|---|
| **v6.3.0** ✅ | **var-family growable migration** — the "var table" is a FAMILY of SEVEN `vcnt`-indexed tables; relocated to `_base` + chained `_var_grow` with an SVCNT grow-check (byte-identical under cap; verified via seed-derive + 8300-var grow gate). Closes the v6.2.0 Phase-0 / AR-03 arc — the last fixed compile-time cap. | 0 — substrate |
| **v6.3.x** (pinned) | **Required / Optional Dependencies — dependency-model LEVER 2.** Cargo-style `optional = true` + `[features]` table + `--features`/`--no-default-features` CLI, **and** platform-conditional `target = "<arch\|os>"` keys on `[deps.<name>]` (axes combine). Builds on lever 1 (modules + `[groups]`, shipped v6.2.46–.50). First consumer: profile-scoped includes (rosnet `lib.gpu`/`lib.cpu`). Pre-existing manifests build byte-identical; consumer migration opt-in. Design + schema + acceptance bar: [roadmap_6.md § "Required vs Optional Dependencies"](roadmap_6.md); [[project_v6_3_x_required_optional_deps]], [[project_lib_profile_includes_arc]]. | deps / packaging |
| **v6.3.x** (pinned, bundled with lever 2) | **Undefined-fn reachable-call hard-error (default-on).** Designed + verified in a v6.2.44 spike, then pulled back: a *default* hard-error breaks loosely-coupled consumer builds (e.g. mabda-without-samvada) until cross-module refs are resolved/declarable-optional — exactly what lever 2 provides. Dead/unreachable stubs stay warnings. Bundle here where it's safe. [`issues/2026-06-25-undefined-fn-reachable-call-hard-error.md`](issues/2026-06-25-undefined-fn-reachable-call-hard-error.md). | frontend / safety |
| **v6.3.x** (pinned) | **Bare-metal deliverable completion (#5/#6/#7)** (user 2026-06-27 — "revisit / fix during 6.3.x"). Numbered per the v6.2.x seven-deliverable design list (NOT the .27/.28 shipped-slot D-labels): **#5** `[sections]` linker-script / section-placement block in `cyrius.cyml`; **#6** inline-asm primitive completion (`cli`/`sti`/`hlt`, port I/O, memory barriers, `cpuid` — beyond the `asm{}`+`iretq`/`eret` that shipped at .28); **#7** kernel-freestanding `lib/tls_native` link + in-kernel handshake smoke (cyrius-side link + smoke schedulable; the *live* in-kernel boot stays AGNOS-consumer-gated). Riding alongside: kernel **load-base settability** (`issues/2026-06-19-kernel-load-base-settable.md`) + the kernel-PIE live boot (gnoboot-gated). Detail: [roadmap_6.md § "Bare-metal deliverable completion"](roadmap_6.md); `issues/2026-06-19-naked-fn-safety-and-inline-asm.md`. | bare-metal |
| **v6.3.x** (fuller arc — design in roadmap_6.md) | **The language trio + native-float**, pinned for the minor but not in the near-term execution set: **Phase 0 substrate** (monomorphization token-replay revival AR-01 + order-independent call ABI CO-01; growable tables AR-02 already in place) → **closures with lexical capture** → **real generic instantiation** (on Phase 0) → **async/await syntax** → **native-float Tier A** (f64/f32 — partially shipped v6.2.18/.19). Phase 0 is non-negotiable groundwork (the deep-dive proved generics have no working substrate without it). Per-cluster scope + acceptance gates: [roadmap_6.md § v6.3.x](roadmap_6.md), [`issues/2026-06-10-monomorphization-substrate-prereqs.md`](issues/2026-06-10-monomorphization-substrate-prereqs.md). | language |

> **Indicative sizes** (from [roadmap_6.md § "Scope shape (v6.3.x)"](roadmap_6.md), not a cap):
> Phase 0 ~5–7 · closures ~7 · generics ~7 · async ~5 · native-float Tier A ~5 ·
> Required/Optional deps ~5 · bare-metal #5/#6/#7 ~4–6 · cross-feature integration + tcyr ~3.
> Minors flex long.

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
