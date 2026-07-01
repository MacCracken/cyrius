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
| **Version** | **6.3.23** (v6.3.x cycle — **unreviewed dimensions: DX-01 + DX-02 + SEC-AGNOS-01** — the "completeness critic" cluster no analyst owned. **DX-01**: the `CYRIUS_SYMS` function-symbol dump (crash-localization "`<16-hex VA> <name>`" per fn) was inline in `x86/fixup.cyr` and the **aarch64 backend emitted nothing** (silent x86-ELF-only rot) → hoisted to a shared **`_emit_sym_dump(S, base)`** in `runtime.cyr`, called from x86 **and** aarch64 fixup with the target-correct base (portable `SYS_OPEN`/`SYS_WRITE`/`SYS_CLOSE` + aarch64 `openat` shim); PE crash-reporter base fixed to ImageBase+text-RVA; cx N/A (bytecode, `_read_env` stub); rot-guard `tests/dx01_syms_parity.sh`; behind the env guard → **byte-identical** emitted programs. **DX-02** (`cyrius-lsp`): real **OOB stack write** fixed — `var pipe_fds[2]`/`status_buf[1]`→`[16]` (the daimon footgun the v6.3.18 sweep missed in `programs/`) + `Content-Length` 16 MB cap + `read_body` null-check + `uri_to_path` `..`-traversal reject + adversarial **Phase 4** in the LSP check gate (traversal-URI + missing-uri didOpen → valid documentSymbol still answers). **SEC-AGNOS-01**: assessed against fn bodies — entropy (getrandom #45 fail-closed), W^X (2-PT_LOAD default), PIE/ASLR (non-PIE ET_EXEC; ASLR cross-repo), `alloc_agnos` (CVE-24/25/26 guards) all SAFE / correctly cross-repo → **no cyrius-side code change owed**; 2 stale comments corrected. CVE-29 shipped v6.2.44; LEGAL-01 alone remains (v7). check.sh 113→**114**; cycc self-host fixpoint + seed→cybs→cycc byte-identical; ecb+cass+pi SELFHOST_OK; self_compile 539 ms; cycc 1,027,672 B. See CHANGELOG [6.3.23].) PRIOR: **6.3.22** (v6.3.x cycle — **verification coverage: VR-02 real fuzzing + VR-04 binary lint** (VR-01 split to its own slot .34, cross-host). **VR-02** REAL mutation fuzzers (shipped `fuzz/` were fixed-input): `tests/cycc_parser_fuzz.sh` (byte-mutated hostile source → cycc stdin parser, assert no crash/hang — **400 inputs/0 crashes**, `CYCC_FUZZ_ITERS`-tunable check gate) + `fuzz/tls_client_hello.fcyr` (adversarial ClientHello bodies → the network-facing `_tn_parse_client_hello`, fresh server ctx/iter — in `cyrius fuzz`, **120/0**). **VR-04** pure-cyrius **ELF** structural lint (`_binary_structural_lint_gate`, services.cyr): magic/ELFCLASS64/e_type/e_machine + PH & SH tables in bounds + every PT_LOAD file range + **entry-in-executable-segment** on an emitted binary; PE/Mach-O skips gracefully (follow-on, folded into VR-01 .34). Both parsers held (0 crashes). check.sh 111→**113**; cycc **byte-identical** (test/check-program only, no compiler/lib change); self-host fixpoint + seed→cybs→cycc; ecb+cass+pi SELFHOST_OK; self_compile 539 ms; cycc 1,027,672 B. See CHANGELOG [6.3.22].) PRIOR: **6.3.21** (v6.3.x cycle — **the security-audit tail (RM-06)**. **CVE-09**: `src/backend/x86/jump.cyr` now HARD-ERRORS past 1023 jump targets/fn instead of silently dropping them (which let LASE, `CYRIUS_IR=3`, mis-eliminate a live load → wrong codegen); byte-identical for every real program (0 corpus hits; the v6.3.20 `differential.sh` proved it logic-preserving 304/304 — the gate's first real use); regression `tests/jump_target_cap.sh` (check.sh 110→**111**). **CVE-11**: stack canaries ACCEPTED-WITH-RATIONALE (guard page CVE-29 + W^X + PIE supersede them). **CVE-21 anti-downgrade floor** in `install.sh` (`~/.cyrius/signed-since` TOFU-pin; unsigned install ≥ floor refused unless `CYRIUS_ALLOW_UNSIGNED=1`; logic unit-tested). **CVE-10** paper-closed; **RM-02** threat-model refreshed (16 MB output cap); audit cadence pinned **v6.4.0**. Premise-check caught 2 stale claims: the v6.3.23 CVE-29 row (shipped v6.2.44) + the `tls_native.cyr` "known holes" header (all 3 implemented). Self-host fixpoint + seed→cybs→cycc; check.sh 111/111; ecb+cass+pi SELFHOST_OK; self_compile 539 ms; cycc 1,027,672 B (+8 B, x86-only). See CHANGELOG [6.3.21].) **Earlier releases (6.3.20 back to v5.x): see CHANGELOG.md** — trimmed here (state.md keeps current + ~2 priors; the rest is canonical in CHANGELOG). |
