# 2026-06-16 — a `var` syscall NUMBER silently defeats the macOS/Windows reroute (class)

> **RESOLVED — v6.2.16.** Both remaining instances fixed at their source repos +
> re-folded: **yukti 2.2.6** (event/device_db CLOCK_REALTIME timestamps now use
> stdlib `chrono.clock_epoch_secs()`; dead `SYS_CLOCK_GETTIME` removed) and
> **sakshi 2.3.1** (x86 TSC-calibration `clock_gettime`/`nanosleep` now use literal
> `228`/`35`; `_sk_clock_now_ns_raw` takes the GetTickCount64 return on Windows;
> dead `_SK_SYS_*` consts removed; the `sakshi.tcyr` nanosleep probe fixed to
> literal 35 + `nap[16]`). The literal-228/35 routing was proven cross-OS in v6.2.15
> (`bench_elapsed` on ecb/cass/pi). The compiler-side guardrail/const-fold options
> below were considered and left for a future minor (a blanket warning would be
> noisy with false positives on ESYSXLAT-covered var syscalls; const-folding global
> int-literal vars is a frontend change out of a lib-fold slot's scope). See
> CHANGELOG [6.2.16].

> **Class:** the macOS `__got` libcall reroutes and the Windows IAT reroutes for
> "Linux-numbered" syscalls (`parse_expr.cyr`, e.g. `syscall(228)`→
> `_clock_gettime_nsec_np`, `syscall(35)`→`Sleep`, `syscall(1)`→`WriteFile`) are
> keyed on a **compile-time literal** first argument. `sc_num` is set only when the
> first arg const-folds (`parse_expr.cyr:453` — `if (_cfo == 1) sc_num = _cfv`).
> A `var SYS_FOO = 228; syscall(SYS_FOO, …)` does **not** fold → `sc_num = -1` →
> the reroute never fires → a raw `svc`/`syscall` with the Linux number, which on
> Darwin/Windows is a different (or nonexistent) call. **And it is silent**: the
> "not routed" warning at `parse_expr.cyr:477` is gated on `sc_num >= 0`, so the
> `var` case emits no diagnostic at all.
>
> **Status (filed):** the motivating instance — `lib/bench.cyr` `now_ns` using
> `syscall(SYS_CLOCK_GETTIME, …)` → `-9` (dead clock) on arm64-macOS — is **FIXED
> in 6.2.15** (literal `228`, mirroring `chrono.clock_now_ns`). This issue tracks
> the remaining instances + the general guardrail question.

## Why Linux is immune

Linux `svc` with the un-rerouted Linux number genuinely *is* the intended call
(e.g. syscall 228 on x86-64/aarch64 Linux *is* `clock_gettime`). So the bug is
invisible on the dev host and in CI's Linux matrix — it only bites macOS/Windows,
exactly the "found by ports / found by consumers" failure mode.

## Remaining instances (ecosystem libs — source-repo fixes, then re-fold)

These are the language's stdlibs (vendored via `cyrius deps`); per the ecosystem
rule, fix the **source repo**, hold for release, re-fold — never hand-edit the
`# Do not edit` vendored copy.

| lib | site | issue |
|-----|------|-------|
| `yukti` | `lib/yukti.cyr:1042,4638,4707,4924` | `syscall(SYS_CLOCK_GETTIME, 0, &ts)` — `var` number **and** the Linux read-`&ts` pattern (Darwin returns ns in the register and does not fill `&ts`; CLOCK_MONOTONIC is 6, not 1). Dead on macOS/Windows if yukti targets them. |
| `sakshi` | `lib/sakshi.cyr:171,202` | `syscall(_SK_SYS_CLOCK_GETTIME, 4, &ts)` + `syscall(_SK_SYS_NANOSLEEP, …)` — same `var`-number + read-`&ts` pattern. |

Note: a *literal* alone is not sufficient for these — they also use the Linux
read-`&ts` timespec pattern, so a full Darwin/Windows port of their clock path is
needed (literal number **+** take the return value **+** Darwin clock-id 6), the
way `chrono.clock_now_ns` / `bench.now_ns` now do. Whether yukti/sakshi claim
macOS/Windows timing support is for their maintainers; filed so the footgun is
tracked rather than rediscovered.

## Guardrail options (compiler-side, future)

- **A precise warning is hard.** Most `var`-based syscalls in the stdlib are fine —
  on aarch64/macOS the ESYSXLAT chain renumbers the runtime `x8`, so a `var` works
  for ESYSXLAT-covered numbers. Only the `__got`/IAT *libcall* reroutes need a
  literal. The compiler can't tell at parse time whether a `var` will hold an
  ESYSXLAT number or a reroute-required one, so a blanket "non-constant syscall
  number on macho/PE" warning would be noisy with false positives (net/async use
  `var`-based syscalls that work).
- **Const-folding global `var X = <int-literal>` references** at the syscall site
  would auto-route these and fix the whole class deterministically — but that is a
  frontend constant-folder change (self-host + cross-arch byte-identical risk),
  out of scope for the v6.2.15 bench-tooling slot. Candidate for a future minor.

## Durable lesson

A syscall NUMBER that must hit a macOS `__got` or Windows IAT reroute MUST be a
**literal** at the call site, never a `var`/named constant — until the const-fold
enhancement lands. See `lib/bench.cyr` `now_ns` for the canonical pattern + the
in-source comment, and CHANGELOG [6.2.15].
