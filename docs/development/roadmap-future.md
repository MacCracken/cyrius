# Cyrius Future Work — Beyond Current Minor

**Scope** — Items that aren't pinned to the current cycle but are
known long-term work: v7.0+ aspirations, unpinned language
refinements waiting on consumer pressure, speculative type-system
extensions, and the public-release manuscript pin. Items here may
get pulled forward into a v6.x minor when consumer pressure
materializes; the placement is "watching" not "deferred".

See [roadmap.md](roadmap.md) for the current active minor and
[roadmap_6.md](roadmap_6.md) for the whole v6.x cycle.

---

## cyrius-x (cx) bytecode backend — ▲ PULLED FORWARD to v6.4.x (2026-07-07)

**Moved to the active minor** at the 2026-07-07 horizon session: the missing CLI
surface was hit as a real wall by a consumer needing wasm-shaped output, so the
user prioritized it as **sooner-than-later interim DX work in v6.4.x** — see
[roadmap.md](roadmap.md) "2026-07-07 horizon additions". Scope unchanged:
`cyrius build --target=cx` (mirror `--target=js`) + install `cxvm`/`.cyx` run
path + finish cx float ops + decide SIMD-on-cx. Full stub:
[`proposals/2026-07-05-cx-bytecode-cli-exposure.md`](proposals/2026-07-05-cx-bytecode-cli-exposure.md).

---

## SIMD Phase 5 — aarch64 NEON (+ cx/PE tail) (DEFERRED, resumes later in v6.4.x)

**Break point taken 2026-07-05** (user): the x86 SIMD compute portion of the v6.4.x arc shipped
complete (Phase 1–4, v6.4.4–.9 — f32v4 128-bit + f32v8 256-bit AVX2, integer vectors + int8 widening
dot), and the arc is **intentionally paused** to land interim items first. Phase 5 is **deferred, NOT
cancelled** — it resumes **later in the v6.4.x minor** (so it stays in the active-minor arc, not v7);
it lives here only as the tracking home while paused. Until it lands, `simd_f32v4` / `simd_ints` /
`simd_f32v8` stay **XFAIL on aarch64** (and the cx/PE stubs stay silent).

**Pre-scoped (premise-check 2026-07-05):** a **mechanical NEON mirror** of the existing `EMIT_F64V_*`
aarch64 code (`.2d` → `.4s`, llvm-mc-sourced encodings), a planned **2-release split**:
- **5a — f32 NEON** (`fadd`/`fmul`/`fmla`/dot). Un-XFAILs **both** `simd_f32v4` and `simd_f32v8` on
  ARM in one go, because the f32v8 wrappers fall through to the f32v_ (128-bit) path on aarch64.
- **5b — integer NEON + `iv_dp8`.** The one design point: `sdot` needs the optional **`FEAT_DotProd`**
  extension, so a runtime feature-gate or an `smull`/`saddlp` fallback is required — the aarch64
  analog of the x86 FMA/AVX2 CPUID gate.

**Phase-6/7 tail:** cx-bytecode SIMD (decide alongside the cx CLI-exposure item above) + PE-target
SIMD gating + the `lib/simd.cyr` wrapper/doc pass. When 5a lands, remove the `simd_f32v4`/`simd_f32v8`
XFAILs from the aarch64-native CI corpus and promote them into the `vr01_` cross-OS LIBTEST glob (CI
surfaces the flip via `XPASS`). Tracked: `issues/2026-07-05-aarch64-f32v4-xfail-phase5.md`.

---

## v6.1.x carry-in (from the v6.0.x → v6.1.0 closeout, 2026-06-07) — ✅ MOSTLY SHIPPED

Surfaced by the v6.0.91 closeout judgment-pass workflow (heap/dead-code/
refactor/code-review/security/downstream — all otherwise clean). **Status
2026-06-10:** the first three shipped — `aarch64 EADDRA_IMM` @ v6.1.2,
`_emit_fmt`/`_entry_base` hoist @ v6.1.4, DCE consolidation @ v6.1.5. The
freed-scalar-holes reclaim (informational) stays a fill-as-you-go item. The
original candidate write-ups are kept below for history:

- **`aarch64` ADD/SUB-immediate 12-bit-mask class — CLOSED.** `EADDRA_IMM` was
  fixed at v6.0.91 (three-way split); the two remaining unguarded siblings
  (`EADDIMM_X1` struct-field offsets, `EPATCHFRAME` prologue frame size) were
  swept and fixed at **v6.2.21**, and the other imm12 sites (`ESTOREB_IMM`,
  `ELOAD_LOCAL_ADDR`) confirmed guarded. All latent (cycc's own offsets/frames
  are small; 256-field struct cap + array globalization keep source < 4096), so
  none bit in-tree — guarded by `tests/tcyr/aarch64_imm12_frame_field.tcyr` +
  disasm differentials. Original write-up (historical):
  [`issues/archived/2026-06-07-aarch64-eaddra-imm-12bit-mask-over-4095.md`](issues/archived/2026-06-07-aarch64-eaddra-imm-12bit-mask-over-4095.md).
- **Hoist `_emit_fmt` / `_entry_base` to a shared home** — the v6.0.89
  first-bite left these byte-identical-duplicated in `x86/fixup.cyr` +
  `aarch64/fixup.cyr` deliberately. The hoist is BLOCKED by the single-pass
  parser + include order: `runtime.cyr` is parsed before `emit.cyr`, but
  `_emit_fmt` reads `_TARGET_MACHO/_PE/_ELF64_KERNEL` as bare-identifier
  globals declared only in `emit.cyr` → a hoist there is a hard "undefined
  variable" exit, not a deferrable fixup. Prereq: move the `_TARGET_*`
  declarations into `runtime.cyr`/`tokens.cyr` first (verified feasible — no
  early reader; all assignments happen after every include). Structural
  multi-backend change; needs ecb/cass self-host reverify.
- **Consolidate the DCE mark-and-sweep across `x86/fixup.cyr` +
  `aarch64/fixup.cyr`** — the hash build/seed/propagate/sweep/undef-fn pass
  is duplicated across the two backends, and within each the open-addressing
  hash-probe + the linear host-fn scan are each written twice. A shared
  `_dce_hash_lookup` + `_dce_host_fn` collapse 4 probe-blocks → 1 and 4
  host-scans → 1 (arch delta is only `E8/E9`+`DECODE_LEN` vs `BL/B` 4-byte
  stride). Changes emitted helper code → cross-OS self-host reverify.
- **Reclaim the FREED scalar holes** (informational) — the compiler-state
  scalar band has the ~2 KB v6.0.88 `ret_patches` hole + the v6.0.47 holes
  (`0x18E630`/`0x18EE30`/`0x18F900`/`0x18F908`); allocate the next new
  compiler-state scalar into the `.88` hole rather than growing the band.

---

## TS/TSX → JS emit — frontend builder (consumer-filed, minor TBD)

SecureYeoman's `yeo-cy-test` port probe (2026-05-27) confirmed the
Cyrius TS/TSX front-end **parses** real-world TS/TSX cleanly
(interfaces, `<K extends string, V>` generics + default type params,
`?.`/`??`, async/await, enums, `readonly`/optional members,
destructuring, spread, tuples, `Record<K,V>`, a full React component
with `useState`/`useEffect`/JSX) — but has **no emit**. `--lex-ts` /
`--parse-ts` validate only; the P3–P5 lowering from the old v5.7.2 TS
plan never shipped. So Cyrius can be the build-time *validator* of a TS
frontend but not its *builder*; the consumer hand-maintains a parallel
`web/app.js` as the production stopgap.

**Ask**: a `cycc --emit-js <file.tsx>` (or `cyrius build --target=js`)
codegen stage walking the existing AST — strip type annotations /
interfaces / type aliases, lower JSX → `createElement`-style calls
(configurable pragma), pass ESM through. Single-file emit only; a
bundler is explicitly out of scope. The expensive part (a correct,
full-fidelity TS/TSX parser) already exists — this is codegen on top.

**Status**: consumer-filed with active pressure, but **minor TBD** per
user direction 2026-05-27 ("arc TBD"). Larger than the three TS
scripting papercuts the same filing surfaced (those are near-term
v6.0.x bug-bandwidth — see [roadmap.md](roadmap.md)). Notable framing:
this is a *non-machine-code output target* for an assembly-up compiler,
so its home minor is a deliberate open decision rather than an obvious
v6.3.x language-refinements fit. ✅ **SHIPPED v6.1.10/.11** (Phase D — emitter on
the corrected AST; surfaced via `cyrius build --target=js` v6.1.12; `async`-on-
nested-arrow fix v6.1.15). Issue (resolved, archived):
[`issues/archived/2026-05-27-yeo-cy-test-no-tsx-js-emit.md`](issues/archived/2026-05-27-yeo-cy-test-no-tsx-js-emit.md);
full write-up in `secureyeoman/yeo-cy-test/FINDINGS.md`.

---

## Unpinned language refinements

These were tracked through v5.x as known asks but explicitly held
unpinned at v5.8.65 close (2026-05-05) — consumer pressure either
didn't materialize or workarounds proved sufficient. Re-evaluate
at each cycle-open per [`feedback_premise_check_at_slot_entry`].

| Feature | Effort | Status / Notes |
|---|---|---|
| **Hardware 128-bit div-mod** | Medium | Stays unpinned. abaco / sigil work around via u128 shifts; not blocking. Pull forward if a real perf regression surfaces. |
| **Phase 3-full varargs** (`va_arg` for structs-by-value + nested) | Medium | Phase 3-min shipped v5.5.36. Stays unpinned — niche. Most consumers use array-of-args pattern instead. |
| **cycc per-block scoping** | Medium | ▲ **PINNED v6.6.x** (2026-07-07 horizon session — item 3 of the Language-Ergonomics minor, with shadowing; see [roadmap_6.md](roadmap_6.md)). |
| **Incremental compilation** | High | Stays **watching**. Whole-program self-host is fast (~500 ms @ v6.1.x). Reconsider when cycc self-host crosses ~2 sec (~575 ms @ v6.4.14) — and per user 2026-06-11, **the next few arcs will inform the timing**: the v6.5.x perf-quality minor + RISC-V (now v6.7/v6.8) will show whether self-host is approaching the threshold (the bench harness is un-blind since v6.2.15/v6.3.17, phase-resolved). Don't pin now; let those arcs report. Same posture for the **bus-factor / institutional-memory** question (vidya + memory-pins live outside the repo) — revisit as those arcs land. |
| **Stackless coroutines** (suspend/resume across `await`) | Medium (poll-runtime rework) | **Unpinned follow-on.** v6.3.11 shipped async/await as first-class deferred-then-forced Futures over the run-to-completion epoll runtime, explicitly NOT stackless CPS. True suspend/resume needs a poll-runtime rework (+ force-once memoization). No live consumer; pull forward on a real suspend-across-await need. (Named in the v6.3.11 slot cell as "pinned as a follow-on" — recorded here 2026-07-01 so it points somewhere.) |
| **f32 scalar arithmetic** (native-float Tier A tail) | Low | ▲ **PINNED later-v6.4.x** (2026-07-07 horizon session — the scalar-float completion slot, together with scalar-`f64` return type + stricter f64/f32 typecheck; see [roadmap.md](roadmap.md)). |

---

## Stdlib libs (consumer-filed proposals)

Discrete stdlib additions filed by ecosystem consumers; each is its own slot when
pulled (no urgency — every consumer has a working fallback today).

| Lib | Filed by | Effort | Status / Notes |
|---|---|---|---|
| ~~`lib/protobuf.cyr`~~ (proto3 wire encode/decode) | hoosh (OTLP/OpenTelemetry span export) | — | ✅ **Shipped v6.2.17**, finished v6.3.42 (double/float wire helpers + guide section, protobuf.tcyr 49 cases). Minimal proto3 wire codec — length-delimited messages, no `.proto` compiler; pure Cyrius, no syscalls. Proposal archived. |
| ~~`sys_fsync`/`sys_fdatasync`~~ | hapi (atomic manifest edits) | — | ✅ **Shipped v6.2.14** — bare wrappers in `syscalls_x86_64_linux.cyr` (74/75) + `syscalls_aarch64_linux.cyr` (emit x86 74/75, ESYSXLAT → 82/83). Proposal archived. |

---

## Speculative type-system work

Long-horizon items that go beyond the v6.3.x Language Refinements
arc (closures + monomorphization + async sugar). Not pinned to any
minor; floats in the watching list until a specific consumer ask
or design driver materializes.

- **Polymorphic items beyond monomorphization** — trait-bounded
  generics, higher-kinded types, GATs (generic associated types),
  or whatever shape post-monomorphization generic work needs once
  consumers start hitting the next ceiling. **Trait-bounded generics
  got a DEMAND-GATED home at the v6.6.x ergonomics tail (2026-07-07)**
  — pulls in only if consumer pressure materializes by that arc-open
  (the open B3 struct-type-args monomorph bug lands first). HKTs/GATs
  stay here.
- **Effect tracking beyond `@unsafe`** — v5.8.x shipped `@unsafe`
  as the first effect annotation. Lift-to-more-effects (e.g.
  `@io`, `@alloc`, `@panic`) only if a real consumer enforcement
  scenario emerges.

---

## ~v7.0 — Public release ("Cyrius ONE") — FULL-PUBLIC IS AN OPEN QUESTION

**Reframed 2026-06-11** (user): "sovereign and usage — whether its full public
is still in question." Sovereign + usable is the committed direction; a *full
public* release (the book on Amazon/Packt + an installer aimed at strangers) is
**not a decided commitment**. Keep the manuscript + public launch as a *possible*
v7 shape, a watching item — not a gate.

Two things follow:
- **v6.x grows much more before any v7.0.0 bump** (user 2026-06-11) — see
  roadmap_6.md "What comes after v6.x". v7 is further out than earlier framing
  implied; the language can keep accumulating surface across additional v6.x
  minors.
- **The usability/adoption debt is worth paying regardless** of whether it ever
  goes fully public — diagnostics, debug-info, stdlib-reference coverage, the
  GPL linking-exception question all make the toolchain better for the *existing*
  ecosystem too. Tracked in roadmap_6.md "Usability / adoption readiness" + the
  2026-06-10 deep-dive audit.

**If/when a public release is decided**, the book ("written from Vidya +
first-party docs") fixes a "stable point" — when the language stops accumulating
substantial new surface. That point is now expected later in (or after) the v6.x
cycle, not at a near-term v7.

---

## v7.0 commitments (NOT items — invariants)

Two known commitments per CLAUDE.md "Version lives in `VERSION` +
`--version`, never in binary names":

- **No binary rename at v7.0.0**. The v6.0.0 `cc5 → cycc` +
  `cyrc → cybs` rename was the LAST name-change penalty paid.
- **Prior-major slot rotates at v7.0.0**. **cc3 was already dropped at
  v6.1.0** (corrected 2026-06-10 — earlier text here said "build/cc3 drops
  at v7.0.0", which contradicted CLAUDE.md's "dropped at v6.1.0"; finding
  RM-05). The prior-major slot now holds **cc5** (the last v5.x top
  compiler); at v7.0.0 it rotates to the last v6.x `cycc` — same binary
  name, so the slot effectively retires (no rename bridge).

---

## How items move from here into a cycle

An item earns a v6.x slot when:
1. A consumer files a specific need (per
   `docs/development/issues/`) that the item closes.
2. Cycle bandwidth opens during a minor's absorber band.
3. User direction explicitly pulls it forward at slot entry.

When pulled forward: edit `roadmap.md` to add the item to the
target minor; remove from `roadmap-future.md`. The reverse path
(de-pinning a roadmap item back to "watching") is rare but
happens when premise-check at slot entry shows the work isn't
ready or consumer need evaporated.

---

## Retired references

- **roadmap-old.md** (1,249 lines, deleted v6.0.x) — contained the
  v5.x long-term considerations + v5.12.x retired-spec archive +
  v5.x platform-shipping table + pre-pinned v6.x narrative.
  Resolved pins moved to `roadmap.md`; unpinned items moved here;
  durable principles consolidated into `cycle-discipline.md`;
  ecosystem/platform snapshots moved to their canonical docs
  (`docs/ecosystem.md`, `docs/platform-status.md`); pre-v5.11.x
  retrospective material lives in `completed-phases.md`.
- **roadmap-last.md** (272 lines, deleted v6.0.x) — frozen v5.11.x
  in-flight roadmap. Fully duplicated CHANGELOG + new `roadmap.md`
  + memory pins by v6.0.0 cycle-open.
