# A struct-typed FIELD destination from a `*S` global, a `: *S` call or a `*S` field (`o.s = GP`, `o.s = gp()`, `o.s = w.p`) stores the pointer's word at every size — RESOLVED

> ✅ **RESOLVED in v6.7.11** (ST-3: a struct-typed FIELD destination from a `*S` global, a `: *S` call or method, a `*S` field or pointer arithmetic copies the struct it points at — directly, through a `*O`, at top level and in a for step; a `*U` of another struct is refused by name (no decision needed: 6.7.10's decision 6, which the name destination already followed). The repro gives 58 on every row (it gave 100 / 100 / 100) on x86_64, aarch64, cx and PE. Rows: `crossos/struct_pointer_source_copy.tcyr` +13 (60, `small_struct_handle_line.sh` R9 on seven legs), `struct_copy_source_type_refused.sh` R24–R29, A6; `hidden_temp_census.sh` counts `_fsc_psrc`. A ZERO-size field from these sources still moves a word (pre-existing; not a shape the repro measured) — filed as issues/archived/2026-10-14-zero-size-struct-into-field-or-dereference-value-moves-a-word.md. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — verified 2026-10-13 against `build/cycc` 2,114,376 B (6.7.10, x86_64): each of the three
leaves `o.s.a == &GS` and `o.s.b` untouched, with no diagnostic, where `o.s = {5, 8}` is right; at 8 B (`struct S { a;
}`) `o.s = GP` stores `&GS` too. The same sources into a name destination copy since 6.7.10 ops-3 (`l = GP` gives
58), and a `*S` LOCAL into the field copies (`o.s = lp` gives 58).
**Placement:** 6.7.11 — repair 1, the struct operators / call arguments lanes (roadmap.md § 6.7.11) — placed
2026-10-13 — never 7.x.
**Discovered:** 2026-10-13, the 6.7.10 ops lane.
**Severity:** High — a silent wrong value (an address in a data field) on source that compiles clean.
**Affects:** the 6.7.10 tree (measured there only, x86_64); the field-store arms are frontend-only, so every target.

## Summary

6.7.10's decision 6 (completed by ops-3) makes a `*T` global, a `: *T` call or method and a `*T` field copy sources
at every size — for a name destination (local, global). The struct-typed field destination was not given the same
typing: only a `*T` local source copies into it.

## Reproduction

```sh
cd /home/macro/Repos/cyrius
H='struct S { a; b; }
struct O { s: S; }
struct W { p: *S; }
var GS = S { 5, 8 };
var GP: *S = 0;
fn gp(): *S { return GP; }'
B='GP = &GS; var w: W; w.p = GP; var lp: *S = GP; var o: O; o.s.a = 0; o.s.b = 0;'
R='return (o.s.a == &GS) * 100 + o.s.a * 10 * (o.s.a != &GS) + o.s.b; }'
row() { printf '%s\n%s\nsyscall(60, main());\n' "$H" "$2" > /tmp/fd.cyr
  build/cycc < /tmp/fd.cyr > /tmp/fd 2>/dev/null && chmod +x /tmp/fd && { /tmp/fd; echo "$1: exit $?"; }; }
row "o.s = GP     " "fn main(): i64 { $B o.s = GP; $R"
row "o.s = gp()   " "fn main(): i64 { $B o.s = gp(); $R"
row "o.s = w.p    " "fn main(): i64 { $B o.s = w.p; $R"
row "ctl o.s = lp " "fn main(): i64 { $B o.s = lp; $R"
row "ctl l = GP   " "fn main(): i64 { $B var l: S; l = GP; return (l.a == &GS) * 100 + l.a * 10 * (l.a != &GS) + l.b; }"
```

Actual: 100, 100, 100 (the field holds `&GS`), 58, 58. Expected: 58 on every row.

## Root cause

`_fsc_src` (`src/frontend/parse_decl.cyr:1151`) classifies a struct-typed field's source: `_fsc_name` (`:1066`, through
`_fsc_name_src` `:1052`) copies a struct-valued name or a `*T` local but answers 0 for a `*S` global; `_fsc_call`
(`:1079`) takes only a call whose `GFRS` is the field's struct (a `: *S` call is not); everything else goes to
`_fsc_expr` (`:1101`), which leaves the value in rax for the one-word store. None of them runs the 6.7.10 pointer-source
typing (`_hl_psrc`, used by `_hl_psrc_copy`, `src/frontend/parse.cyr:3022`), which only the name-destination arm
calls (`parse.cyr:3571`).

## Proposed fix

In `_fsc_src`, before `_fsc_call` / `_fsc_expr`: type the whole source with `_hl_psrc` / `_hl_psid`; when it is a `*T`
of the field's struct, evaluate it, park the pointer and copy `STRUCTSZ` bytes into the field (`_fsc_copy`'s
destination addressing), as `_hl_psrc_copy` does for a name; a `*U` of another struct refused by name (`_fsc_type_err`).
Pointer arithmetic (`o.s = GP + 0`) comes with it. Rows: the three shapes at 8, 16 and 24 B, the field reached
directly and through a `*O`, in `tests/tcyr/crossos/`, a mutant RED.

## Consumer-side workaround

Bind the pointer to a `*S` local first (`var lp: *S = GP; o.s = lp;`) or copy into a struct local (`var t: S = GP;
o.s = t;`) — 58 either way.
