# ADR-005: Two-Step Bootstrap for Compiler Changes

**Status**: Accepted
**Date**: 2026-04-05 (cc3 era; current binary is cc5 after the v5.0.0 cc3 → cc5 rename, will be cyc after the v6.0.0 cc5 → cyc rename — the principle applies regardless of the current binary name)
**Context**: Heap layout changes break the bootstrap chain because the committed compiler binary uses old offsets.

## Decision

Any compiler change that modifies heap offsets, token array sizes, or buffer locations requires a two-step (or three-step) bootstrap:

1. Old cc5 compiles new source → `stage_a` (has new layout; may differ from build/cc5)
2. `stage_a` compiles same source → `stage_b` (must equal `stage_a`)
3. Verify `stage_a` == `stage_b` (byte-identical self-hosting)
4. Copy `stage_a` to build/cc5

## Rationale

- The old cc5 can compile the new source because it only uses ITS OWN offsets during compilation
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
- The committed build/cc5 must always be the SECOND-generation binary
- Multi-backend changes (aarch64) must sync ALL offset references

## Tooling

The canonical verifier was formalized at v5.11.67 as `scripts/build-cc5-verify.sh` (renames to `scripts/build-cyc.sh` at v6.0.0). It enforces the three byte-identity invariants above plus a third check (stage_a == build/cc5) that surfaces stale build artifacts.
