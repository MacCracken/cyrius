# DX diagnostics: multi-error reporting (Release 2 of the DX arc)

**Filed:** 2026-07-12 (at v6.4.60, when DX Release 1 — column + source-excerpt — shipped).
**Severity:** P2 — DX quality; not a correctness bug.
**Component:** `src/frontend/parse*.cyr`, `src/common/util.cyr` (the emitters), `src/main.cyr`
(the pass-2 driver + the dead `_had_error` exit hook).

## Context

v6.4.60 shipped DX Release 1: every error now prints `error:<source>:LINE:COL:` + a source-excerpt
with a caret. Release 2 is **multi-error reporting** — report several errors per compile instead of
fail-fast on the first. Today every emitter (`ERR`/`ERR_EXPECT`/`ERR_MSG`/`ERRDUPVAR`) ends in
`syscall(SYS_EXIT, 1)`; the parser stops at the first error.

## Scope — BOUNDED statement/decl-boundary panic-mode (the viable version)

The clean-path saving grace: recovery branches are **never taken on valid input**, and cycc's own
source never errors, so the self-compile output is unchanged → the byte-identical fixpoint +
seed-derive hold *provided every edit is a never-taken branch that doesn't reorder the clean path*.
Mechanism (must land COMPLETE in one release — no slicing):

1. `ERR*`/`ERR_MSG`/`ERRDUPVAR` **print-and-return** (mirror `WARN`, the existing template) instead
   of `SYS_EXIT`; set the (already-present but dead) `_had_error = 1` (main.cyr:560 →
   `syscall(SYS_EXIT, _had_error)` @ main.cyr:2119); set a new `_panic = 1` and go **silent** while
   `_panic` (one error per statement).
2. A small standalone `_sync_skip(S)` advances to the next `;`(5) / `}`(14) / `fn`(32) / decl-keyword
   / EOF(12) with a **hard EOF guard**, called from `PARSE_STMT` (parse.cyr) and the pass-2 driver
   loop (main.cyr ~1452) when `_panic`, then clears `_panic`.
3. Gate the single output write (main.cyr ~2083) on `_had_error == 0`.

## Risk (be honest — riskier than a normal slot)

Between the error and the sync point the desynced cursor keeps parsing/emitting through expression
interior. `PEEKT`/`TOKTYP` are unchecked `L64` reads; an unbounded skip past EOF or a
`while(PEEKT!=X)` loop lacking an EOF guard → SIGSEGV; continued garbage emission grows the fixup
table (cap 32768) / fn table (8192). **8 `while(PEEKT!=...)` skip loops** need an EOF-guard hardening
audit: parse.cyr:379/446/686/730, parse_types.cyr:316, parse_decl.cyr:585, parse_expr.cyr:174,
parse_fn.cyr:2254. Ship with a negative-input corpus (missing `;`, unclosed `(`, garbage token,
garbage-past-EOF) → `tests/dx_multi_error.sh` asserting `grep -c '^error:' == N` + exit 1, run cross-OS
(desync-driven table growth is target-agnostic; check.sh's grep summary masks segfaults — use a
per-file exit-code loop).

## Deferred FURTHER (backlog, not this arc): full arbitrary recovery

Full expression-interior recovery needs error-return threading through the 346+ `ERR_EXPECT`
fall-through sites + every parse-chain caller (parse fns return i64 but callers ignore it) OR
exceptions (door closed — `project_no_try_catch_door_closed`). That is cybs-hostile (adds call/return
refs to already-large parse fns that cybs mis-compiles silently) and is NOT a 1-2 release arc. Pin to
`roadmap-future`; possibly revisit atop the v6.5.x IR substrate. Codegen/runtime → 6.x line or the
roadmap "potential backlog", NEVER parked to 7.x.

## Acceptance

`cyrius build` of a file with N independent statement-level errors prints N `error:…:L:C:` diagnostics
(each with its excerpt) and exits 1; valid input is byte-identical (self-host fixpoint + seed-derive);
malformed/garbage/past-EOF input never crashes (negative corpus green on ecb/ach/cass/pi).
