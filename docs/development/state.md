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
> .20) → governance body (.21–.23) → v6.4.x perf arc (.24–.28) → deps/language/lib
> pull-ins (**Phase D** .29 = the modularity-arc lever-1 completion / generics tail .30 /
> protobuf .31) → Intel-Mac (.32–.33) → closeout. **.18 and .19 were consumer-filed stdlib pull-ins** (the AGNOS base-stack
> migration to 6.3.15): .18 the undersized-array hardening sweep, .19 the ws_server header
> rename + agnos `sys_fstat` peer (the differential gate + all downstream slots shifted +1).
> See [roadmap.md](roadmap.md).

| | |
|---|---|
| **Version** | **6.3.20** (v6.3.x cycle — **the differential-corpus gate (VR-03)**, the perf-arc prerequisite. Codifies the "logic-preserving" verification (a ~338-input old-vs-new byte-identical corpus + DCE torture, muscle memory since v6.1.5/.6/.8) into `scripts/differential.sh`: OLD cycc (`git show ref:build/cycc`, the tracked binary) + NEW cycc compile a deterministic **304-input corpus** (src compilers + tcyr + programs + benches + fuzz) in default + `CYRIUS_DCE=1` modes; `cmp` all → identical / codegen-diff / status-diff / both-fail. Manual-trigger (`--quick`/`--smoke`). **Validated both ways**: clean self-run all-identical (303/304, `programs/io.cyr` a non-standalone both-fail); vs pre-.15 cycc correctly flags the array-locals codegen diffs **RED** — a real detector, not a placebo. Functional `_differential smoke gate` rot-guard (check.sh 109→**110**) so the manual gate can't rot (the macOS-CI lesson). The ONLY guard between the perf arc (.25–.27 regalloc/copy-prop/DSE) and a silent miscompile → **MUST precede it**. cycc **byte-identical** (scripts + check-program only). check.sh 110/110; seed→cybs→cycc; ecb+cass+pi SELFHOST_OK; self_compile 545 ms; cycc 1,027,664 B. See CHANGELOG [6.3.20]. **Also 2026-07-01 (doc-only): a roadmap-gap audit scheduled the dropped modularity-arc Phase D → v6.3.29, generics tail → .30, protobuf → .31; anti-downgrade folded into .21; carry-in + watching items recorded; v7/LEGAL parked to one note — see [[feedback_roadmap_the_whole_arc]].**) PRIOR: **6.3.19** (v6.3.x cycle — **two more consumer-filed stdlib fixes (AGNOS base-stack migration to 6.3.15, cont'd)**, both lib-only → cycc **byte-identical**. **ws_server**: `http_find_header`→`sandhi_server_find_header` (4 dangling calls missed by the `http_*`→`sandhi_server_*` rename → reachable-undefined the moment a consumer's WS handshake ran; bote 2.7.7) + **first-ever ws test** `ws_server_handshake.tcyr` (reject-path; a stale name is now a *local* reachable-undefined, proven by revert). **agnos `sys_fstat`**: fail-closed peer `fn sys_fstat(fd, statbuf): i64 { return 0-1; }` mirroring `sys_access` — agnos kernel 1.51.2 dispatches **no fstat-by-fd** (only path-based `stat`#33; 0–63 table full → a real wrapper is agnos-kernel work); `--agnos` probe links clean, no `ud2`. api-surface regenerated (+`syscalls_x86_64_agnos::sys_fstat/2`, additions-only). **Third consumer issue triaged**: sankoch `zlib_compress` SIGSEGV was **not** a cyrius codegen bug and **not** a sankoch library bug — a workflow adversarial compress-path array audit found the library clean; the crash was the **test's own** `var chunks[4]` (4 B slot, `store64(&chunks+i*8)` i=0..3 = 32 B, 24-B frame overrun; daimon footgun). Fixed at sankoch source (`chunks: i64[4]`) + sankoch `cyrius.cyml` pin 6.2.44→6.3.18; full sankoch suite (20 tiers) 0-failed on 6.3.18; library unchanged → no re-vendor. check.sh 109/109; seed→cybs→cycc; ecb+cass+pi SELFHOST_OK; self_compile 537 ms; cycc 1,027,664 B (byte-identical to 6.3.18). Both cyrius issues resolved. See CHANGELOG [6.3.19].) PRIOR: **6.3.18** (v6.3.x — **stdlib undersized-array-locals hardening sweep** (consumer-filed, AGNOS migration). A precise **17-file agent audit** caught **2 GENUINE stack-smashes both in `lib/sankoch.cyr` bzip2**: `_bz_decode_block` `var pos[6]`→`[48]` + `_bze_emit_block` `var present[16]`→`[128]` — the daimon footgun (author meant i64 SLOTS, declared BYTES), **missed by the v6.3.13 sweep AND the v6.3.15 "0 over-runs" audit** (loop bound not resolved). New `sankoch_bzip2_roundtrip.tcyr`; the 34 sites the issue named were latent-benign (≤8 B writes fit the 1-slot alloc) → sized correctly anyway (byte-identical). cycc **byte-identical** (consumer-lib-only). check.sh 109/109; ecb+cass+pi SELFHOST_OK; bench 540 ms. See CHANGELOG [6.3.18].) **Earlier releases (6.3.17 back to v5.x): see CHANGELOG.md** — trimmed here (state.md keeps current + ~2 priors; the rest is canonical in CHANGELOG). |
