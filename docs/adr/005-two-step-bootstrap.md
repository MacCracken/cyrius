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

## Tooling

The canonical verifier was formalized at v5.11.67 as `scripts/build-cycc-verify.sh`. It enforces the three byte-identity invariants above plus a third check (stage_a == build/cycc) that surfaces stale build artifacts.
