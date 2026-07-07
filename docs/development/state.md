# Cyrius — Current State

> Refreshed every release. This file is **state** (volatile) — a SNAPSHOT of where the
> project is right now, bumped via `version-bump.sh`. It deliberately holds **no
> per-release narrative** (canonical in [`CHANGELOG.md`](../../CHANGELOG.md)) and **no
> backlog** (the full pin sequence + length map is in [`roadmap.md`](roadmap.md); parked /
> v7+ items in [`roadmap-future.md`](roadmap-future.md)). CLAUDE.md holds the durable
> preferences / process / procedures.

## Current state

| | |
|---|---|
| **Version** | **6.4.17** — cx portable bytecode target **Release A** (CLI exposure): `cyrius build --target=cx` + `cyrius run *.cyx` + versioned `.cyx` header + float hard-error. First of the ~4-release cx-portable arc (A→B→C). Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,069,552 B (self-host fixpoint; **cycc byte-identical** — the cx surface is all in `cbt/` + the cx fork/backend + cxvm, none in `src/main.cyr`) · check.sh **132** · self_compile ~577 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` (cass green proves the `cyrius` CLI compiles to PE with the cx fork/exec plumbing; release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **cx portable bytecode target — Release A SHIPPED (v6.4.17).** `--target=cx` + `.cyx` run + versioned header + float-guard. **NEXT: Release B — cx scalar float** (host-backed f64 opcodes in cxvm + emitter rewire + `_cx_float_gate`; lifts A's float hard-error). Then **Release C — cxvm cross-OS syscall ABI** + raised caps. Full A→B→C plan in [roadmap.md](roadmap.md) slot 5. |
| **Next up** | **cx Release B — scalar float** (host-backed f64 VM opcodes: reinterpret i64 bits as f64 + host op; rewire `EMIT_FLOAT_LIT`/binop/casts/cmp; `_cx_float_gate`; transcendentals fail loud). Then **Release C** (portable cxvm: guest-syscall ABI per-host + raised 64 KB caps). After the cx arc: **SIMD Pin 1 aarch64 NEON — Phase 5**. |
| **Committed after** | UEFI Secure Boot signing → function visibility (`pub`/`private`) → Intel-Mac (x86_64 Mach-O) tail. **2026-07-07 horizon**: + scalar-float completion + diagnostics later in 6.4.x · **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency expected to pull into 6.4.x post-NEON per user follow-up) · **v6.6.x = language ergonomics** (defer, const fn, block scoping, bounds mode, trait-bounds gated) · **RISC-V → v6.7/v6.8** |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
