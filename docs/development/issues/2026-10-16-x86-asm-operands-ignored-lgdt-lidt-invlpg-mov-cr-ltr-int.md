# x86 inline asm ignores the register operand of lgdt / lidt / invlpg / mov crN / ltr, and masks `int N` to 8 bits — each assembles a different instruction than its source names — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-16 on the 6.7.14 infra lane's tree (l6714-infra, after the D16 commits
that match mnemonics whole and give `in` / `out` real operands; these five emitters were not in that item's filed
surface).
**Placement:** 6.7.15 — repair 5 (infra lane; filed from the 6.7.14 infra lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-16, the 6.7.14 infra lane (unit I4), implementing `issues/2026-10-08-asm-in-mnemonic-unreachable.md`
(decision D16, 2026-10-16: an asm block naming an instruction cyrius's assembler does not have — a misspelled mnemonic,
or an operand the instruction cannot take — stops compiling, naming it). That item's surface was the `in` route, the
in / out operands and whole-mnemonic matching; the same "operand read past, never looked at" shape is in five more
x86 emitters.
**Severity:** Low — a silent wrong encoding of a privileged instruction on the developer's own source (kernel code); a
bug, not a vulnerability. Every spelling the guide, lib/ and the corpus use is the one the emitter hard-codes, so
nothing shipped is affected.
**Affects:** `src/backend/x86/emit.cyr` `ASM_LGDT`, `ASM_LIDT`, `ASM_INVLPG`, `ASM_MOV_CR`, `ASM_LTR`, `ASM_INT`.

## Reproduction

```sh
cat > p.sh <<'EOF'
for t in 'lgdt [rax]' 'lgdt [rbx]' 'lidt [rcx]' 'invlpg [rdi]' 'mov cr3, rax' 'mov cr3, rbx' 'mov rbx, cr3' \
         'mov cr9, rax' 'ltr ax' 'ltr bx' 'int 3' 'int 256' 'int 0x1FF'; do
  printf 'fn f(): i64 {\n    asm { 0xF1; 0xF1; 0xF1; %s; 0xF1; 0xF1; 0xF1; }\n    return 0;\n}\nsyscall(60, f());\n' "$t" > a.cyr
  rc=0; build/cycc < a.cyr > a.bin 2> a.err || rc=$?
  hex=$(od -An -tx1 -v a.bin | tr -d '\n' | sed 's/  */ /g' | sed -n 's/.* f1 f1 f1 \(.*\) f1 f1 f1 .*/\1/p')
  printf '%-16s rc=%s bytes=[%s]\n' "[$t]" $rc "$hex"
done
EOF
sh p.sh
```

Output:

```
[lgdt [rax]]     rc=0 bytes=[0f 01 10]
[lgdt [rbx]]     rc=0 bytes=[0f 01 10]      lgdt [rax]; lgdt [rbx] is 0f 01 13
[lidt [rcx]]     rc=0 bytes=[0f 01 18]      lidt [rax]; lidt [rcx] is 0f 01 19
[invlpg [rdi]]   rc=0 bytes=[0f 01 38]      invlpg [rax]; invlpg [rdi] is 0f 01 3f
[mov cr3, rax]   rc=0 bytes=[0f 22 d8]
[mov cr3, rbx]   rc=0 bytes=[0f 22 d8]      mov cr3, rax; mov cr3, rbx is 0f 22 db
[mov rbx, cr3]   rc=0 bytes=[0f 20 d8]      mov rax, cr3; mov rbx, cr3 is 0f 20 db
[mov cr9, rax]   rc=0 bytes=[0f 22 c8]      mov cr1, rax (cr9 does not exist; crN is read from one digit)
[ltr ax]         rc=0 bytes=[0f 00 d8]
[ltr bx]         rc=0 bytes=[0f 00 d8]      ltr ax; ltr bx is 0f 00 db
[int 3]          rc=0 bytes=[cd 03]
[int 256]        rc=0 bytes=[cd 00]         int 0 (the vector is 8 bits)
[int 0x1FF]      rc=0 bytes=[cd ff]         int 0xFF
```

(The annotations after the byte lists are the filer's, not the script's.)

## Root cause

- `ASM_LGDT` / `ASM_LIDT` / `ASM_INVLPG` check `[`, step over ONE token without reading it, check `]`, and emit the
  `[rax]` ModR/M (`0F 01 10` / `18` / `38`).
- `ASM_MOV_CR` reads which operand is `crN` (its third byte as the digit) and always encodes rax as the other
  (`ASM_CR_MODRM` = `0xC0 | crn << 3`, rm 0); a two-digit or nonexistent `crN` wraps into the reg field.
- `ASM_LTR` steps over its operand and emits `0F 00 D8` (ltr ax).
- `ASM_INT` takes any number and emits `PEEKV & 0xFF`.

## Fix shape

Under D16 (refuse what the assembler does not have, naming it): either encode the register (the ModR/M rm field from
`_asm_x86_reg`, which `param_load` already uses; REX.B for r8-r15 where the instruction allows) or refuse any operand but
the one encoded (`rax`, `ax`), naming it; refuse a `crN` other than cr0 / cr2 / cr3 / cr4 / cr8 and an `int` vector over
255, naming the operand. Which of encode-or-refuse is the user's call where it makes something compile that did not.
Rows: tests/gates/codegen/asm_mnemonics_whole.sh, beside its in / out axis — each form's bytes, and each refused form
named; the guide's Inline Assembly spellings (`lgdt [rax]`, `mov cr3, rax`, `int 3`, `invlpg [rax]`) keep their bytes.
