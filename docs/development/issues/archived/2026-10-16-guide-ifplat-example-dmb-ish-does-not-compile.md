# The guide's `#ifplat aarch64` example `asm { dmb ish }` does not compile: aarch64 asm mnemonics take no operand — RESOLVED

> ✅ **RESOLVED in v6.7.15** (IT-8, `e3133d664`, and IT-7, `390b2108c` — the user's decision D37 (2026-10-18): accept the option. IT-8: `dmb` / `dsb` take sy, st, ld, ish, ishst, ishld, nsh, nshst, nshld, osh, oshst or oshld and `isb` takes sy, each into the CRm field (llvm-mc's words: `dmb ish` D5033BBF, `dsb sy` D5033F9F); a bare barrier is the full-system one; the next mnemonic is never read as an option (`dmb` / `dsb` / `isb` on three lines stay three barriers); a word the barrier has no option for is refused, naming it (`dmb foo` → 'foo', `isb ish` → 'ish'). The filed repro compiles (rc 0; it was `unknown aarch64 asm mnemonic 'ish'`), its binary holds bf 3b 03 d5 and exits 0 under qemu-aarch64, and the guide's `#ifplat` example compiles as written. IT-7 (no decision needed: a codegen fix met checking this item): this file's root-cause line was wrong — the fixed words were `dmb #0` (D50330BF, not `dmb ish`), SSBB (D503309F, not `dsb sy`), `isb #0` (D50330DF) and, for `wfe`, `msr S0_3_C1_C0_1, x0` (D5031020); they are now D5033FBF, D5033F9F, D5033FDF and D503205F. `svc #0`, which the fix shape lists, still cannot be written (`#` starts a comment; the guide says so, and D37 named the barriers only). Rows: `tests/gates/codegen/asm_mnemonics_whole.sh` axis 6's word row (IT-7) and axis 9 (21 forms and three refusals; IT-8); `tests/gates/toolchain/guide_examples_compile.sh` axis 5 (every guide block with an `#ifplat aarch64` line compiles with the aarch64 cross compiler; the example's binary holds D5033BBF); new `tests/tcyr/crossos/asm_barrier_options.tcyr` (2 / 2 on qemu-aarch64, cx, pi and ecb); mutations RED on each. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-16 on the 6.7.14 infra lane's tree (l6714-infra) and on the slot-open
aarch64 cross compiler (6.7.13's src): refused both times. The guide's example has never compiled.
**Placement:** 6.7.15 — repair 5 (infratools lane, wave 1, unit I3; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D37 — Accept the option.
**Discovered:** 2026-10-16, the 6.7.14 infra lane (unit I4), surveying every asm spelling in the guide, lib/ and the
corpus for `issues/archived/2026-10-08-asm-in-mnemonic-unreachable.md` (decision D16: an unknown mnemonic is refused by name).
**Severity:** Low — the guide teaches a spelling the compiler refuses; a doc / compiler mismatch, not a miscompile.
**Affects:** `docs/guides/cyrius-guide.md` (the `#ifplat` paragraph, `asm { dmb ish }`), `src/backend/aarch64/emit.cyr`
`ASM_MNEMONIC` (dmb / dsb / isb / svc take no operand).

## Reproduction

```sh
cat src/main_aarch64.cyr | build/cycc > cc_a64 && chmod +x cc_a64
printf '#ifplat aarch64\n    asm { dmb ish }\n#endif\nsyscall(60, 0);\n' > dmb.cyr
./cc_a64 < dmb.cyr > dmb.bin; echo "rc=$?"
```

Output (the 6.7.14 lane's tree; the slot-open compiler printed `error:<source>:2: unknown aarch64 asm mnemonic`):

```
error:<source>:2:15: unknown aarch64 asm mnemonic 'ish'
        asm { dmb ish }
                  ^
rc=1
```

## Root cause

The aarch64 asm block has no operands: each mnemonic is one fixed word (`dmb` = `D50330BF`, which IS `dmb ish`;
`dsb` = `D503309F`, `dsb sy`; `isb` = `D50330DF`, `isb sy`; `svc` = `D4000001`, `svc #0`), so the option `ish` is read
as the next mnemonic. tests/tcyr/codegen/inline_asm_fences.tcyr and lib/ write the bare `dmb` / `dsb` / `isb`.

## Fix shape (the user's call: it is what valid cyrius means)

Either the guide writes `asm { dmb }` (and says the barrier is `ish` / `sy`), or the aarch64 assembler accepts the
option that its fixed word already encodes (`dmb ish`, `dsb sy`, `isb sy`, `svc #0`) and refuses any other by name
(D16). Row: the guide's `#ifplat` example compiles on aarch64 (guide_examples_compile.sh compiles include-less blocks
with the x86 compiler only, so it never saw this).
