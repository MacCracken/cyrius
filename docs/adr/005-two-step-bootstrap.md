# ADR-005: Two-Step Bootstrap for Compiler Changes

**Status**: Accepted
**Date**: 2026-04-05 (cc3 era; current binary is cycc after the cc3 → cc5 rename at v5.0.0 and the cc5 → cycc rename at v6.0.0. `cycc` is the final, version-agnostic name — the principle applies regardless of the binary name)
**Context**: Heap layout changes break the bootstrap chain because the committed compiler binary uses old offsets.

## Decision

Any compiler change that modifies heap offsets, token array sizes, or buffer locations requires a two-step (or three-step) bootstrap:

1. Old cycc compiles new source → `stage_a` (has new layout; may differ from build/cycc)
2. `stage_a` compiles same source → `stage_b` (must equal `stage_a`)
3. Verify `stage_a` == `stage_b` (byte-identical self-hosting)
4. Copy `stage_a` to build/cycc

## Rationale

- The old cycc can compile the new source because it only uses ITS OWN offsets during compilation
- The GENERATED binary (`stage_a`) has the new offsets
- `stage_a` compiling itself (`stage_b`) must match `stage_a` — this proves correctness
- If `stage_a` != `stage_b`, there's a real bug (not just bootstrap divergence)

## When Required

- Expanding token arrays (32K → 64K)
- Relocating var_noffs, var_sizes, or any named buffer
- Changing brk limit
- Adding block scoping (changes local variable indexing)

## Consequences

- Every heap change requires explicit verification
- The committed build/cycc must always be the SECOND-generation binary
- Multi-backend changes (aarch64) must sync ALL offset references
- **The cycc self-host fixpoint does NOT cover the full seed chain.** Trust descends
  `seed (bootstrap/asm) → cybs → cycc`, and `cybs` (the hand-assembly bootstrap compiler
  the 29 KB seed assembles) is far more limited than `build/cycc` — it fails **silently**
  on constructs `build/cycc` compiles fine (too many global/call references in one
  function, tail calls). So a `src/` change can pass the cycc self-host fixpoint yet break
  `seed → cybs → cycc`. **`seed-derive-cycc.sh` is a mandatory EVERY-release gate** (not
  closeout-only); see the v6.3.0 seed break (the var-family migration grew all 7 tables
  inline in one function) and `feedback_seed_derive_mandatory_cybs_limits`.

## Tooling

The consolidated pre-tag verifier is `scripts/release-gate.sh` (canonical as of v6.3.0):
step 1/5 = the cycc self-host fixpoint, step 2/5 = `seed-derive-cycc.sh` (the
`seed → cybs → cycc` byte-identity), then check.sh + cross-OS + bench, fail-fast.
`version-bump.sh` also runs the seed-derive gate after its cycc rebuild. The older
`scripts/build-cycc-verify.sh` (v5.11.67) is now a SUBSET — it enforces the cycc
byte-identity invariants but does NOT exercise the seed chain. See the CLAUDE.md
"Release Gate" section.
