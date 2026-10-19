# A struct literal's elements need no comma: `P { 3 4 }` and `P { b: 1 a: 2 }` compile — RESOLVED

> ✅ **RESOLVED in v6.7.15** (FE-8, `e5a003c6f` — the user's decision D1 (a), 2026-10-18: refused by name. EMIT_STRUCT_FIELD_W (src/frontend/parse_decl.cyr), the one element store, ends in `_slit_sep`: a missing comma is one error at the second element, "expected ',' between struct literal elements". The filed repro (rc 0, exit 6) is now `3:22` and `4:19`, one per literal; positional and named, in a fn, after the first statement, in the declaration zone (a `kernel;` build too), nested leaves, a generic `Box<i64> { 1 2 }`, a generic fn's body (once), `--syntax-only`. Literals with commas and a trailing comma `P { 1, 2, }` compile as before. The census found no commaless literal in the tree. Rows: `struct_literal_type_refused.sh` CM1 (the filed repro verbatim) – CM12, controls CT1 – CT4; mutations RED CM1 – CM12, CT4, and `tuple_checked.sh` (the `)` exception). Filed beside it (6.7.16): a commaless tuple literal `(1, 2 3)` now names the struct-literal rule (`2026-10-18-commaless-tuple-literal-named-as-struct-literal.md`); `enum E { A B }` compiles, D1's twin for enums (`2026-10-18-enum-members-need-no-separator.md`). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 frontend lane (l6714-frontend, unit F3), x86_64; the
same in a fn, after the first top-level statement and (since 6.7.14's named-literal fix) in the declaration zone.
**Placement:** 6.7.15 — repair 5 (frontend lane, wave 1, unit F2; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D1 — (a) Refused by name.
**Discovered:** 2026-10-16 by the 6.7.14 frontend lane, unit F3, comparing the zone's named literal with the fn-local
one (`issues/archived/2026-10-09-declaration-zone-named-struct-literal-refused.md`).
**Severity:** Low — accepted bad syntax; the values land where the comma-separated form puts them.
**Kind:** language (what a struct literal's grammar is — whether to refuse it is the user's call).

## Reproduction

```cyrius
struct P { a; b; }
fn f(): i64 {
    var p = P { b: 1 a: 2 };
    var q = P { 3 4 };
    return p.a + q.b;
}
syscall(60, f());
```
rc 0, no diagnostic; exits 6 (p.a = 2, q.b = 4) — as with the commas.

## Root cause

The element stores step over a `,` when one is there and never require it: EMIT_STRUCT_FIELD_W (src/frontend/
parse_decl.cyr) ends with `if (PEEKT(S) == 31) { STI(S, GTI(S) + 1); }`, and _STRUCT_INIT_BODY's named loop reads
the next `name :` wherever the cursor is.

## Fix

A decision first (it changes what compiles): refuse a missing comma between two elements by name ("expected ',' between
struct literal elements"), in both forms and every position (fn-local, top level, the declaration zone, nested), or
document the comma as optional in the guide's § Structs.
