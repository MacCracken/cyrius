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
| **Version** | **6.4.18** — cx portable target **Release B**: cx scalar f64 arithmetic (host-backed VM float opcodes) + a foundational **global-var-collision fix** (all top-level vars collided at addr 0 — pre-existing fixup-table reader/writer mismatch). f64 compares deferred (fail loud). Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,069,552 B (self-host fixpoint; **cycc byte-identical** — all cx work is in the cx fork/backend + cxvm, none in `src/main.cyr`; the SESTYPE experiment was reverted) · check.sh **132** · self_compile ~577 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **cx portable bytecode target — A (v6.4.17 CLI) + B (v6.4.18 f64 arithmetic + global-var fix) SHIPPED.** **NEXT: cx f64-compare follow-up** (`issues/2026-07-07-cx-f64-compare-result-typing.md` — f64 compare RESULTS are F64-typed → misbehave in `if()`/`==` on cx; the cxvm compare opcodes are shipped+correct, only the wiring/type-tracking waits), then **Release C — cxvm cross-OS syscall ABI** + raised 64 KB caps. Full A→B→C in [roadmap.md](roadmap.md) slot 5. |
| **Next up** | **cx f64-compare follow-up** (trace the cx `if(F64_expr)` truthiness path vs x86; re-wire `EF64_CMP` to the shipped 0x5A-0x5F opcodes without the 10-program SESTYPE churn). Then **Release C** (portable cxvm: guest-syscall ABI per-host + raised caps). After the cx arc: **SIMD Pin 1 aarch64 NEON — Phase 5**. |
| **Committed after** | UEFI Secure Boot signing → function visibility (`pub`/`private`) → Intel-Mac (x86_64 Mach-O) tail. **2026-07-07 horizon**: + scalar-float completion + diagnostics later in 6.4.x · **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency expected to pull into 6.4.x post-NEON per user follow-up) · **v6.6.x = language ergonomics** (defer, const fn, block scoping, bounds mode, trait-bounds gated) · **RISC-V → v6.7/v6.8** |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
