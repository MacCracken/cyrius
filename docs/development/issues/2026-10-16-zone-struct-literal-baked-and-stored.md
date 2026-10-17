# A declaration-zone struct literal of constants is baked into the image AND stored again at startup — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 frontend lane (l6714-frontend, unit F3, after the scalar
fix of `issues/2026-10-08-const-init-redundant-store-and-unfolded-const-operand.md` item 1), x86_64.
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-16 by the 6.7.14 frontend lane, unit F3: item 1's filed surface is the SCALAR `var X = C;`;
the struct literal `_spc_try` bakes (6.6.16, `_gvk_bk` 2) keeps its replayed stores.
**Severity:** Low — code size and startup work only (per field on x86_64: `mov eax,imm; push rax; movabs rcx,G; [add
rcx,off;] pop rax; mov [rcx],rax`); every value is right.
**Kind:** codegen (size).

## Reproduction

```cyrius
struct P { a; b; }
var p = P { 1, 2 };
syscall(60, p.b);
```
```sh
cat r.cyr | build/cycc > r && chmod +x r && ./r; echo $?               # 2
objdump -d -M intel --no-show-raw-insn r | sed -n 7,20p                # the entry code stores 1 and 2
od -A x -t x8 -j 0x1000 -N 16 r                                        # 0000000000000001 0000000000000002 (baked)
```
The entry code is `mov eax,0x1; push rax; movabs rcx,0x600000; pop rax; mov [rcx],rax; mov eax,0x2; push rax;
movabs rcx,0x600000; add rcx,0x8; pop rax; mov [rcx],rax` before the program — while the image already holds both
words. The named form (`P { a: 1, b: 2 }`, baked since 6.7.14 by `_spc_nfields`) and a tuple literal (`_spc_try` with
`_spc_cl` 11) are the same.

## Root cause

EMIT_GVAR_INITS's struct-literal arm (src/frontend/parse_decl.cyr) runs `_spc_try` (the bake) and then
`_gvi_struct_body` (the stores) for every literal; 6.7.14's `_gvk_quiet` / `_gvi_baked` step over a baked SCALAR
entry only (bk 1 → 3).

## Fix

The scalar rule for bk 2: when `_spc_try` baked the literal and no earlier live writer of the slot exists (or the
earlier one is a baked literal of the same bytes), step the literal's tokens to its `}` instead of emitting the
stores (diagnostics the walk gives — a refused field, a float into an int field — must still be given). Rows: the
binary byte-identical to a build whose image holds the value and no code (as const_init_bake_and_fold.sh S0-S7), the
kmode_enum_initializer_baked.sh struct patterns re-derived, and x86_64 / aarch64 / cx / PE values.
