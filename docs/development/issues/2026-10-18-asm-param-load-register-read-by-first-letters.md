# An asm `param_load(reg, idx)` reads its register by the first letters: `param_load(raxx, 0)` is rax, `param_load(r8d, 0)` a 64-bit r8 load — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 infratools lane (l6715-infratools, unit I3, x86_64 Linux,
the lane's build/cycc), identical on the slot-open compiler (b2e1f4c48's build/cycc).
**Placement:** unplaced — filed from the 6.7.15 infratools lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Low — accepted bad syntax in an asm block on the developer's own source; the bytes are a valid load of
the register the name STARTS with. A bug, not a vulnerability.
**Kind:** language (refusing a spelling that compiles today is 6.7.14's D16 class — "an operand the instruction cannot
take stops compiling, naming it" — but it is a newly refused shape, so the call is the user's).
**Discovered:** unit I3 (issues/2026-10-16-x86-asm-operands-ignored-lgdt-lidt-invlpg-mov-cr-ltr-int.md), which gave
lgdt / lidt / invlpg / mov crN a whole-name register reader (`_asm_x86_gpr`) over the same table; param_load was
outside that filing's surface.

## Reproduction

```sh
printf 'fn f(a): i64 {\n    asm { 0xF1; 0xF1; 0xF1; param_load(raxx, 0); 0xF1; 0xF1; 0xF1; }\n    return 0;\n}\nsyscall(60, f(1));\n' > pl.cyr
build/cycc < pl.cyr > pl.bin; echo rc=$?
od -An -tx1 -v pl.bin | tr -d '\n' | sed 's/  */ /g' | sed -n 's/.* f1 f1 f1 \(.*\) f1 f1 f1 .*/\1/p'
```

Output:

```
rc=0
48 8b 45 f8          mov rax, [rbp-8]
```

`param_load(r8d, 0)` likewise: rc 0, `4c 8b 45 f8` (mov r8, [rbp-8] — a 64-bit load though the name is the 32-bit
r8d). The aarch64 twin (`_asm_aarch64_reg`, src/backend/aarch64/emit.cyr) matches `x0` .. `x30` on their first two or
three bytes the same way (`param_load(x0abc, 0)` is x0); not measured on the cross compiler here.

## Root cause

`_asm_x86_reg` (src/backend/x86/emit.cyr) compares 2 or 3 bytes of the name (`n & 0xFFFFFF == 0x786172` for rax)
without its NUL, and ASM_PARAM_LOAD takes its answer as is; a name that is not a register at all is a bare `ERR(S)`
(no name). 6.7.15's `_asm_x86_gpr` (the NUL test over `_asm_x86_reg`) is the whole-name reader the other operand
forms now use.

## Fix

Read param_load's register with `_asm_x86_gpr` (and an aarch64 whole-name twin), refusing any other name through
`_asm_refuse`, naming it. Rows: asm_mnemonics_whole.sh — `param_load(raxx, 0)` / `param_load(r8d, 0)` refused naming
the operand; `param_load(rax, 0)`, `param_load(r12, 1)` keep their bytes; the aarch64 cross compiler likewise.
