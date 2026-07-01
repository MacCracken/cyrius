# Cyrius — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable);
> this file is **state** (volatile). Bumped via `version-bump.sh` post-hook.
>
> **Consolidated 2026-06-08 (v6.1.4):** the per-patch session-close log
> (104 entries, ~5,600 lines back to v5.x) + the stale v6.0.4-frozen
> structured sections were pruned — that detail is canonical in
> [`CHANGELOG.md`](../../CHANGELOG.md) (per-patch) and
> [`completed-phases.md`](completed-phases.md) (arc retrospective). This file
> now holds only the **active cycle** + current state.

## Current state

> **v6.3.x EXPANSION in effect (user 2026-06-30).** v6.3.x does NOT close at .16 — the
> whole v6.4.x ABI/Perf arc + the 2026-06-10 governance cluster (minus LEGAL-01, deferred
> to public release) are pulled into v6.3.x; Intel-Mac arc at the tail; v6.4.x reopened as
> an empty staging minor. Sequence: perf-prereqs (bench un-blind .17 / differential gate
> .18) → governance body (.19–.21) → v6.4.x perf arc (.22–.26) → Intel-Mac (.27–.28) →
> closeout. See [roadmap.md](roadmap.md).

| | |
|---|---|
| **Version** | **6.3.17** (v6.3.x cycle — **EXPANSION opens: bench harness un-blind (PF-02 + PF-03)** — the perf-arc prerequisite so the pulled-in v6.4.x regalloc/copy-prop/DSE work can measure its own wins. **PF-02**: `alloc()` single-threaded fast-path — `_alloc_lock_acquire`/`_release` no-op while `_threads_active == 0`, skipping the v6.0.64 CAS spinlock + 2 fences for the dominant single-thread case (incl. cycc, which includes `lib/alloc.cyr`); `thread_create`/`_thread_spawn` (Linux/agnos/Windows) arm `_threads_active=1` BEFORE the child runs (monotonic 0→1, happens-before clone/CreateThread barrier → both parent+child then lock). Single-thread allocs monotonic (100k), concurrency fixture clean, cycc self-hosts+seed-derives byte-id (alloc returns identical pointers single-threaded → ONE-step fixpoint, no two-step). self_compile flat 545 ms (cycc not alloc-bound; win is per-alloc for alloc-heavy consumers). **PF-03**: `bench-history.sh` tier-3 `CYRIUS_PROF=1` self-compile → appends `compiler/phase_pp/lex/gvar/parse/fixup/emit/write` ns rows to `bench-history.csv` (v6.5.x perf-refactor trend). PF-01 already done (v6.2.15). check.sh 109/109; ecb+cass+pi SELFHOST_OK; native regen+pi byte-id; snapshot refreshed for `lib/{alloc,thread,thread_agnos,thread_win}.cyr`. `runtime-bench-suite-blind` closed→archived. See CHANGELOG [6.3.17].) PRIOR: **6.3.16** (v6.3.x — **var-decl / struct-local codegen fixes (P2)**, `parse_decl.cyr`. (a) inferred `var p = mk()` from a struct-ret call → infer struct type + reuse explicit asv/pair codegen; (c) single-≤8B-field struct field access segfaulted x86+aarch64 (1-slot has no `-1` filler → misread as pointer-to-struct → `mov[slot]` not `lea&slot`) → force inline when `STRUCTSZ<=8`, gated `_TARGET_CX==0` (cx boxes structs → already correct); (b) str-literal global init already fixed → regression-locked. `struct_local_codegen.tcyr`; x86+aarch64(real pi)+cx=42; ecb+cass+pi SELFHOST_OK; check.sh 109/109; bench 546 ms; 3 issues closed→archived. See CHANGELOG [6.3.16].) PRIOR: **6.3.15** (v6.3.x — **array locals PER-THREAD by DEFAULT** — v6.3.13 str_builder concurrency fix (array LOCALS were a shared global `.bss` buffer) flipped OPT-IN → DEFAULT-ON (`CYRIUS_STACK_ARRAYS=0` opts out). m128 16-align parity-pad + `secret var` zeroise via `ELOAD_LOCAL_ADDR` + AUTO-FALLBACK (array over 16384-slot budget stays global+`note:`). "Ecosystem footgun" = FALSE ALARM (buggy awk mis-flagged element-typed arrays); precise+11-file agent audit = 295 bare-array locals, 0 over-runs, ZERO stdlib changes; only 6 `.tcyr` daimon-idiom suites fixed. Two-step bootstrap; cycc SHRANK 1,111,616→1,027,664 B. check.sh 109/109; bench 544 ms. See CHANGELOG [6.3.15].) **Earlier releases (6.3.15 back to v5.x): see CHANGELOG.md** — trimmed here (state.md keeps current + ~2 priors; the rest is canonical in CHANGELOG). |
