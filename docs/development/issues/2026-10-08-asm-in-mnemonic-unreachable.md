# `asm { in al, dx; }` is refused: `in` lexes as keyword 76, so the `ASM_IN` emitter is unreachable by its documented spelling — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with the tree's `build/cycc`: `asm { in al, dx; }` gives `unexpected in` and then `parser recovery aborted`, in both a user-mode and a `kernel;` build. The documented sibling `asm { out dx, al; }` compiles.
**Placement:** 6.7.12 — Break 2, repair 3 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
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
