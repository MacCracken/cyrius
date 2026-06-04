# Completed Phases

Historical record of all completed development phases.
For current work, see [roadmap.md](roadmap.md).
For detailed changes, see [CHANGELOG.md](../../CHANGELOG.md) (source of truth).

---

## Phase 0 — Fork & Understand
Forked rust-lang/rust, built rustc from source, mapped cargo registry codepaths.

## Phase 1 — Registry Sovereignty
Ark as default registry, git/path deps first-class, publish validation relaxed. ADR-001 documented.

## Phase 2 — Assembly Foundation
Seven-stage chain: seed → stage1a → 1b → 1c → 1d → 1e (63 tests) → cyrc (16384 tokens, 256 fns).

## Phase 3 — Self-Hosting Bootstrap
asm.cyr (1110 lines, 43 mnemonics), bootstrap closure, 29KB committed binary. Zero external dependencies. Byte-exact reproducibility.

## Phase 4 — Language Extensions
cc2 modular compiler (7 modules, 182 functions). Structs, pointers, >6 params, load/store 16/32/64, include, inline asm, elif, break/continue, for loops, &&/||, typed pointers, nested structs, global initializers.

## Phase 5 — Prove the Language
46 programs, 157 tests. 10-233x smaller than GNU. wc 2.4x faster.

## Phase 6 — Kernel Prerequisites
All 9 items: typed pointers, nested structs, global inits, for loops, inline asm (18 mnemonics), bare metal ELF, ISR pattern, bitfields, linker control.

## Phase 7 — Kernel (x86_64)
58KB kernel (hardened to 62KB in Phase 10): multiboot1 boot, 32-to-64 shim, serial, GDT, IDT, PIC, PIT timer, keyboard, page tables (16MB), PMM (bitmap), VMM, process table, syscalls.

## Phase 8 — Language Foundations (Tier 1)
7/8 complete: type enforcement (warnings), enums, switch/match, heap allocator, function pointers (&fn_name), argc/argv, String type. Block scoping deferred.
Standard library: 8 libs (string, alloc, str, vec, io, fmt, args, fnptr) — 53 functions.
Comparison-in-args fix: `PARSE_CMP_EXPR` + `setCC` codegen.
`assert.cyr` test framework library.

## Phase 9 — Multi-Architecture (aarch64) — Partial
Done: codegen factored into backends, aarch64 emit (61 fns), cross-compiler builds.
Remaining: instruction correctness, self-hosting on ARM, kernel port, cross-compilation.

## Phase 10 — Audit, Refactor, Stabilize — Partial
Done: kernel audit (23 issues fixed), compiler hardening (fixup + token guards), 17 new edge case tests.
Deferred: error message line numbers, performance pass, block scoping.

## Phase 11 ��� Prove at Scale (Crate Rewrites)
5 AGNOS crate rewrites in Cyrius:
- **agnostik** — 6 modules (error, types, security, agent, audit, config), 54 tests
- **agnosys** — syscall bindings (50 numbers, 20+ wrappers, sigset, epoll, timerfd)
- **kybernet** — 7 modules (console, signals, reaper, privdrop, mount, cgroup, eventloop), 38 tests
- **nous** — dependency resolver (marketplace + system), 26 tests
- **ark** — package manager CLI (44KB, 8 commands)
- **cyrb** — build tool (29KB, compile/test/self-host)
- Benchmarks and documentation updated
---

## v0.9.x → v5.x — per-version detail

Per-version slot history (every `## [x.y.z]` block) lives in
[`CHANGELOG.md`](../../CHANGELOG.md) — the **source of truth**
for what shipped when.

Durable cycle retrospectives + field-note narratives live in
[`vidya`](https://github.com/MacCracken/vidya) under
`content/cyrius/field_notes/compiler/retros/`:

| Vidya retro | Covers |
|-------------|--------|
| `pre_v3.cyml` | Phase 8 → v2.x (early language + multi-arch foundation) |
| `v3.cyml` | v3.0 → v3.4.x (compiler maturity arc) |
| `v4.cyml` | v4.x (language vocabulary + closeout) |
| `v5_chronicle.cyml` | v5.x release-arc chronology (per-cycle feature lists) |
| `v58x_back_half.cyml` + `v58x_agent_perspective.cyml` | v5.8.x retrospective (longest minor by patch count at the time, 65 patches) |
| `v59x.cyml` | v5.9.x cleanup-and-lib-improvement cycle (43 patches) |
| `v510x.cyml` | v5.10.x typed-simd / REAL TYPE SYSTEM / struct-by-value arcs (50 patches) |
| `v511x.cyml` | v5.11.x close arc (in-progress at file-trim time) |
| `foldin_arc_v57_v59.cyml` | sandhi-pattern fold-in arc spanning v5.7.0–v5.9.0 |

Volatile current-cycle state (current version, cycc size, in-flight
slots, recent shipped patches) lives in
[`state.md`](state.md) — refreshed every release via
`scripts/version-bump.sh`'s post-hook.

This file (`completed-phases.md`) is on a documented phase-out
track — its prior per-version v0.x → v5.9.x narrative
duplicated CHANGELOG entries + vidya retros without unique
value. v5.11.41 trimmed those redundant sections (572 lines
removed); the Phase 0–11 retrospective above stays because
it's the only single-glance summary of cyrius's pre-cycle
foundation arcs and isn't structured the same way in vidya
or CHANGELOG.

When Phase 0-11 itself gets fully captured in vidya (likely
during the v6.x doc reorg), this file can retire entirely.
