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
> an empty staging minor. Sequence: perf-prereqs (bench un-blind .17, differential gate
> .19) → governance body (.20–.22) → v6.4.x perf arc (.23–.27) → Intel-Mac (.28–.29) →
> closeout. **.18 was a consumer-filed stdlib hardening pull-in** (AGNOS migration). See
> [roadmap.md](roadmap.md).

| | |
|---|---|
| **Version** | **6.3.18** (v6.3.x cycle — **stdlib undersized-array-locals hardening sweep** (consumer-filed, AGNOS base-stack migration to 6.3.15). Completes the v6.3.13 sweep: since array locals became stack-allocated, a bare `var X[N]` written past `ceil(N/8)*8` bytes smashes the frame. A precise **17-file agent audit** (max-write-width vs the 8-byte-rounded slot) caught **2 GENUINE stack-smashes both in `lib/sankoch.cyr` bzip2** (NOT the 7 files the issue listed): `_bz_decode_block` `var pos[6]`→`[48]` (48-byte `store64(&pos+i*8)` loop, i<n_groups≤6) + `_bze_emit_block` `var present[16]`→`[128]` (128-byte loop, i<16) — the daimon footgun (author meant i64 SLOTS, declared BYTES). **Both were missed by the v6.3.13 sweep AND the v6.3.15 "0 over-runs" audit** (loop bound not resolved). New `sankoch_bzip2_roundtrip.tcyr` (compress↔decompress byte-id under default-on stack locals; pre-fix smashes the frame). The 34 sites the issue named (`process`/`regression`/`pam`/`shadow`/`net`/`tls`/`yukti`/`ws`/`syscalls_*`) were confirmed **latent-benign** — each writes ≤8 B, fitting its 8-byte 1-slot alloc (exactly why v6.3.15 said 0 over-runs) — but sized correctly anyway (`stbuf[1]`→`[4]` etc.; byte-identical since slot count unchanged). cycc **byte-identical** (consumer-lib-only). check.sh 109/109; seed→cybs→cycc; ecb+cass+pi SELFHOST_OK; bench 540 ms; cycc 1,027,664 B; native regen byte-id. Snapshot refreshed for 11 edited libs. Issue closed→archived; AGNOS re-vendors on next `cyrius lib sync`. See CHANGELOG [6.3.18].) PRIOR: **6.3.17** (v6.3.x — **bench harness un-blind (PF-02+PF-03)**, opens the EXPANSION. PF-02: `alloc()` single-threaded fast-path (`_alloc_lock_acquire`/`_release` no-op while `_threads_active==0`; `thread_create`/`_thread_spawn` arm it before the child → skip the v6.0.64 CAS spinlock+2 fences for the dominant single-thread case incl. cycc; one-step self-host fixpoint). PF-03: `bench-history.sh` tier-3 `CYRIUS_PROF=1` → `compiler/phase_*` ns rows. PF-01 done v6.2.15. self_compile flat 545 ms (cycc not alloc-bound). check.sh 109/109. See CHANGELOG [6.3.17].) PRIOR: **6.3.16** (v6.3.x — **var-decl / struct-local codegen fixes (P2)**, `parse_decl.cyr`: (a) inferred `var p=mk()` from struct-ret call → infer struct type + reuse asv/pair codegen; (c) single-≤8B-field struct field access segfaulted x86+aarch64 (1-slot has no `-1` filler → misread as pointer-to-struct) → force inline when `STRUCTSZ<=8` gated `_TARGET_CX==0` (cx boxes structs); (b) str-literal global init already fixed → regression-locked. `struct_local_codegen.tcyr`; x86+aarch64(real pi)+cx=42; check.sh 109/109; bench 546 ms; 3 issues closed→archived. See CHANGELOG [6.3.16].) **Earlier releases (6.3.16 back to v5.x): see CHANGELOG.md** — trimmed here (state.md keeps current + ~2 priors; the rest is canonical in CHANGELOG). |
