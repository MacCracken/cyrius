# A field access in a const fn, or on a const, is refused with a message that names the wrong thing — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with the tree's `build/cycc`: a field store
in a const fn body says `expected ';', got '.'`; a field read there says the same and cascades a second error; `C.x = 1`
on a top-level const says `no struct type in scope for 'C'`; on a LOCAL const it prints two errors, `undefined variable
'L'` and `no struct type in scope for 'L'`. `C = 1` / `L = 1` already say `cannot assign to const` correctly.
**Placement:** 6.7.12 — Break 2, repair 3 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.7.5 planning (roadmap commit 68de8001, 2026-10-08); filed 2026-10-08 from roadmap.md.
**Severity:** Low — every case is refused; only the message is wrong.
**Affects:** cycc 6.7.2 – 6.7.6 (`const` / `const fn` arrived in 6.7.2).

## Summary

Four spellings, one class — the refusal is right, the reason given is not:

1. **Field store in a const fn** — `a.x = n;` → `expected ';', got '.'`. The guide's pure subset excludes fields
   ("Not: memory (`load64`, arrays, `&x`, fields)"); the message should say that.
2. **Field read in a const fn** — `var b = a.x;` → `expected ';', got '.'` **plus** `no struct type in scope for 'a';
   a '.field' access needs its struct declaration (missing include?)` from the runtime compile of the same body.
3. **`.field` store / read on a top-level const** — `C.x = 1;` → `no struct type in scope for 'C'; a '.field'
   assignment needs its struct declaration (missing include?)`; `var v = C.x;` → the `access` form. Blames a missing
   include; a const has no storage and no fields.
4. **`.field` store on a local const** — `const L = 5; L.x = 1;` → `undefined variable 'L'` AND `no struct type in scope
   for 'L'` — two errors, both false (`L` is in scope).

## Reproduction

```cyr
# 1 / 2 — const fn body
const fn f(n) {
    var a = n;
    a.x = n;          # 1: expected ';', got '.'
    var b = a.x;      # 2: expected ';', got '.'  + no struct type in scope for 'a'
    return b;
}
```

```cyr
# 3 / 4 — const receivers
struct P { x; y; }
const C = 5;
fn main() {
    C.x = 1;          # 3: no struct type in scope for 'C'; a '.field' assignment needs ...
    var v = C.x;      # 3: no struct type in scope for 'C'; a '.field' access needs ...
    const L = 5;
    L.x = 1;          # 4: undefined variable 'L'  +  no struct type in scope for 'L'
    return v;
}
var r = main();
```

`build/cycc < f.cyr > /dev/null` (one case per file to see each first error). Expected: one error each, naming the
rule — e.g. `a field is not in a const fn: its body takes no memory (fields, arrays, load64, &x)` and `cannot assign to
a field of const 'C' - a const has no storage`.

## Root cause

- 1 / 2: the const-fn checker's statement arm (`_ce_stmt`, `src/frontend/parse_fn.cyr:6380–6388`) takes an IDENT
  followed by anything but `=` / `OP=` as an expression statement; `_ce_atom` (parse_fn.cyr:5881, the frame-local
  lookup ~6124) returns the local's value without looking at a following `.`, so `_ce_expect(S, 5)` reports the `.`.
  For 2 the runtime compile of the same body then reports the field access too (the const fn is also an ordinary fn).
- 3: `PARSE_FIELD_STORE` (`src/frontend/parse_decl.cyr:1843–1873`) resolves `C` through `FINDVAR`, gets no struct id,
  and reports `ERR_IDENT(... "no struct type in scope for " ...)` (parse_decl.cyr:1872); the read side does the same at
  parse_decl.cyr:1669. Neither consults `_cst_named` (the check `_cst_lvalue_check`, parse_fn.cyr:7157, makes for `C =`).
- 4: a local const has no var slot, so `FINDVAR` misses and the undefined-variable arm (parse_decl.cyr:1851) fires,
  and then the `sid == 0` arm fires as well.

## Proposed fix

Diagnostic only — nothing that compiles today changes. (a) In `_ce_stmt`'s ident arm and `_ce_atom`, a `.` after the
name → `_ce_bad("a field is not in a const fn: ...")`, and stop the runtime body from repeating it (see the duplicate-
report item in `2026-10-08-diagnostic-cascades-and-locationless-eof-errors.md`). (b) In `PARSE_FIELD_STORE` and the
read path, check `_cst_named(S, noff)` before the undefined-variable / no-struct arms and report `cannot assign to a
field of const 'C'` / `const 'C' has no fields - a const has no storage`; one error per site.
