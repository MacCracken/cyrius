# Array-Typed Struct Fields — `Vec<T>` Handle Design (Pin 2, v6.4.x)

**Status**: PINNED — user-signed-off 2026-07-06. Ready to implement R1.
**Arc**: v6.4.x Pin 2 (array-typed struct fields). 3-release split.
**Consumer**: svara (M2 serde types); also naad/vidya round-trip tests.

Design produced by a code-grounded premise-check (5-reader workflow). Anchors are
`file:line` at time of reading — re-confirm before editing.

## Decision summary (signed off)

1. **Syntax = `Vec<T>`** (source spelling), NOT `T[]`.
2. **Representation = a typed `Vec<T>` *handle*** — an 8-byte i64 pointer to the heap
   Vec, concrete element type `T`. NOT inline fixed `T[N]`. Dynamic generic `Vec<T>`
   element-typing stays OUT of scope (concrete-T only).
3. **Metadata = a far-negative sentinel in the existing ftype cell** (no new heap pool).
4. **`#derive` codecs = 100% frontend** (emit Cyrius source) — cycc byte-identical.
5. **Split = 3 releases** (R1 parse+metadata / R2 Vec<primitive> derive / R3 Vec<struct>+svara).
6. **`svara_pt` raw buffer** → fixed svara-side (a **minor patch to svara at R3**:
   promote `svara_pt` to a 2-field `#derive` struct + bump the pin). The compiler adds
   no bespoke raw-buffer codec.

## Decisive ground-truth facts

- **`Vec` is not a registered struct** — `lib/vec.cyr:5` is a comment; fns return a bare
  i64 handle. `FINDSTRUCT(S,"Vec")` = 0. So the `IS_STR_FIELD` name-compare model is
  impossible for Vec — the ftype must carry an out-of-band encoding.
- **`0x93A000` is occupied** (`_fnt_cstrmask`, adjacent to `struct_ftypes@0x91A000` /
  `struct_fnames@0x92A000`). No free adjacent pool slot → a new parallel column would
  force a 7-fork heap relocation (the fork-rot hazard). The sentinel-in-cell approach
  avoids this entirely.
- **The "7-fork mirror" premise is FALSE.** All field-metadata *code* lives in shared
  source (`parse_types.cyr`, `parse_decl.cyr`, `parse_fn.cyr`, `lex_pp.cyr`, each included
  once via `parse.cyr:218`). The `main_*` forks carry only heap-map **comments**.
- **The `<= -2048` SIMD guards** (`parse_decl.cyr:219,427`) act on var/local types
  (`GLTYPE`), a *different* value space from the struct-field ftype cell (`GETFTYPE`). A
  Vec-field sentinel neither collides with them nor is covered by them — field guarding
  is a separate, enumerable obligation.
- **`from_json_str` (single-pass) cannot decode nested structs today** (`lex_pp.cyr:992`
  emits `# nested struct — skip for single-pass`); **`from_json` (pairs form) can**
  (recurses at `lex_pp.cyr:859`). This asymmetry sets the Vec<struct>-decode boundary → R3.

## 1. Syntax — `Vec<T>`

The `#derive` text pre-parser (`lex_pp.cyr:500-508`) captures the field type-name string
stopping only on `;`(59) `}`(125) space(32) `\n`(10) — not on `<`/`>`. So `xs: Vec<u8>`
lands verbatim as the string `"Vec<u8>"` in the type-name column (`S+0x1FE000`), and the
codec generator string-parses the inner `T` at emit time. `T[]` would require a stop-set
change plus a lost-element-type workaround, desyncing the two parsers.

**Main-parser change** — `PARSE_STRUCT_DEF` (`parse_types.cyr:462-497`) + the parallel
`PARSE_UNION_DEF` (`:528-545`). After capturing the type-name IDENT and before the
`ADDFIELD/ADDFIELDTYPED` dispatch, peek for `<`(token 19). If present: consume `<`, require
IDENT `E` (the element type), classify `E` with the existing inline scalar/struct logic
(`:482-495`), require `>`(token 20), then call a new `ADDFIELDVEC(S, si, fnoff, elem_code)`.
Type position after `:` → `<` unambiguously opens a generic arg (no comparison ambiguity).

For R1, **gate Vec fields to non-generic structs** (svara uses none) — leave the
`_tp_resolve` generic-instance branch (`:470-479`) untouched. Known limitation, not a defer.

## 2. Metadata — sentinel in the existing ftype cell

```
VEC ftype cell value = VEC_BASE - elem_code
  VEC_BASE = 0 - 0x40000   (-262144)   # far below sid range 1..1024 and the SIMD band
  elem_code: scalar T (i8/i16/i32/i64/f64/u*) -> small width/tag
             struct T                          -> struct sid (1..1024)
  scalar-vs-struct disambiguated by one tag bit in elem_code (mirrors SIMD _vd_signed)
```

Helpers (mirror the `IS_STR_FIELD` pair):
- `IS_VEC_FIELD(S, ft)` → `ft <= VEC_BASE && ft > VEC_BASE - 0x10000`. **Checked BEFORE any
  `ft>0` struct path and any `0-ft` scalar path.**
- `VEC_ELEM(S, ft)` → `VEC_BASE - ft`, then unpack width-or-sid + tag.
- `FIELDSZ` (`parse_types.cyr:184`): add `if (IS_VEC_FIELD(S,ft)) { return 8; }` as the
  **first** line.

Cross-fork footprint: **comments only** (no new region). While there, fix the stale
`main_aarch64.cyr:64-65` / `main_aarch64_macho.cyr:68-69` "256×32 grid v5.7.17" comments,
add the missing `main_x86_macho`/`main_cx` ones, and the stale `parse_types.cyr:17-18` header.

## 3. Field access + layout — 8-byte handle, no new load/store codegen

- Load: `PARSE_FIELD_LOAD` → `FIELDSZ`=8 → `mov rax,[rcx]` (`emit.cyr:561`). No change.
- Store: `PARSE_FIELD_STORE` → width 8 → `mov [rcx],rax`. No change.
- `accessors` derive (`lex_pp.cyr:1082`): `load64`/`store64` per field — already correct.

**Struct-literal init — the one real gotcha, in TWO parallel copies.** A Vec field must
take the single-8-byte-store branch (the Str branch), or the `else` at `parse_decl.cyr:646`
flattens it as a nested struct (`GETFCOUNT(ft-1)` slots) — and `ft-1` on the sentinel is a
wild OOB index. Both sites:
- `PARSE_STRUCT_INIT` (`parse_decl.cyr:643`) → `IS_STR_FIELD(...) || IS_VEC_FIELD(...)`.
- `EMIT_GVAR_INITS` (`parse_decl.cyr:1104`) → **same** change (the copy that shipped broken
  in v6.3.44; missing it → global-scope `var g = Foo{ xs: v };` hits `unexpected '}'`).

**Empty-array literal `Foo{ xs: [] }` is OUT of scope** — no list-literal production exists
(`[` is only subscript / `var a[N]`). R1 requires an explicit `vec_new()` initializer.
svara constructs handles explicitly, so it doesn't need `[]` sugar.

## 4. `#derive` codecs — frontend, emitted as Cyrius source

Lands in `PP_DERIVE_SERIALIZE_BODY` (`lex_pp.cyr:593`). Uses only existing lib fns
(`vec_new`/`vec_len`/`vec_get`/`vec_push`, `str_builder_*`) → cycc byte-identical. Element-T
is the raw string `"Vec<u8>"` in `S+0x1FE000`; add an emit-time parser (match `Vec<`, read
inner `T` to `>`, classify with existing first-byte gates). Factor the ~6× duplicated
outer-field classifier (`lex_pp.cyr:687,798,822,936,960`) into one helper reused for inner T.

Per-field emission for `Vec<T>`:
- **Encode**: `[` then, **guarded by `load64(ptr+OFF)!=0`**, loop `vec_len`/`vec_get`
  emitting each element by T (`str_builder_add_int` / `add_json_str` / `Struct_to_json`),
  comma-separated, then `]`. Null-handle guard mandatory (else `vec_len(0)` crashes).
- **Decode `from_json_str`** (the path svara exercises): scan `[ … ]`, `vec_new()`, loop
  `vec_push`. Int/f64/Str self-contained; **struct = the first recursive value-parse in this
  scanner** (net-new; today skips at `:992`) → R3.
- **Decode `from_json` (pairs form)**: already recurses at `:859` → composition.

Element storage: `vec_push`/`vec_get` are always i64 slots. Vec<u8>/Vec<i32> store widened
i64; width matters only for JSON text, never storage. Never emit `storeN`/`loadN` against
vec slots.

## 5. Minimal cut (svara-driven)

Vec<primitive> alone unblocks only `SvSpectrum.magnitudes` + `SvRenderOutput.samples`
(2 of ~10). The M2 marquee types (`SvPhonemeSequence.events`, `SvBatchRenderer.events`,
`SvTrajectoryPlanner.keypoints`) are all **Vec<flat #derive struct>** → Vec<struct> is on the
critical path (R3). No Vec<Str> anywhere → Str-element support NOT needed. `SvProsodyContour.
f0_points` is `Vec<svara_pt>` (raw `alloc(16)` pair) → svara-side minor patch at R3. SOA raw
buffers (`SvFormantBank`, `SvSynthCtx.buffer`) are `#[serde(skip)]`+rebuild, out of scope. The
101-phoneme table is an if-chain fn, never serde — a red herring.

## 6. Release split (boundaries at structural seams)

| Rel | Scope | Gate |
|---|---|---|
| **R1** | `Vec<T>` parse (`<`-peek, `ADDFIELDVEC`) + `VEC_BASE`/`IS_VEC_FIELD`/`VEC_ELEM` + `FIELDSZ`→8 + struct-init (both copies) + fork comments + tests (parse/load/store/init local+global/STRUCTSZ + rejection/no-OOB). No `#derive`. | **FULL** — self-host fixpoint + **seed-derive** + check.sh + **cross-OS ecb/cass/pi** + bench. cycc has no Vec fields so should stay byte-identical, but the sentinel touches shared decode paths → prove it. |
| **R2** | `#derive` Serialize/Deserialize for **Vec<primitive>** (int, f64), full round-trip. Inner-`Vec<T>` string parser; factor the 6× classifier; encode loop; `from_json_str` + `from_json` array scan. | self-host verify + seed-derive (trivial) + new `.tcyr`. Frontend-only; cycc byte-identical. |
| **R3** | `#derive` **Vec<struct>** (encode via recursive `_to_json`; pairs-decode via `:859`; **`from_json_str` recursive decode = net-new**) + **svara minor patch** (promote `svara_pt` → 2-field `#derive` struct, bump pin) + confirm svara serde types derive. | self-host verify + seed-derive + new `.tcyr` + downstream svara check. Frontend-only. |

**No R4** — the field is an arch-neutral 8-byte pointer and the codecs are portable Cyrius
source, so there is no per-arch tail. If a real cross-arch bug surfaces in R1's gate, fix it
*in* R1 (one-bug-one-complete-fix).

## 7. Risks / traps

1. **Sentinel guard obligation (`−2121` class).** `IS_VEC_FIELD` FIRST at every field-cell
   decode: `FIELDSZ`:184, `IS_STR_FIELD` `ft-1`:173, `PARSE_STRUCT_INIT`:643, `EMIT_GVAR_INITS`
   :1104, `FINDFIELD`, `parse.cyr:656` sizeof, `STRUCTSZ`. Miss one → `ft-1 = −262146` OOB.
   **The single highest-risk item, fully enumerable — audit these ~7 sites in R1.**
2. **Two `PARSE_STRUCT_INIT` copies (v6.3.44 déjà vu).** :643 and :1104 both need it; a
   global-scope `.tcyr` is the regression guard.
3. **Two field-type parsers must agree** — `PARSE_STRUCT_DEF` + the `#derive` pre-parser.
   `Vec<T>` chosen precisely so both tolerate it.
4. **`from_json_str` nested-struct gap (`:992`)** — isolate to R3; keep out of R2.
5. **Str-vs-Vec** — both 8-byte pointers, but Str is name-detectable and Vec is not. The
   sentinel is mandatory; do not model Vec on the name-compare.
6. **Empty/null Vec zero-value** — encode must guard `load64(...)!=0` before `vec_len`.
7. **Widened-i64 element storage** — never `storeN`/`loadN` against vec slots.
8. **Generic-struct Vec field** — the `_tp_resolve` branch (`:470`) is untouched in R1;
   Vec fields gated to non-generic structs. Documented limitation.
9. **32-byte derive type-name slot** — `Vec<LongStructName>` could approach the cap at
   `S+0x1FE000`; verify a slot-length guard when Vec<struct> lands (R3).

## Files touched

- Parser + metadata: `src/frontend/parse_types.cyr` (PARSE_STRUCT_DEF :462, PARSE_UNION_DEF
  :528, ADDFIELDVEC/IS_VEC_FIELD/VEC_ELEM near :99-191, FIELDSZ :184).
- Struct-init: `src/frontend/parse_decl.cyr` (:643 and :1104 — both copies).
- Codecs (R2/R3): `src/frontend/lex_pp.cyr` (type capture :500, PP_DERIVE_SERIALIZE_BODY
  :593, encode ~:646, from_json ~:782, from_json_str ~:888).
- Fork heap-map **comments only**: `src/main.cyr`, `main_win.cyr`, `main_aarch64.cyr`,
  `main_aarch64_macho.cyr`, `main_aarch64_native.cyr`, `main_x86_macho.cyr`, `main_cx.cyr`.
- Consumer pin (R3): `../svara/cyrius.cyml` + the `svara_pt` promotion.
- **NOT touched**: any `backend/*/emit.cyr`, `fixup.cyr` (`0x91A000` there is a stale comment
  mislabel, not shared storage).
