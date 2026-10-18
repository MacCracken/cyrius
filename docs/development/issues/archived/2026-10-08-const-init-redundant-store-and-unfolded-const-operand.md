# A top-level `var X = CONST;` is baked AND stored at run time; `2 * CONST` is not folded — RESOLVED

> ✅ **RESOLVED in v6.7.14** (item 1: FE-15, `735fb3c7` (decided with its companion issue, D11 (b), the user 2026-10-16); item 2: FE-16, `c0d6d1ba`; no decision needed for either item. (1) The replay steps over a baked entry whose store writes what the slot already holds (`_gvk_quiet`: the image value is the entry's own and the nearest earlier live writer of the slot, if any, is a baked entry of that value); an earlier computed writer of the slot or a const- / enum-named constant of another value (or `= 0`), a list-blob slot, a bool global and another file's private const keep the store; cx agrees through `_gv_cx_prestore`. The filed repro's entry code `mov eax,0x5; movabs rcx,0x600000; mov [rcx],rax` is gone (exit 15). (2) The `* / << >>` arms read their right factor's constant value without emitting (`_cf_fac_at`: a literal, a local or top-level integer const, an enum constant) and the `+ - & | ^` arms fold the whole right term (`_cf_can`): the filed `return 2 * C;` is `mov eax,0xa`, as are `1 + C` and `2 + C * 3`; values unchanged. Rows: `frontend/const_init_bake_and_fold.sh` S0 – S7, K1, O1 – O13, D1 – D3, V1 – V3, F1 – F21 (x86_64, aarch64, cx); `platform/kmode_enum_initializer_baked.sh` K / E / D; mutations `_gvk_quiet` → 0 (26 of 123 RED), `_gvk_prev` → −1 (12), `_cf_fac_at` literal-only (42), `_cf_can`'s term arm (21). Item 1 reaches beyond the filed text: an earlier initializer's call that writes such a global keeps its write (see the companion issue). Filed beside (6.7.15): an all-constant zone struct / tuple literal is still baked AND stored (`2026-10-16-zone-struct-literal-baked-and-stored.md`); `return 2 + 3 *% 4;` is refused (`2026-10-16-constant-left-literal-then-term-operator-refused.md`). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — both reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc` (x86_64, read from the
disassembly): `var X = C;` puts 5 in X's data slot AND emits `mov eax,5; movabs rcx,X; mov [rcx],rax` at startup,
where `var X = 5;` emits no store; `return 2 * C;` emits `mov eax,2; push; mov eax,5; pop rcx; imul rcx`, where
`C * 2`, `2 * 5` and a named `const D = 2 * C;` are one `mov eax,10`.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (frontend lane, wave 1, unit F3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** before 2026-10-08 (carried in roadmap.md's backlog; the redundant store is the one 6.6.16's bake kept
on purpose — "The store stays, so no code changes"); filed 2026-10-08 from roadmap.md.
**Severity:** Low — code size and startup work only (18 bytes and three instructions per such global on x86_64; one
multiply per unfolded expression); every value is right.
**Affects:** cycc 6.6.16 – 6.7.6 (the bake + kept store); the run-time fold's literal-only right operand since it
existed (not bisected)

## Summary

1. **The redundant store.** Since 6.6.16 a top-level scalar whose initializer folds through `_CF_TRY` with enum / const
   names on (`var X = C;`, `var X = E.A;`, `var X = A + 1;`) has its value BAKED into the var image (`_gvk_pre`), so a
   read before the deferred initializer replay — or an x86 `kernel;` build's late replay — sees it. The replay still
   emits the run-time store of the same value. A plain literal (`var X = 5;`) takes the v5.11.64 static-init path and
   emits no store.
2. **The unfolded constant operand.** The expression parser's run-time fold (`_cfo` / `_cfv`) folds `K op L` only when
   the LEFT side is a constant and the RIGHT side is a LITERAL token: `C * 2` → 10, `2 * C` → `imul`; `C + 1` → 6,
   `1 + C` → `add`; `2 + C * 3` folds `C * 3` and then adds. An array size or a named `const` folds all of them (the
   `_CF_TRY` folder).

## Reproduction

```cyrius
const C = 5;
var X = C;              # 1: baked AND stored
fn f(): i64 { return 2 * C; }   # 2: imul at run time
syscall(60, X + f());
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?          # 15 — the values are right
objdump -d -M intel --no-show-raw-insn /tmp/r | head -40                           # read the code
od -A x -t x8 -j 0x1000 -N 8 /tmp/r                                                 # X's data word: 5
```

Expected: no startup store for X (as with `var X = 5;`), and `f` is `mov eax,0xa`. Actual: the entry code begins
`mov eax,0x5; movabs rcx,0x600000; mov QWORD PTR [rcx],rax` (X's slot, already 5 in the image), and `f`'s body is
`mov eax,0x2; push rax; mov eax,0x5; pop rcx; imul rcx`.

## Root cause

1. `_gvk_pre` / `_gvk_one` (`src/frontend/parse_decl.cyr:4254`, `:4264`) bake the folded value into
   `_vgsi_base[slot]` and mark the entry (`_gvk_bk` = 1), but `EMIT_GVAR_INITS` (`parse_decl.cyr:4453`) replays every
   deferred entry's store regardless; the 6.6.16 comment above them (`:4197`–`4198`) records keeping the store as the
   choice that kept the code unchanged.
2. The fold arms test `if (_cfo == 1) { if (PEEKT(S) == 1) {` — the right operand must be token type 1, a numeric
   literal: PARSE_TERM's `*` arm (`src/frontend/parse_expr.cyr:5368`, and the `/` / `<<` / `>>` arms at `:5428`,
   `:5448`, `:5463`) and `_PEXPR_IMPL`'s `+` / `-` arms (`:6017`, `:6045`). A const name on the right is token type 2,
   parsed as a factor (which sets `_cfo` for the next operator, `:2594` / `:2857`, but nothing re-folds the pair).

## Proposed fix

1. In the replay, skip the run-time store of an entry `_gvk_pre` baked (`_gvk_bk` = 1) on the targets whose var image
   carries it (not cx, whose `_gv_cx_prestore` stores first). Check the orderings the 6.6.16 comment names before
   dropping it: a redeclared global (`_gv_fold` / `_gv_supersede` — the last declaration must still win), a slot a list
   blob covers (`_gvk_left`'s `GVGAI` case), and the x86 kernel late replay. Byte output changes (smaller); the self-host
   and seed gates confirm nothing reads the store.
2. Let the fold arms take a const / enum name on the right when it resolves to a constant (`_cst_*`, the same lookup the
   factor uses to set `_cfo`), or fold after the right operand is parsed when both sides set `_cfo` and nothing was
   emitted between (`_cfp`). Values are unchanged; a `tests/gates/` disassembly row for `2 * C` and `1 + C`.
