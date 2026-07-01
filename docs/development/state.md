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
| **Version** | **6.3.22** (v6.3.x cycle — **verification coverage: VR-02 real fuzzing + VR-04 binary lint** (VR-01 split to its own slot .34, cross-host). **VR-02** REAL mutation fuzzers (shipped `fuzz/` were fixed-input): `tests/cycc_parser_fuzz.sh` (byte-mutated hostile source → cycc stdin parser, assert no crash/hang — **400 inputs/0 crashes**, `CYCC_FUZZ_ITERS`-tunable check gate) + `fuzz/tls_client_hello.fcyr` (adversarial ClientHello bodies → the network-facing `_tn_parse_client_hello`, fresh server ctx/iter — in `cyrius fuzz`, **120/0**). **VR-04** pure-cyrius **ELF** structural lint (`_binary_structural_lint_gate`, services.cyr): magic/ELFCLASS64/e_type/e_machine + PH & SH tables in bounds + every PT_LOAD file range + **entry-in-executable-segment** on an emitted binary; PE/Mach-O skips gracefully (follow-on, folded into VR-01 .34). Both parsers held (0 crashes). check.sh 111→**113**; cycc **byte-identical** (test/check-program only, no compiler/lib change); self-host fixpoint + seed→cybs→cycc; ecb+cass+pi SELFHOST_OK; self_compile 539 ms; cycc 1,027,672 B. See CHANGELOG [6.3.22].) PRIOR: **6.3.21** (v6.3.x cycle — **the security-audit tail (RM-06)**. **CVE-09**: `src/backend/x86/jump.cyr` now HARD-ERRORS past 1023 jump targets/fn instead of silently dropping them (which let LASE, `CYRIUS_IR=3`, mis-eliminate a live load → wrong codegen); byte-identical for every real program (0 corpus hits; the v6.3.20 `differential.sh` proved it logic-preserving 304/304 — the gate's first real use); regression `tests/jump_target_cap.sh` (check.sh 110→**111**). **CVE-11**: stack canaries ACCEPTED-WITH-RATIONALE (guard page CVE-29 + W^X + PIE supersede them). **CVE-21 anti-downgrade floor** in `install.sh` (`~/.cyrius/signed-since` TOFU-pin; unsigned install ≥ floor refused unless `CYRIUS_ALLOW_UNSIGNED=1`; logic unit-tested). **CVE-10** paper-closed; **RM-02** threat-model refreshed (16 MB output cap); audit cadence pinned **v6.4.0**. Premise-check caught 2 stale claims: the v6.3.23 CVE-29 row (shipped v6.2.44) + the `tls_native.cyr` "known holes" header (all 3 implemented). Self-host fixpoint + seed→cybs→cycc; check.sh 111/111; ecb+cass+pi SELFHOST_OK; self_compile 539 ms; cycc 1,027,672 B (+8 B, x86-only). See CHANGELOG [6.3.21].) PRIOR: **6.3.20** (v6.3.x cycle — **the differential-corpus gate (VR-03)**, the perf-arc prerequisite. Codifies the "logic-preserving" verification (a ~338-input old-vs-new byte-identical corpus + DCE torture, muscle memory since v6.1.5/.6/.8) into `scripts/differential.sh`: OLD cycc (`git show ref:build/cycc`, the tracked binary) + NEW cycc compile a deterministic **304-input corpus** (src compilers + tcyr + programs + benches + fuzz) in default + `CYRIUS_DCE=1` modes; `cmp` all → identical / codegen-diff / status-diff / both-fail. Manual-trigger (`--quick`/`--smoke`). **Validated both ways**: clean self-run all-identical (303/304, `programs/io.cyr` a non-standalone both-fail); vs pre-.15 cycc correctly flags the array-locals codegen diffs **RED** — a real detector, not a placebo. Functional `_differential smoke gate` rot-guard (check.sh 109→**110**) so the manual gate can't rot (the macOS-CI lesson). The ONLY guard between the perf arc (.25–.27 regalloc/copy-prop/DSE) and a silent miscompile → **MUST precede it**. cycc **byte-identical** (scripts + check-program only). check.sh 110/110; seed→cybs→cycc; ecb+cass+pi SELFHOST_OK; self_compile 545 ms; cycc 1,027,664 B. See CHANGELOG [6.3.20]. **Also 2026-07-01 (doc-only): a roadmap-gap audit scheduled the dropped modularity-arc Phase D → v6.3.29, generics tail → .30, protobuf → .31; anti-downgrade folded into .21; carry-in + watching items recorded; v7/LEGAL parked to one note — see [[feedback_roadmap_the_whole_arc]].**) **Earlier releases (6.3.17 back to v5.x): see CHANGELOG.md** — trimmed here (state.md keeps current + ~2 priors; the rest is canonical in CHANGELOG). |
