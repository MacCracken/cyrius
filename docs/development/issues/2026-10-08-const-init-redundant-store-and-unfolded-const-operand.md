# A top-level `var X = CONST;` is baked AND stored at run time; `2 * CONST` is not folded — OPEN

**Status:** 🟡 **OPEN** — both reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc` (x86_64, read from the
disassembly): `var X = C;` puts 5 in X's data slot AND emits `mov eax,5; movabs rcx,X; mov [rcx],rax` at startup,
where `var X = 5;` emits no store; `return 2 * C;` emits `mov eax,2; push; mov eax,5; pop rcx; imul rcx`, where
`C * 2`, `2 * 5` and a named `const D = 2 * C;` are one `mov eax,10`.
**Placement:** 6.7.12 — Break 2, repair 3 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
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
