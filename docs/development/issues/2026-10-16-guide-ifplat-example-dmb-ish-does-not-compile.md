# The guide's `#ifplat aarch64` example `asm { dmb ish }` does not compile: aarch64 asm mnemonics take no operand — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-16 on the 6.7.14 infra lane's tree (l6714-infra) and on the slot-open
aarch64 cross compiler (6.7.13's src): refused both times. The guide's example has never compiled.
**Placement:** 6.7.15 — repair 5 (infra lane; filed from the 6.7.14 infra lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
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
