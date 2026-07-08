# Capturing closures unsupported on Windows PE

**Filed:** 2026-07-07 (CHANGELOG-prose deferral sweep — fail-loud guard live, never filed).
**Severity:** P3 — fails loud (no miscompile); no current PE consumer blocked.
**Component:** `src/frontend/parse_expr.cyr:692` (guard), `src/backend/x86/emit.cyr` (`ECALLPTR_PE`).

## Problem

A **capturing** closure hard-errors on the PE target: `src/frontend/parse_expr.cyr:692`
emits *"capturing closures not yet supported on Windows PE"* rather than risk a miscompile.
Non-capturing closures already work on PE. Per CHANGELOG [6.3.8]: *"the env build +
ECALLPTR_PE 16-byte-align interaction is unverified, so it fails loud."* That deferral
lived only in prose (only a passing mention in the async-tokio-parity issue's "Documented
limits", no dedicated filing).

## Fix

Verify/implement the heap-env build + `ECALLPTR_PE` 16-byte-rsp-align path for capturing
closures on PE (the alignment class the `pe_callptr_alignment` work already navigates for
contended kernel32 reroutes). Remove the fail-loud guard at `parse_expr.cyr:692` once
proven.

## Acceptance

A capturing-closure PE program compiles and runs to the expected exit code under **wine**
AND on **cass** (real hardware); the guard is removed; a PE capturing-closure test joins
the cross-OS gate. Do NOT remove the guard without the cass run (found-by-ports).
