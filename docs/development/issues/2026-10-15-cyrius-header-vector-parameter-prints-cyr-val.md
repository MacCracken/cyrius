# `cyrius header` prints `cyr_val v` for a SIMD vector PARAMETER, which cycc receives in a vector register — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 tools lane (l6712-tools, unit T5) with that lane's
`build/cyrius` and `build/cycc`. Named "met in passing" by the 6.7.12 triage of
issues/2026-10-14-cyrius-header-stack-enum-return-prints-cyr-val.md (its Risk line, with a `: Result` parameter); the
D24 bite (issues/2026-10-14-cyrius-header-vector-return-prints-cyr-val.md) refuses a vector RETURN only, so the
argument side is outside both filed surfaces.
**Placement:** 6.7.13 — repair 3: struct values (tools lane; filed from the 6.7.12 tools lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
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
