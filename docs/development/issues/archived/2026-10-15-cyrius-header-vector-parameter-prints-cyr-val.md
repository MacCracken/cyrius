# `cyrius header` prints `cyr_val v` for a SIMD vector PARAMETER, which cycc receives in a vector register — RESOLVED

> ✅ **RESOLVED in v6.7.13** (TL-4: `cyrius header` refuses a public fn that takes a SIMD vector by value. The filed pv.cyr now gives `error: cyrius header: 'pv' takes 'v: f64v2': a SIMD vector parameter, which no C11 type carries; no prototype written`, rc 1, and the rest of the header is written (`cyr_val pr(cyr_val r);` is kept). It used to print `cyr_val pv(cyr_val v);` at rc 0. The refusal covers all twelve vector types, in any parameter position. A `*f64v2` parameter, and a `: Result` / `: Option` / `: Tagged` one, stay `cyr_val`. No decision needed: 6.7.12's D24 on the argument side. Census: only lib/simd.cyr changes, with 17 more refusals, and it was already rc 1. Rows: `header_spellings_and_size.sh` H8 (the repro verbatim; f64v4, i32v4 and a vector second parameter; the shapes that stay `cyr_val`; cc -std=c11 -pedantic-errors; two mutations RED). ⚠ This closes the filed shape only for a parameter list on ONE line. A vector parameter on a continuation line still escapes, because `cmd_header` reads only a declaration's first line. That gap is older than the lane; the review found it, and it is filed for 6.7.14. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 tools lane (l6712-tools, unit T5) with that lane's
`build/cyrius` and `build/cycc`. Named "met in passing" by the 6.7.12 triage of
issues/archived/2026-10-14-cyrius-header-stack-enum-return-prints-cyr-val.md (its Risk line, with a `: Result` parameter); the
D24 bite (issues/archived/2026-10-14-cyrius-header-vector-return-prints-cyr-val.md) refuses a vector RETURN only, so the
argument side is outside both filed surfaces.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Severity:** Medium — a generated C header that is wrong for every public fn taking a vector by value: the C caller
puts the argument in rdi (x0), the callee reads xmm0 (v0), so it computes on whatever the vector register held.
**Affects:** `cyrius header` (cbt/quality.cyr `cmd_header`'s parameter loop), every version that has it.

## Reproduction

```sh
printf 'fn pv(v: f64v2): i64 { return 0; }\nfn pr(r: Result): i64 { return r; }\n' > pv.cyr
T=$(mktemp -d); HOME=$T CYRIUS_HOME=$T/.cyrius build/cyrius header pv.cyr | grep '^cyr'; echo "rc=$?"; rm -rf "$T"
printf 'object;\nfn pv(v: f64v2): i64 { var a: f64v2 = v; return load64(&a + 8); }\n' | build/cycc > pv.o
llvm-objdump -d --no-show-raw-insn pv.o | awk '/<pv>:/,/ret/' | grep xmm
```

```
actual:   cyr_val pv(cyr_val v);          (rc 0)
          cyr_val pr(cyr_val r);
          pv's prologue: movupd %xmm0, -0x38(%rbp)   <- the parameter is read from xmm0, not rdi
expected: pv refused by name (stderr, rc 1), as D24 refuses a vector return ("no C11 type carries it") — never
          `cyr_val v`.
```

The `: Result` parameter the triage named is NOT a defect: a Result / Option / Tagged parameter is one word (its tag —
lib/tagged.cyr: "rdx never reaches a parameter"), so `cyr_val r` is right; only the vector parameter is wrong.

## Root cause

`cmd_header`'s parameter loop writes `cyr_val <name>` for every parameter and skips the `: type` text whole; it never
asks whether the type is one of the twelve vector names (`_hdr_vec_name`), which cycc passes in vector registers
(xmm / v; a 32-byte vector in two, or by a PE convention of its own).

## Proposed fix

In the parameter loop, read each parameter's type name and refuse the fn by name when it is a vector type (the D24
wording: a SIMD vector parameter, which no C11 type carries), with rows in
tests/gates/toolchain/header_spellings_and_size.sh beside H8's vector-return refusal rows (f64v2, f64v4, i32v4
parameters refused; `: Result` / `: Option` parameters still `cyr_val`).
