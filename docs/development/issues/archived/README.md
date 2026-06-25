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

## Archival conventions

- File header gains a `— RESOLVED` suffix and a status paragraph
  pointing at the fix version + commit / CHANGELOG section.
- File name is unchanged so external links (consumer bug reports,
  PR descriptions) keep working.
- If a resolved issue returns under a new manifestation, open a
  fresh issue in the parent folder and cross-reference this one.
  Don't resurrect archived files in place.
