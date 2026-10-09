# Cyrius Future Work — beyond the current minor

**Scope** — the **6.x-cycle watching list**: known work not pinned to a slot, pulled into a v6.x minor when a need is
filed or the user pulls it forward. **PLACEMENT RULE (hard): everything technical here is 6.x-cycle work — no
codegen / runtime / platform item is ever a "v7 item."** The only genuine 7.x content is the public-release book +
legal / release invariants at the bottom. Shipped items do not stay here — mark nothing "SHIPPED" in place; delete it
(the CHANGELOG is the record).

See [roadmap.md](roadmap.md) for the active minor and its unscheduled backlog, and [roadmap_6.md](roadmap_6.md) for the
work placed after it.

---

## Unpinned language and platform refinements

Re-verify each against LIVE code before pulling it — a row's own text is not evidence (two of eight rows here were
wrong at the 2026-08-07 pass).

| Feature | Effort | Status / notes |
|---|---|---|
| **Hardware 128-bit div-mod** | Medium | No `div`-family emitter exists in any backend. `bayan_u128_divmod` has an x86-only fast path for `b_hi == 0` (two `div`s as raw bytes in an `asm { }` block, `#ifdef CYRIUS_ARCH_X86`); the full 128/128 case and every aarch64 / cx case run the 128-iteration shift-subtract loop. Pull forward on a real perf regression or when aarch64 numeric work makes the asymmetry bite. |
| **Phase 3-full varargs** (`va_arg` for by-value structs + nested) | Medium | Phase 3-min shipped v5.5.36. Niche — most code passes an array of args. |
| **Incremental compilation** | High | Reconsider when cycc self-host crosses ~2 s (**1,175 ms at 6.7.6**; 923 ms at 6.6.19). ⚠ Quote a pair, not a point: the same binary has measured a 52 ms spread across three runs, wider than most release-over-release deltas. Every release's bench run is the report. |
| **`#phf` — a compile-time perfect-hash table** | Medium | The const-eval proposal's option 3 (archived at 6.7.2, when C1 `const fn` answered its decided scope): bake a collision-free lookup from a checked-in key set. Only if a filed need remains that `const fn` + the generated-`.cyr` idiom do not cover. |
| **DWARF debug-info emission** | High | When a real debugger story is needed; crash localization (`CYRIUS_SYMS`) is still x86-ELF-only. 6.x-line codegen work, never 7.x. |
| **`tantu` — the async runtime as its own repo** | Medium | The name is reserved; a future minor, not sequenced. |
| **Auto-vectorization of scalar SOA loops** | High | Hand-written SIMD (`lib/simd.cyr`, the `f64v*` / `f32v*` types) covers today's needs. |
| **Named build profiles + `[build] target` read** | Medium | `[build.PROFILE]` and a selector, and `[build] target` read instead of warned ([issue](issues/2026-10-08-manifest-build-profiles-and-target-unread.md), open by design). Two forks that change what an existing manifest builds — the user's, at the pull. Pull when a need is filed. |
| **Poison guard pages** (proposal P6's step S7) | Medium | Page-backed guarded blocks so `--poison` catches a read that jumps a whole redzone ([issue](issues/2026-10-08-poison-guard-pages-unbuilt.md), open by design): per-target page sizes (16 KiB on Apple arm64), a new PE `VirtualProtect` reroute, and an agnos run that REPORTS "unguarded" (`cyr_mprotect` is a no-op). |
| **X448 / secp521r1 key exchange** | Medium | TLS capability item 6 ([issue](issues/2026-10-08-native-tls-capability-limits.md)): waits on constant-time implementations in sigil's source. |
| **Native 256-bit SIMD on aarch64** | Medium | The aarch64 `EMIT_F32V8_*` emitters DELEGATE to the 4-lane NEON `EMIT_F32V_*` ones (since 6.5.49), and `lib/simd.cyr` routes f32v8 through native f32v4 NEON (its f32v8 wrappers gate on `simd_has_avx2()`, 0 off x86). Correct at a 4-lane stride; a native path (SVE) is unplanned. |

## DX / cyrlint tooling (watching)

Two static checks, one `cyrlint` bite — **placed in 6.7.10's scanners lane** (2026-10-09; [issue](issues/2026-10-08-cyrlint-array-overrun-and-write-length-checks.md)). `programs/cyrlint.cyr` implements
neither (re-checked at the 6.6.20 re-triage). Linter / formatter / LSP evolution is 6.x-line work.

- **Bare-local-array slot-write lint** — warn when a bare `var a[N]` (N *bytes*, rounded to 8) is written past its
  byte size as if it held N *slots*; needs byte-size-vs-max-index analysis. ~21 intentional sites in-tree. May fold
  into v6.7.x C2 (the bounds-checked mode reasons about the same declared-size-vs-index question).
- **Syscall-write byte-length gate** — a permanent check that `syscall(SYS_WRITE, fd, "literal", LEN)`'s LEN matches
  the literal's byte length (532 sites, 0 mismatches at v6.5.33 — preventive; two off-by-ones were written during
  v6.5.30–.32 and found only by reading the output). ⚠ Implementation trap: count raw bytes and collapse only
  two-character backslash escapes — a checker that round-trips through `unicode_escape` reports 23 false mismatches
  (every em dash, double-decoded).

## Speculative type-system work

- **Polymorphism beyond monomorphization** — higher-kinded types, GATs, or whatever the next generic ceiling needs.
  (Trait-bounded generics shipped in 6.7.1.)
- **Effect tracking beyond `@unsafe`** — `@io`, `@alloc`, `@panic` only if a real enforcement need emerges.

---

## ~v7.0 — public release ("Cyrius ONE") — FULL-PUBLIC IS AN OPEN QUESTION

Sovereign + usable is the committed direction; a *full public* release (the book + an installer aimed at strangers) is
**not a decided commitment** (user, 2026-06-11), and v6.x grows much more before any v7.0.0 bump. The
usability / adoption debt is worth paying regardless — tracked in [roadmap_6.md](roadmap_6.md) § *Usability /
adoption readiness*. If a public release is decided, the book ("written from vidya + first-party docs") fixes a
stable point — when the language stops accumulating substantial new surface.

**LEGAL-01 — the GPL-3.0-only stdlib is source-included into every consumer** (including folded sigil, whose own
licensing has a dual-BSD/GPLv2 leg), so consumer binaries inherit GPL-3.0 obligations. Before any full-public release
this needs a deliberate licensing decision — a linking / library exception, or an explicit statement — with legal
sign-off.

## v7.0 commitments (invariants, not items)

- **No binary rename at v7.0.0.** The v6.0.0 `cc5 → cycc` + `cyrc → cybs` rename was the last one.
- **The prior-major slot rotates at v7.0.0** to the last v6.x `cycc` — the same binary name, so the slot effectively
  retires (`build/cc5`, the last v5.x top compiler, holds it today; cc3 was dropped at v6.1.0).

## How items move from here into a cycle

An item earns a slot when a need is filed (`docs/development/issues/`), or the user pulls it forward at slot entry.
Then add it to roadmap.md (or roadmap_6.md) and delete it here. The reverse — de-pinning a roadmap item back to
watching — happens when the slot-entry premise-check shows it is not ready.
