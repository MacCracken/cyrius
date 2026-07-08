# Archived Issues

Resolved issue reports. Kept for history — so the next agent can
grep a symptom and find the fix version without re-investigating.

**Filing a new issue?** See [`../README.md`](../README.md) — this
folder is history only; active items and the submission template
live one level up.

Active issues live in the parent `docs/development/issues/`
folder; move them down here when fix verification lands and
cross-reference the CHANGELOG entry that closed them.

## Index

| File | Brief | Resolved in |
|------|-------|-------------|
| [`2026-07-07-lexid-dedup-cap-too-low-for-large-consumers.md`](./2026-07-07-lexid-dedup-cap-too-low-for-large-consumers.md) | LEXID identifier-dedup table cap (16384) — a hard per-compilation-unit ceiling large multi-bundle consumers (stiva) legitimately hit. Raised 16384→65536; `lexid_entries` relocated to arena-top `0x7300000`, all 7 forks' arenas extended to `0x7400000`. Two-step, byte-identical, proven with a 20000-ident program. | **v6.4.21** |
| [`2026-06-28-tls13-server-get-version-zero.md`](./2026-06-28-tls13-server-get-version-zero.md) | `tls_native_get_version(srv)` returned 0 after a 1.3 handshake — the server accept path never stored the negotiated version. `respond_hello` now stores `TLS_VERSION_1_3`; freestanding tcyr flipped back to a version assertion. Lib-only, cosmetic (P3). | **v6.4.21** |
| [`2026-06-10-verification-coverage-gaps.md`](./2026-06-10-verification-coverage-gaps.md) | VR-01/02/03/04 verification-coverage sweep (found-by-consumers class). VR-01/02 (arm64 tcyr corpus + fuzz gate), VR-03 (`scripts/differential.sh` gate), VR-04 (ELF/PE structural lint) all shipped. Surviving Mach-O-lint residual re-filed as `2026-07-07-macho-structural-lint-residual.md`. | **v6.2.29 → v6.3.43**; Mach-O residual pinned to slot T. |
| [`2026-07-02-monomorph-engine-bug-inventory.md`](./2026-07-02-monomorph-engine-bug-inventory.md) | 8 gated `CYRIUS_MONOMORPH=1` miscompiles (A1–A4, B1–B3, C1) from the v6.3.34 adversarial sweep. All shipped; generics went default-on. Multi-tparam residual tracked in `2026-07-02-generic-fns-struct-type-args-monomorph-abi.md`. | **v6.3.35 → v6.3.39** + v6.4.0 default-on flip. |
| [`2026-07-03-v6345-closeout-audit-backlog.md`](./2026-07-03-v6345-closeout-audit-backlog.md) | v6.3.45 closeout backlog — L1/L2 latent-bug guards + R1/R3/R4/R5 parallel-copy consolidations. All shipped byte-identical. R2 (PE prologue) + D1/D2 (dead IR/decode code) deferrals re-filed as `2026-07-07-v6415-closeout-residuals.md`. | **v6.4.15**; R2/D1/D2 residuals re-filed. |
| [`libro-unblock.md`](./libro-unblock.md) | Libro release blocker from the v3.4.20 P(-1) review — three missing `include` directives in `src/main.cyr` + silent undefined-function stubs. Cyrius side kept the warning → error policy on undefined fns; libro shipped the fix and is now at 1.0.3 in the ecosystem. | v3.4.20 libro-side + Cyrius diagnostic improvements through v4.x. |
| [`parser-overflow-large-codebase.md`](./parser-overflow-large-codebase.md) | Bug #32: parser overflow at ~12 K expanded lines — preprocessed buffer cap caught real consumers (agnosys, agnostik) with 256 KB sources. | **v3.3.17** — preprocess_out expanded to 1 MB. |
| [`readfile-512kb-cap.md`](./readfile-512kb-cap.md) | READFILE calls in `src/frontend/lex.cyr` used a hardcoded 512 KB cap after the preprocess_out buffer had grown to 1 MB — silent truncation producing misleading parse errors on large include graphs. | **v4.8.4 retag** — READFILE caps raised to 1 MB, `PP_IFDEF_PASS` size guard added, directive detection moved off the capped S+0 mirror onto the mmap'd `tmp` buffer. |
| [`2026-06-23-call-arity-no-check.md`](./2026-06-23-call-arity-no-check.md) | tentib M3c: call-site arg-count mismatch silently accepted (binds garbage / shifts args, build says `OK`). | **v6.2.41** — non-fatal `_CHECK_ARITY` warning across normal/tail-call/inline paths; backward-ref + variadic + ctor carve-outs; surfaced+fixed the `ESUBRSP` latent bug (cycc self-compiles arity-clean). |
| [`2026-06-24-f64-le-nan-comparison-returns-true.md`](./2026-06-24-f64-le-nan-comparison-returns-true.md) | prajna: `f64_le(NaN,x)` returned true — float `<=`/`==`/`<`/`!=` + the `f64_lt`/`f64_eq` builtins ignored the IEEE unordered (parity) flag. | **v6.2.41** — `EF64_CMP` folds `setnp`/`setp` (x86) + `cset le`→`ls` (aarch64); IEEE-correct on x86 + real ARM (41/41 probe). |
| [`2026-06-10-release-trust-chain-integrity.md`](./2026-06-10-release-trust-chain-integrity.md) | CVE-20/21 release trust-chain: installer fail-open, unpinned deps/Actions, no signing, no seed→cycc derivation. | **v6.2.30/.31 + 2026-06-20** — fail-closed installers, `cyrius.lock` SHA-pins, SHA-pinned Actions, `cyrsign` Ed25519, seed→cybs→cycc byte-identical. (Archived v6.2.41 housekeeping.) |
| [`2026-06-10-roadmap-drift-and-stale-docs.md`](./2026-06-10-roadmap-drift-and-stale-docs.md) | RM-01…05 roadmap/governance doc drift (phantom TLS arc, stale threat-model, cc3-drop contradiction, etc.). | **v6.2.25 doc sweep (2026-06-19)** — all five RM items corrected. (Archived v6.2.41 housekeeping.) |
| [`2026-06-24-sigil-certpin-run-capture-signature-mismatch.md`](./2026-06-24-sigil-certpin-run-capture-signature-mismatch.md) | sigil `certpin_core` called the obsolete 2-arg `run_capture(cmd, argv)` (vs the 5-arg API) → cert-pin-via-openssl silently broken; surfaced by the v6.2.41 arity check. | **v6.2.42** — fixed upstream in **sigil 3.9.3** (5-arg `run_capture` + output buffer), folded byte-identical. |
| [`2026-06-23-agnos-portability-sweep-residuals.md`](./2026-06-23-agnos-portability-sweep-residuals.md) | agnos residuals: sakshi clock ran the x86 TSC path (syscall 228/35) on agnos → garbage calibration; mmap/dynlib/fdlopen raw Linux syscalls unguarded on agnos. | **v6.2.43** — sakshi 2.4.2 (agnos `uptime_ms` clock) folded; `#ifdef CYRIUS_TARGET_AGNOS` fail-closed gates on mmap/dynlib/fdlopen (native). |
| [`2026-06-14-stdlib-constant-value-collisions.md`](./2026-06-14-stdlib-constant-value-collisions.md) | Two libs defining the same `ERR_*`/`SYS_*`/`TK_*` symbol with conflicting values → silent last-def-wins under co-link (e.g. sigil `ERR_IO=6` vs yukti `ERR_IO=14`). | **v6.2.11** (`CHKDUPVAL` guardrail) + **v6.2.43** (sigil 3.9.4 `SIGIL_ERR_*` / yukti 2.2.7 `YUKTI_ERR_*`; patra `SQLT_*` + net `NSYS_*` already done). |
| [`2026-07-05-decode-len-mislengths-no-modrm-0f-opcodes.md`](./2026-07-05-decode-len-mislengths-no-modrm-0f-opcodes.md) | `DECODE_LEN` treated every non-Jcc `0F xx` as ModR/M-bearing → mis-lengthed `0F 05` SYSCALL / `0F A2` CPUID, so the DCE validator conservatively kept dead syscall-containing fns. Fail-safe (opt-in DCE only, no miscompile). | **v6.4.15** — added the no-ModR/M `0F` set as fixed-2-byte cases; default codegen byte-identical, `CYRIUS_DCE=1` torture deliberately re-baselined (278 inputs, all 0x90 NOP-fill of dead fns). |
| [`2026-07-05-valform-simd-param-typecheck-only-when-simd-return.md`](./2026-07-05-valform-simd-param-typecheck-only-when-simd-return.md) | Value-form SIMD arg type mismatch (`f64v2`→`f32v4` param) accepted silently in TAIL-CALL position (`return simdfn(local)`). Filed root-cause (mask==0 for non-SIMD-return) was wrong — mask is correct; the tail path just never read it. | **v6.4.15** — reject-only mask check added to `PARSE_RETURN`'s tail path (read-only FINDFN, byte-identical); `tests/simd_vec_reject.sh` Guard 3. |
| [`2026-06-25-bare-local-array-slot-write-lint.md`](./2026-06-25-bare-local-array-slot-write-lint.md) | Follow-on lint: warn on `var a[N]` (N bytes) written as N slots. | **v6.4.15 hygiene** — consolidated into the DX/cyrlint watching list in `roadmap-future.md` (no consumer blocked). |
| [`2026-06-25-syscall-write-byte-length-gate.md`](./2026-06-25-syscall-write-byte-length-gate.md) | Follow-on lint: permanent DOTALL gate that `syscall(SYS_WRITE,fd,buf,LEN)` LEN matches the literal byte length (~543 sites). | **v6.4.15 hygiene** — consolidated into the DX/cyrlint watching list in `roadmap-future.md` (batched with the bare-local-array lint). |
| [`2026-07-07-aarch64-no-trig-polyfill.md`](./2026-07-07-aarch64-no-trig-polyfill.md) | `f64_sin`/`f64_cos` hard-rejected on aarch64 (no native trig, no polyfill) → any trig-consuming amalgamation fails the aarch64 build. attn11 hearing lane + hisab num_fft twiddles blocked. | **v6.4.16** — `_f64_sin_polyfill`/`_f64_cos_polyfill` in core `lib/math.cyr` (v5.7.31 exp/ln pattern) + `EF64_SIN`/`EF64_COS` aarch64 dispatch; tier-1 accuracy, qemu-verified. |
| [`2026-07-07-cx-f64-compare-result-typing.md`](./2026-07-07-cx-f64-compare-result-typing.md) | f64 comparisons misbehaved in `if()`/`==N` on cx (`if (f64_lt)` always true). Root cause: cx's flag-less `EJCC` re-compared against a stale r1 on the bare-boolean path (NOT the F64 type — a frontend SESTYPE fix was tried + rejected). | **v6.4.19** — cx `ETESTAZ` sets r1=0 (real truthiness test) + `EF64_CMP` re-wired to the 0x5A-0x5F opcodes; cx-backend-only, cycc byte-identical. Also fixed latent bare-int-bool branches. |

## Archival conventions

- File header gains a `— RESOLVED` suffix and a status paragraph
  pointing at the fix version + commit / CHANGELOG section.
- File name is unchanged so external links (consumer bug reports,
  PR descriptions) keep working.
- If a resolved issue returns under a new manifestation, open a
  fresh issue in the parent folder and cross-reference this one.
  Don't resurrect archived files in place.
