# Productize the cyrius-x (cx) bytecode backend — give it a user-facing output/run path

- **Filed**: 2026-07-05 (surfaced by a user premise-check during SIMD Phase 4)
- **Status**: TRACKED — lightweight stub; **dig deeper later**. Scheduled AFTER the
  v6.4.x SIMD arc. Design (exact CLI surface, cxvm install shape, float/SIMD scope)
  is deliberately NOT finalized here.
- **Priority**: not a release-blocker; a "finish the last mile" of an existing,
  working-but-unexposed backend.

## The finding (one line)

The **cx / cyrius-x bytecode backend** — a substantial, self-hosting, end-to-end-tested
body of work that began life as the git commit `caa7122e "wasm what"` and evolved into
cyrius-x — is **built, tested, and functional internally, but has ZERO user-facing
surface.** A consumer has no way to emit `.cyx` bytecode or run it.

## Evidence (verified 2026-07-05)

- **The backend exists and works end-to-end:** `src/backend/cx/emit.cyr` (register-based
  4-byte-instruction bytecode emitter), `src/main_cx.cyr` (the cx compiler fork),
  `programs/cxvm.cyr` (the VM). `programs/checks/cx.cyr` is a ~15-check gate — part of the
  green `check.sh` — that builds `cc_cx`, builds `cxvm`, emits bytecode, pipes it through
  cxvm, and asserts the exit code. "cc5_cx output is now clean CYX bytecode end-to-end" is
  a real shipped commit.
- **But there is no CLI to reach it:** the `cyrius` CLI's target flags are default(x86) /
  `--aarch64` / `--win` / `--agnos` / `--target=js` — **there is no `--target=cx`.**
  `cxvm` is **not installed** (`install.sh` has zero cxvm references — it is only built
  ad-hoc inside the test gate). `cyrius run` runs *native* code; there is no `.cyx` run path.

## Why this matters / the exact parallel

This is the **same shape as the TS→JS gap**: the TS/TSX frontend existed for a while with
no JS emit path, then `--emit-js` / `cyrius build --target=js` wired it into the CLI at
v6.1.11/v6.1.12 and made it usable. The cx bytecode backend never got its equivalent
last-mile CLI exposure, so "all those minors of work sit there unable to be used."

## Sketch of the productization arc (to be designed properly later)

1. **CLI output path (the headline):** `cyrius build --target=cx <src> <out.cyx>` routed to
   the cx emit path (mirror the `--target=js` plumbing in `cbt/build.cyr` / `cbt/core.cyr` /
   `cbt/commands.cyr`).
2. **Ship the VM:** install `cxvm` via `install.sh` (like the other build artifacts) so a
   `.cyx` can actually be run, and add a `cyrius run`/exec path (or `cyrius run --cx`) for
   `.cyx`.
3. **Completeness (secondary):** finish the cx backend's **float ops** (already listed in
   `docs/development/roadmap_6.md:742`) and decide whether **SIMD** lands on cx (today
   `EMIT_F32V_LOOP` / `EMIT_IVEC_*` / `EMIT_F32V8_LOOP` are silent stubs on cx).

## Open questions for the deeper pass (later)

- Is the goal a *portable distributable* (`.cyx` + a shipped `cxvm`), a *debug/interp*
  target, or a stepping-stone to a real WASM target? That decides how much to invest.
- Does `cxvm` need to be a tracked/installed binary, or JIT-built on demand like the
  cross-arch `cross_bins`?

**Do not start until the v6.4.x SIMD arc is complete.** This stub only ensures the work is
not "disappeared" again.
