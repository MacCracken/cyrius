# Monomorphization engine (`CYRIUS_MONOMORPH=1`) bug inventory — v6.3.35/.36 repair list

**Filed:** 2026-07-02 (from the v6.3.34 adversarial discovery sweep — 7 dimensions, each verified)
**Severity:** N/A for default builds — ALL of these are gated behind `CYRIUS_MONOMORPH=1` (opt-in
experimental). Default codegen is unaffected. These block making generics a real, default feature.
**Scope:** v6.3.35 = repairs; v6.3.36 = finalize generics. The engine (v6.3.9/.10 instantiate-once)
has accumulated a bug tail; treat as a focused de-risking + completion effort, not one-off patches.

The sweep confirmed **8 distinct gated miscompiles** (all reproduced by a skeptic verifier). They
cluster into ~3 root causes.

> **RESOLUTION (v6.3.37, 2026-07-03):** premise-check found **A2 + A4 already fixed** by the v6.3.35 A1
> `_jt_snapshot`. **A3, C1, B1, B2 fixed** in v6.3.37 (all gated → default byte-identical; verified via
> a 5-agent root-cause workflow + adversarial re-sweep). **B3 deferred to v6.3.38** (base-emission rework
> — the one HIGH-risk unproven item; depends on B1, now landed). See CHANGELOG [6.3.37] +
> `project_v6337_generics_engine_repairs`. A pre-existing default-path bug surfaced while fixing:
> `2026-07-03-le8byte-struct-byval-second-call-reads-zero.md`.

## Root cause A — inline-instance emission corrupts the enclosing fn (ROOT-CAUSED)

`_instantiate_generic_fn` emits the specialized body INLINE at the call site (EJMP0 over it,
`PARSE_FN_DEF`, EPATCH). `PARSE_FN_DEF` resets the per-fn jump-target table (`S64(S+0x19E000, 0)`)
and jump_src table at fn start — so the inline instance **wipes the enclosing fn's recorded jump
targets**, and `_instantiate_generic_fn` does not save/restore them. The enclosing fn's LASE
(`IS_JUMP_TARGET`) then mis-eliminates loads at branch joins; the enclosing fn's compactor loses
sources. Fix direction: save the enclosing fn's jump-target + jump_src tables before the inline
`PARSE_FN_DEF` and merge-restore them after (the instance's own LASE/compaction already ran on its
range with a clean table). Symptoms:
- **A1** (filed separately, `monomorph-inline-instance-clobbers-live-local-after-branch`): an `if`
  before a first-use inline generic call folded into a live local → local clobbered (`r = r + idg<i32>(7)` → 7 not 37).
- **A2** early `return` dropped when followed by a first-use inline instance: `return 42; return idg<i8>(99);` → 99.
- **A3** `idg<i64>(idg<i64>(5) + idg<i64>(37))` → 74 (= 37+37; first operand clobbered by the second inner instance's emission).
- **A4** a generic fn whose body first-instantiates another generic (`outer<i32>` calls `inner<i32>`)
  returns an argument-independent constant (132) — the outer instance's codegen is clobbered by the nested first-use emission.

## Root cause B — monomorphized struct-return / by-value ABI not rebound per instance

- **B1** generic fn returning a multi-field generic struct (`fn mk<T>(...): Pair<T>`) — fields past the
  first read 0 (i32) or SIGSEGV (i64); retptr not set for the specialized struct-return. (Single-field
  OK; non-generic struct return OK; inline-built struct OK.)
- **B2** inferred receiver `var b = mk()` for a by-value generic struct with ≥2 sub-i64 fields copies
  only the first field (`b.w` reads 0).
- **B3** (filed separately, `generic-fns-struct-type-args`): generic fn with a STRUCT type-arg
  (`wrap<i64,Point>`) — by-value struct param + struct-return retptr not rebound → wrong value; currently
  hard-errored by the v6.3.33 `-3` guard.

## Root cause C — monomorph-mode parser: by-value struct-param call

- **C1** under `CYRIUS_MONOMORPH=1` ONLY, a call passing a struct BY VALUE emits a spurious
  `unexpected ';'` unless it is the sole direct operand of `return` — even for a non-generic struct
  (`struct S{v:i32}; fn f(s:S):i32{...}; f(s);` → parse error). The identical program compiles without
  the flag. The monomorph pre-scan mishandles any call whose callee has a by-value struct parameter.

## Verification for the repair slots

Each fix must be reproduced-then-confirmed-fixed with the sweep's minimal repros (above), plus new
`monomorph_*.tcyr` fixtures. Default codegen must stay byte-identical (all gated). Re-run the
adversarial sweep after the repairs to confirm the tail is dry (loop-until-dry). The generic-struct
instantiation itself (nested / multi-param) shipped correct in v6.3.33 — these are emission/ABI bugs
on top of correct instantiation.
