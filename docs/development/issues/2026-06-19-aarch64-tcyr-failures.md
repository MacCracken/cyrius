# aarch64 stdlib/codegen failures surfaced by the VR-01 full-tcyr-on-arm64 gate

> **OPEN — a tracked aarch64-correctness arc.** v6.2.29 added the VR-01 gate that
> runs the FULL .tcyr suite on real arm64 (the `aarch64-native` CI job) — the first
> time on-hardware tcyr coverage existed beyond cycc self-host + funcgate. It
> immediately measured a real debt: **9 of 190 tests fail on real aarch64** (verified
> on pi, NOT just qemu — same cross-built binaries run natively). This is the exact
> "found by ports/consumers" class. The user's call (2026-06-19) was: **ship the
> gate now with these xfail'd + tracked, clear the debt as a follow-on arc.** They
> are listed in the gate's `XFAIL` skip-list (`.github/workflows/ci.yml`,
> `bare-metal`/`aarch64-native` job) — when one is fixed, remove it from that list
> (the gate flags an unexpected PASS).

**Filed:** 2026-06-19 · **Parent:** v6.2.29 VR-01. **Severity:** P1.

> **UPDATE (2026-06-19, post-cut): there are TWO distinct debt classes, and the
> VR-01 CI gate is now SOFT (`ci.yml` aarch64-native tcyr step) until both clear.**
> My initial pi validation used the x86-hosted CROSS compiler (`cycc_aarch64`);
> the CI uses the NATIVE compiler (`cycc_native_a64`, from `main_aarch64_native.cyr`),
> which exposed a second, larger class I missed:

## Class A — `main_aarch64_native.cyr` is a STALE 6th FORK (the primary CI cause)

The native compiler handles **ZERO annotation tokens** — `grep 'PEEKT(S) == 12[0-9]|13[0-9]'`
returns nothing, where `main_aarch64.cyr` (the cross fork) handles 122/124/125/126/127/133
(`#must_use`/`#deprecated`/`#pure`/`#io`/`#alloc`/`#naked`). It is **124 lines behind**
(471 vs 595). So ANY test whose libs use an annotation hits `unexpected enum` on the
native compiler — e.g. `bayan.cyr` uses `#pure` (125), so **base64 / bigint / csv /
cyml** and the `#derive` tests (`derive_serialize_*`, `alloc_serdes`) all fail to
COMPILE natively (they compile fine via the cross compiler — that's why pi-via-cross
missed them). The annotation gap is the same fork-desync class fixed for the other 5
forks at v6.2.27, but this fork was never on that list.

**Fix (a fork-parity arc):** (1) mirror the annotation-token consume from
`main_aarch64.cyr` into `main_aarch64_native.cyr`'s pass-1 + pass-2 dispatches (the
mechanical part — unblocks the annotation tests); (2) audit the remaining ~118 lines
of drift for other missing features (it lags more than just annotations). The native
self-host PASSES (byte-identical, qemu-verified) — the fork compiles ITSELF, just not
newer-feature consumer code. NB: the CI "aarch native self-host fails" report was the
whole job going red on the (then-hard) tcyr loop, not the self-host step.

## Class B — shared aarch64 backend/codegen bugs (affect cross AND native)

**Repro:** `build/cyrius build --aarch64 tests/tcyr/<name>.tcyr /tmp/b &&
qemu-aarch64 /tmp/b` (or real arm64). These fail on BOTH compilers — real backend
bugs. All PASS on x86_64.

## Crashes (SIGSEGV / SIGILL) — P1, likely codegen

| Test | Signal | Hypothesis |
|---|---|---|
| `hashmap_ext`        | SIGSEGV (139) | bad pointer / stack in the extended hashmap path on aarch64 |
| `process`            | SIGSEGV (139) | fork/exec/wait stdlib on aarch64 (process.cyr) — pointer or syscall-ABI |
| `math_inverse_trig`  | SIGILL  (132) | the aarch64 backend emits an ILLEGAL instruction — a bad NEON/FP encoding in the inverse-trig polyfill path. Distinct from the x86-only `f64_sin` compile-reject (that's `math_pack_integration`); this one COMPILES then traps. |
| `u128`               | SIGILL  (132) | illegal-instruction in 128-bit integer ops on aarch64 — a bad encoding in the u128 emit path (mul/div/shift). |

SIGILL (132 = 128+4) is the most diagnostic: the backend is emitting a word that
the CPU rejects. Start there — disassemble the emitted `.text` (`llvm-objdump
-d --mattr=+neon`), find the bad word, fix the encoder. Per
`project_cycc_aarch64_x86_hosted_repro`, these reproduce + fix on x86 with the
x86-hosted cross compiler + qemu — no Pi needed for the fix loop, only for final
sign-off.

## Functional failures (assertions fail, no crash)

| Test | Failed asserts | Area |
|---|---|---|
| `fdlopen`            | 7 | foreign dlopen on aarch64 (fdlopen.cyr) — note some of this may need a real aarch64 `.so` present; triage real-bug vs test-env |
| `io`                 | 2 | io.cyr on aarch64 (a syscall-number or struct-offset mismatch) |
| `result_stdlib_pass2`| 3 | Result<T,E> stdlib on aarch64 |
| `syscalls_at_family` | 4 | the *at syscalls (openat/etc) on aarch64 — likely ESYSXLAT renumber gaps (cf. the recurring aarch64 syscall-number-collision class) |
| `tls_native_scaffold`| 1 | tls_native scaffold on aarch64 |

## Not in this issue (handled in-slot at .29)

- `math` (log2 polyfill rounding) — FIXED in-slot (f64_round; was a test bug).
- `naked_fn_attribute` — FIXED in-slot (arch-conditional iretq/eret; was my .28
  x86-only test).
- `math_pack_integration` — `f64_sin` is x86-only by compiler design (hard compile
  reject on aarch64); SKIP-listed in the gate, not a bug.
- `tls_early_data_status` — was a qemu-user artifact only; PASSES on real pi. Not
  skip-listed.
- `unicode_normconf` — reads `tests/data/NormalizationTest.txt` at runtime; PASSES
  on real arm64 with the data file present (320547/0 on pi). Not a bug — the CI
  `actions/checkout` provides the corpus. (A binary-only staging run will falsely
  fail it; verify with the data file before ever xfail-listing it.)

## Suggested order

The 4 crashes first (P1 — they hard-fault any aarch64 program using those
features), SIGILL before SIGSEGV (illegal-instruction is a precise encoder bug).
Then the syscall-family functional fails (likely the known ESYSXLAT renumber
class). Each fix removes one entry from the gate's XFAIL list.
