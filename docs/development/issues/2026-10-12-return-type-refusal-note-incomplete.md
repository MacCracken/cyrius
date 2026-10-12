# The "cannot be a fn return type" note lists an incomplete return-type set: `bool`, a multi-value `(T1, T2)`, `dyn Tr` and a generic's `T` are accepted but not named — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the 6.7.10 slot-open tree (`efb6623f`, `build/cycc` 2,057,744
B). `fn f(): u8` is refused with `type 'u8' cannot be a fn return type` and this note: "a return type is a struct,
i8/i16/i32/i64, f64, a vector type, Result, Option, Tagged, cstring or a pointer *T; return an i64 (no annotation) for
the others". The compiler also accepts these, each compiled and run on x86_64 against the tree:

- `: bool` (6.7.3): exit 1;
- `: (i64, i64)` (6.5.21): exit 7;
- `: dyn Show` (6.7.8): exit 7;
- a generic's `: T` (`fn id<T>(a: T): T`): exit 6.

The guide's list (§ *Type names (6.6.16)*, "A return type is a struct, `i8`..`i64`, `f64`, `bool` (6.7.3), a vector type, `Result`,
`Option`, `Tagged`, `cstring`, a pointer `*T` (6.6.17), a multi-value `(T1, T2)` / `(T1, T2, T3)` … or `dyn Tr`
(6.7.8)") is complete. The compiler's note lags it.
**Placement:** 6.7.11 — repair 1 (roadmap.md § *6.7.11*) — placed 2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (the guide's type-name section, re-verified against the compiler's
messages).
**Severity:** Low. A diagnostic's help text is incomplete. The accepted set is right; a reader is steered away from
`bool`, tuples and `dyn` returns that work.
**Affects:** cycc 6.6.16 (the note, `02121475`) – the 6.7.10 tree. `*T` was added to it at 6.6.17 (`3c24a52b`); `bool`
(6.7.3) and `dyn Tr` (6.7.8) never were, and the multi-value form (6.5.21) predates it.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
printf 'fn f(): u8 { return 1; }\nsyscall(60, f());\n' | build/cycc > /tmp/rt
# error:<source>:1:9: type 'u8' cannot be a fn return type
#   note: a return type is a struct, i8/i16/i32/i64, f64, a vector type, Result, Option, Tagged, cstring or a
#         pointer *T; return an i64 (no annotation) for the others
printf 'fn f(): bool { return true; }\nsyscall(60, f());\n' | build/cycc > /tmp/rb && chmod +x /tmp/rb && /tmp/rb; echo $?   # 1
printf 'fn f(): (i64, i64) { return (3, 4); }\nvar a, b = f();\nsyscall(60, a + b);\n' | build/cycc > /tmp/rp \
  && chmod +x /tmp/rp && /tmp/rp; echo $?                                                                          # 7
```

The full set, probed one annotation at a time (`fn f(): <T> { .. }`, the tree, x86_64):

- **Accepted**: any struct (`P`, a generic instance `Box<Pt>`, `Str` with `lib/str.cyr` included), `i8` / `i16` /
  `i32` / `i64`, `f64`, `bool`, the twelve vector types, `Result` / `Option` / `Tagged`, `cstring`, `*T`,
  `(T1, T2)` / `(T1, T2, T3)`, `dyn Tr`, and a type parameter of the fn.
- **Refused by this message**: `u8` / `u16` / `u32` / `u64`, `f32`, an enum.
- **Refused by its own message**: a slice (`a slice cannot be a return type`); an unknown name
  (`unknown type 'X' as a fn return type`, as is `Str` without its include); `u128` (`expected identifier, got
  reserved keyword 'u128'`, tracked in `2026-10-08-u128-params-returns-fields-captures.md`).

## Root cause

`_tn_ret_report` (`src/frontend/parse_types.cyr:3036`) prints a fixed note string. The note was written at 6.6.16
from `_classify_return_type` (`src/frontend/parse_fn.cyr:11787`). The other accepted forms are taken before that
classifier is asked:

- the multi-value form (`_parse_multiret_sig`, the `PEEKT == 10` arm of PARSE_FN_DEF's return parse,
  `parse_fn.cyr:15158`);
- `*T` (`_ret_ann_alt`, `parse_fn.cyr:10000`);
- `bool` (`_bx_ret_or_refuse`, `src/frontend/parse_expr.cyr:1604`);
- a type parameter (`_is_tparam_of` / `_gtype_tp_ret`).

`dyn Tr` reaches the classifier as a struct: `_dyn_fold` makes `dyn X` one identifier and `_dyn_prepass` registers
its struct. So the note's "a struct" covers it by implementation only, and a reader cannot tell. Only `*T` was ever
added back to the note.

## Proposed fix

Make the note the guide's list: "a return type is a struct, i8/i16/i32/i64, f64, bool, a vector type, Result, Option,
Tagged, cstring, a pointer *T, a multi-value (T1, T2[, T3]) or dyn Trait; return an i64 (no annotation) for the
others". Optionally name the refused type's nearest accepted one (`u8`..`u64` → `i64`; `f32` → `f64`). One row in
`tests/gates/diagnostics/type_name_refused.sh` (`ret_known`) pins the note text with `bool`, `(T1, T2` and `dyn` in
it, mutation-proven (the old string → RED). It is a message change only: no compiled program changes, and the
self-host output changes only by the string.

## Consumer-side workaround

None needed. `bool`, `(T1, T2)`, `dyn Tr` and a generic's `T` are accepted return types whatever the note says.
