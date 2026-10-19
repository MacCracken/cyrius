# A declaration-zone struct literal of constants is baked into the image AND stored again at startup — RESOLVED

> ✅ **RESOLVED in v6.7.15** (FE-15, `8981d679b` — no decision asked: 6.7.14's D11 (b) (a constant initializer is the global's value from program start) applied to the baked literal, as the filed fix says. `_gvs_quiet` (src/frontend/parse_decl.cyr) drops a baked struct / tuple literal's stores when no earlier live writer of the slot exists and no later entry may bake other bytes over the image, or the nearest earlier writer is a baked literal of the same bytes; the walk still runs for its diagnostics and `_gvs_mark` / `_gvs_undo` take back the code it emitted. The filed repro now enters straight into the program (its two stores gone; exit 2; the image unchanged), byte-identical to `var p: i64[2] = { 1, 2 };`; the named form and a tuple likewise (71 test binaries smaller). Value change beyond D11's text: a call in an earlier initializer that writes the global keeps its write (`var r = setp(); var p = P { 1, 2 };` p.a 1 → 9); a redeclared literal of other bytes keeps declaration order — filed for the user's decision (6.7.16, `2026-10-18-struct-tuple-literal-redeclaration-order-vs-d2.md`). Rows: `const_init_bake_and_fold.sh` S12 – S24 (the filed repro verbatim among S17 – S24), Z1 – Z13, V6 – V8, T5 – T8 (`tests/tcyr/crossos/zone_struct_literal_value.tcyr` on x86_64 / qemu / cxvm / wine; 18 of 18 there and on pi, ecb, ach and cass); `kmode_enum_initializer_baked.sh` K / E / KF / S; mutations RED as the gate's ledger says. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 frontend lane (l6714-frontend, unit F3, after the scalar
fix of `issues/archived/2026-10-08-const-init-redundant-store-and-unfolded-const-operand.md` item 1), x86_64.
**Placement:** 6.7.15 — repair 5 (frontend lane, wave 1, unit F5; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
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
