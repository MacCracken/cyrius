# v6.3.45 closeout audit — backlog (refactor consolidations, dead code, 2 latent bugs)

**Filed:** 2026-07-03 (the v6.3.45 minor-closeout judgment-call audit — heap-map / dead-code /
refactor / code-review / cleanup / security). The closeout LANDED the byte-identical doc-hygiene
fixes (heap-map map drift + stale binary names) and archived the .44-resolved issues. Everything
below touches compiler CODEGEN or needs a self-host+differential pass, so it is filed for
**v6.4.x-early** (not closeout — a closeout must stay byte-identical / self-host-safe).

## Two genuine latent bugs (safe today, no current trigger — but real)

### L1 — lex_pp `#ifdef`/`#define` flag table has a hard 16-slot cap with SILENT corruption past it
`src/frontend/lex_pp.cyr:~1319/1349`. The flag hash table at `S+0x190800` and the values at
`S+0x190880` are only `0x80` bytes (16 slots) apart, and `_pp_flag_count` is incremented with NO cap
guard. The 17th `#define` in one compilation unit corrupts `flag[0]`'s value (writes past the hash
array into the value array). Fix: add a cap check that hard-errors (like `gvar_toks` at
parse_decl.cyr:740), or relocate/grow the table. Safe today only because no unit defines >16 PP
flags. **A hard-error is byte-identical** (only fires on the 17th) — this one could even land early.

### L2 — `_msx` (EMACHO_SYSXLAT imm8 form) silently truncates any syscall number ≥ 128
`src/backend/x86/emit.cyr:829`. `_msx` emits `cmp rax, lin` via the imm8 opcode `0x83 /7` with an
unguarded byte, so a Linux source number ≥ 128 routed through `_msx` (instead of the `_msx32` sibling)
sign-extends and mistranslates silently. Safe today because every current `_msx` caller is ≤ 110
(the .44 getppid `110→39` is the current max). Fix: make `_msx` assert `lin < 128` (hard error) or
auto-dispatch to `_msx32` for ≥ 128, so a future macho syscall addition can't silently break. (The
aarch64 side already learned this the hard way at v6.0.60 — getdents64 217 needed the imm32 form.)

## Refactor consolidations — the ".44 EMIT_GVAR_INITS class" (parallel copies that take the same fix twice)

Each is a place where logic was hand-duplicated and then had to receive the SAME fix in N places
(the exact bug class that produced the .44 Str-field-global-scope miss). All are byte-identical
extractions IF done carefully, but they change parse/emit-side code → need a self-host + differential
pass, so they are v6.4.x-early, not closeout.

- **R1 — PARSE_FIELD_LOAD / PARSE_FIELD_STORE** (`parse_decl.cyr:~393`) duplicate three
  address-resolution blocks (pointer-vs-inline, the v5.8.17 sentinel + v6.3.16 ≤8B-inline logic, and
  the v6.3.33 chained-access leaf-retype) that have repeatedly taken the same fixes. Extract
  `_resolve_field_base_addr` / `_resolve_leaf_field`. **Highest-value** (most recent repeat-fixes).
- **R2 — EWRITE_PE / EREAD_PE** (`emit.cyr:~955/1196`) share the GetStdHandle fd-resolution prologue
  (`cmp rax,2; ja .direct; neg; sub; GetStdHandle`) — this is the EXACT block the .43 VR-01 fix had to
  re-apply to EWRITE after EREAD already had it. Extract `_pe_fd_to_handle_rcx` called by both.
- **R3 — scalar-type-name → byte-width decode ladder** (the i8/i16/i32/i64 magic-constant compare
  block) is hand-duplicated across `parse_types.cyr:485/535`, `parse.cyr:651`, `parse_expr.cyr:320`,
  and `parse_decl.cyr` (multiple). **NOTE (re-inspection):** NOT a clean 6-way collapse — the
  parse_decl copies also handle unsigned/f64/f32/u128 detection and the ann_scalar-vs-ann_float split,
  so a correct extraction must parametrize those, not just lift the ladder.
- **R4 — EVLOAD_W / EFIELD_LOAD_W** (`emit.cyr:~561`, x86 + aarch64) emit an identical width ladder;
  both took the v6.3.35 signed sign-ext fix. Factor per-backend, preserving the differing IR-record +
  flags wrappers.
- **R5 — EMIT_GVAR_INITS positional struct-init loop** (`parse_decl.cyr:~1062`) is a parallel copy of
  `PARSE_STRUCT_INIT`'s positional branch (the .44 example — reconciled for the Str fix, but two
  copies remain). Extract `_emit_struct_positional_init(S, target_idx, sid)` called from both.

## Dead code (byte-identical to remove, but not closeout — the IR substrate wants its own slot)

- **D1 — legacy `CYRIUS_IR=3` substrate helpers** in `src/common/ir.cyr` with ZERO live callers
  (`ir_lower_all`/`_ir_lower_node`/`ir_dce`/`ir_dead_store`/`ir_emit2`/`IR_BB_ID`/`IR_EDGE_FROM`).
  Unreachable on all targets; DCE already NOPs their bytes (no shipped cost). Removal is
  byte-identical-safe but `ir.cyr` is the delicate IR substrate → a dedicated IR slot, not closeout.
- **D2 — speculative disassembler CFG API** (`CLASSIFY_CF`/`CF_TARGET`) in `src/backend/x86/decode.cyr`
  (~:225), the v4.4.5 CFG-construction companion to `DECODE_LEN`, never consumed (the DCE call-graph
  is byte-scan-based, not decoder-based). Either wire into a real decoder-based pass or remove.

**DCE floor at closeout (v6.3.44 tree):** 61 unreachable fns / 24 239 bytes — dominated by documented
false-positive classes (~24 public stdlib fns dead in cycc but exercised by tcyr/benches/downstream;
~15 cross-arch/gated backend stubs). No removal action on those — all load-bearing.
