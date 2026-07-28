# Cross-compiling to PE or Mach-O silently drops `lib/simd.cyr`'s value-form SIMD wrappers — the same source builds differently depending on where you build it

**Discovered:** 2026-07-27, by the v6.4.x closeout code-review pass.
**Severity:** **High** — a half-shipped language feature. v6.4.31 shipped Win64 value-form SIMD and
v6.4.32 shipped it on cx; the **cross-compile path was never brought along**, so the feature has been
native-only for the whole minor.
**Affects:** `src/main.cyr:1005-1009` (the PE and Mach-O cross branches), `lib/simd.cyr`,
`docs/guides/cyrius-guide.md`, four `vr01_*` tcyr headers.

## Evidence

Every **native** fork predefines the flag; `src/main.cyr`'s **cross** branches do not:

```
$ grep -rn 'CYRIUS_HAS_VAL_SIMD_PARAMS' src/main*.cyr
src/main_cx.cyr:129 · src/main_aarch64_macho.cyr:270 · src/main_x86_macho.cyr:163
src/main_aarch64.cyr:330 · src/main_aarch64_native.cyr:271 · src/main_win.cyr:459
src/main.cyr:1015 (agnos) · src/main.cyr:1022 (linux)
```

`src/main.cyr:1005-1009` — `if (_is_pe_build == 1) { PP_PREDEFINE(S, "CYRIUS_TARGET_WIN"); … }` and
the `_is_macho_build` arm at `:1009` predefine **only** the target macro.

`git blame -L455,460 src/main_win.cyr` → `34437d019` 2026-07-08 (v6.4.31) added it natively;
`main.cyr`'s PE arm is `79940e817` 2026-04-20 and was never updated.

Empirical proof, probe = `#ifdef CYRIUS_HAS_VAL_SIMD_PARAMS fn probe(): i64 { return 1; } #endif` +
`fn main(): i64 { return probe(); }`:

```
cat probe.cyr | ./build/cycc                        → rc=0, 4448 bytes
cat probe.cyr | CYRIUS_TARGET_AGNOS=1 ./build/cycc  → rc=0, 4448 bytes
cat probe.cyr | CYRIUS_TARGET_WIN=1  ./build/cycc   → rc=1  error: refusing to emit binary with 1 reachable undefined function
```

## Impact

A consumer using value-form SIMD (`f64v2_lo(v)`, `f32v4_add(a,b)` — the whole
`#ifdef CYRIUS_HAS_VAL_SIMD_PARAMS` block at `lib/simd.cyr:500+`) compiles natively on cass/ecb/ach
but fails with `undefined function` when cross-built from Linux via `cyrius build --target win` or
the `CYRIUS_MACHO` path. **The same source produces two different programs depending on where it was
built.** Nothing in the gate suite covers it.

## Compounding rot — the docs say this is intentional

Value-form SIMD is described as "non-PE" in **11 places**, which reads as design intent rather than
as the bug it is, and actively obstructs diagnosis:

- `lib/simd.cyr:23` "…(defined by every non-PE `main_*.cyr`)."
- `lib/simd.cyr:494` `# --- Value-form typed wrappers (non-PE targets only) ---`
- `lib/simd.cyr:496` "except `main_win.cyr`. On Win64 PE these fns are absent;"
- `lib/simd.cyr:648` `# --- f32v4 value-form (non-PE) …`
- `tests/tcyr/vr01_f64v2_ctor.tcyr:7-9`, `vr01_f32v4_ctor.tcyr:13`, `vr01_f32v8_ctor.tcyr:9`,
  `vr01_ints_ctor.tcyr:8`, `simd_overload_dispatch.tcyr:21`
- `docs/guides/cyrius-guide.md:444`, `:466` — which the same guide contradicts 32 lines later at `:498`

**The four `vr01_*` headers are the dangerous ones**: they claim these gates SKIP on cass, and
`vr01_*` is exactly the glob the release gate's cross-OS step runs there. A future agent triaging a
cass failure will conclude the tests don't run on Windows when they do.

## Fix

Two lines in `src/main.cyr`:

- `:1006` after `PP_PREDEFINE(S, "CYRIUS_TARGET_WIN");` add `PP_PREDEFINE(S, "CYRIUS_HAS_VAL_SIMD_PARAMS");`
- `:1009` after `PP_PREDEFINE(S, "CYRIUS_TARGET_MACOS");` add the same

Replace the stale v5.10.39 rationale comment at `:1018-1021` ("so PE builds skip them") with the
`.31`/`.32` reality, and correct all 11 "non-PE" claims above.

**This is a `src/` change** — cycc bytes move, so seed-derive is mandatory and the full release gate
(cross-OS ×4) is the verification, since it exercises both the cross and native paths.

`lib/simd.cyr` is vendored into consumers via `cyrius deps` — refresh the install snapshot after
editing (CLAUDE.md's snapshot-ping-pong section).

## Acceptance criteria

1. The probe above compiles under `CYRIUS_TARGET_WIN=1` and the Mach-O cross path on a Linux host.
2. A new tcyr compiles a **value-form** SIMD call under `CYRIUS_TARGET_WIN=1` **on the Linux host** —
   not only on cass, since the whole defect is that the cross path diverges from the native one.
3. Mutation-proven: revert one predefine and confirm the new gate goes RED.
4. Zero remaining "non-PE" claims about value-form SIMD in `lib/`, `docs/`, or `tests/`.

## Placement

v6.4.82 closeout or the first v6.5.x patch — it needs a full gate run either way. **Not 7.x.**
