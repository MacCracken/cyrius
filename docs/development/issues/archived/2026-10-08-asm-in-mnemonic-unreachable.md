# `asm { in al, dx; }` is refused: `in` lexes as keyword 76, so the `ASM_IN` emitter is unreachable by its documented spelling — RESOLVED

> ✅ **RESOLVED in v6.7.14** (IN-13, `52616b617`, and IN-14, `f1a0b3dc6` + `51350b7e2` (the user's decision D16, 2026-10-16: refuse it, naming the mnemonic or operand; the `in` route and the width encoding are fixed to what the source says): the asm arm sends `in` (keyword 76) to the backend; x86 `ASM_IN` / `ASM_OUT` read their operands and encode the width — `in al|ax|eax, dx` EC / 66 ED / ED, `out dx, al|ax|eax` EE / 66 EF / EF — and refuse any other operand by name (`in takes al, ax or eax and then dx, not 'bl'`); aarch64 and cx refuse `in` by name. Mnemonics are matched whole on x86 and aarch64 and an unknown one is refused (`unknown x86 asm mnemonic 'clix'`, `unknown aarch64 asm mnemonic 'nopx'`), so `clix`, `inb al, dx` and `nopx` no longer assemble as cli / in / nop, and `out dx, eax` no longer as `out dx, al`. The filed repro compiles and emits EC (was `unexpected in` + `parser recovery aborted`). Every spelling in the guide's Inline Assembly list, lib/ and the corpus keeps its bytes; cx's refusal names the mnemonic and no longer aborts recovery. Rows: new `tests/gates/codegen/asm_mnemonics_whole.sh` (axis 1 the six encodings; axis 2 the guide's block, read from the guide, in a `kernel;` build and a program; axis 3 the corpus's spellings and `programs/asmtest.cyr`'s new `test_in` / `test_out`; axis 4 bad operands; axis 5 aarch64 / cx refuse `in`; axis 6 unknown mnemonics on x86 and aarch64); mutations RED on each axis they reach. The other x86 emitters that skip their operand (`lgdt` / `lidt` / `invlpg` / `mov crN` / `ltr` / `int N`) are outside this file and filed separately. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with the tree's `build/cycc`: `asm { in al, dx; }` gives `unexpected in` and then `parser recovery aborted`, in both a user-mode and a `kernel;` build. The documented sibling `asm { out dx, al; }` compiles.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (infra lane, wave 1, unit I4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D16 — Refuse it, naming the mnemonic or operand.
**Discovered:** before 2026-10-08 (carried in roadmap.md's backlog); filed 2026-10-08 from roadmap.md.
**Severity:** Low — the guide and the compiler disagree. Workaround: the raw byte `asm { 0xEC; }`.
**Affects:** cycc ≤ 6.7.6 (since `in` became the for-in keyword).

## Summary

The guide lists `asm { in al, dx; }  # Port input` among the kernel mnemonics
(`docs/guides/cyrius-guide.md:3260`), and the x86 backend has an emitter for it (`ASM_IN`). The asm block
parser dispatches to `ASM_MNEMONIC` only for an IDENT token (type 2). `in` is lexed as keyword 76 (the
for-in `in`), so the block reaches the `else { ERR(S); }` arm and the emitter is never reached.

## Reproduction

```cyr
fn rd(): i64 {
    asm { in al, dx; }
    return 0;
}
syscall(60, 0);
```

```sh
cat repro.cyr | build/cycc > /tmp/o
# actual:   error:<source>:2:11: unexpected in
#           error: parser recovery aborted (desync — too many errors)
# expected: compiles; the block emits 0xEC (`in al, dx`), as `asm { 0xEC; }` does today
```

## Root cause

- `src/frontend/parse.cyr:4159-4164`: the `asm { … }` arm of `_PARSE_STMT_IMPL` takes a number (raw
  byte) or `PEEKT == 2` (a mnemonic), else `ERR(S)`. `in` is token type 76
  (`src/common/util.cyr:2172`).
- `src/backend/x86/emit.cyr:5336` dispatches to `ASM_IN` (`:5447`) when the mnemonic's first two bytes
  are `in` (`mnem & 0xFFFF`). The documented `in` never gets there. Only an identifier that merely STARTS
  with `in` and is not matched earlier does: `asm { inb al, dx; }` compiles today and emits `0xEC`, through
  the same prefix looseness that assembles `clix` as `cli`.

## Proposed fix

In the asm arm, treat token 76 as the `in` mnemonic: on the x86 backend call `ASM_IN` with the cursor
placed as `ASM_MNEMONIC` leaves it (past the mnemonic). On the aarch64 and cx forks, refuse it by name as
an unknown mnemonic is refused today. ⚠ `ASM_IN` (`:5447`) ignores its operands and always emits `0xEC`,
so once the arm is reachable `in eax, dx` would silently assemble as `in al, dx`. The arm should validate
`al, dx` (or encode `ax` / `eax` as `66 ED` / `ED`). Add a gate row that disassembles the block, plus a
guide-example row.

## Related — the same matcher (found 2026-10-08 while filing; one bite with the above)

- `ASM_MNEMONIC` (`src/backend/x86/emit.cyr:5314`) matches mnemonics by BYTE PREFIX with no unknown-mnemonic refusal:
  `asm { clix; }` assembles as `cli` (0xFA), and `inb al, dx` as `in al, dx` — which is the only way `ASM_IN` is
  reachable today. Verified 2026-10-08: `clix` compiles (rc 0) and disassembles to `cli`.
- `ASM_OUT` (`src/backend/x86/emit.cyr:5455`) ignores its operands: `asm { out dx, eax; }` assembles as `out dx, al`
  (0xEE). Verified 2026-10-08 by objdump.

A fix matches whole mnemonics, refuses an unknown one by name, and either encodes the operand width or refuses a
width it does not encode.
