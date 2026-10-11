# A name a closure body declares without a `var` right before it is taken as a capture of the enclosing local — OPEN

**Status:** 🟡 **OPEN**. Found 2026-10-11 while fixing
[`2026-10-09-closure-prescan-reads-field-names-as-captures.md`](2026-10-09-closure-prescan-reads-field-names-as-captures.md)
(6.7.9, the critical lane's bite 14). Reproduced on that lane's tip with the tree's compiler, and with the installed
6.6.0, 6.7.0 and 6.7.8 compilers. It was not fixed in that bite: the declared-name forms need their own scoping in the
pre-scan (a `for … in` variable's scope is the loop), and that is a separate class from field names.
**Placement:** unpinned. For the user to place in the 6.x-line backlog.
**Discovered:** 2026-10-11 during 6.7.9 crit bite 14 (the field-name exemptions), while probing which other non-reads
the pre-scan still captures.
**Severity:** Medium. Valid source is refused, and the workaround is to include `lib/alloc.cyr` or rename the enclosing
local. With lib/alloc.cyr the closure carries a needless heap env (one allocation per closure value, and a by-value
copy of the enclosing local). No wrong value was observed.
**Affects:** cycc 6.6.0 – 6.7.9 (measured 6.6.0, 6.7.0, 6.7.8 and the 6.7.9 crit tip).

## Summary

`_cl_prescan_body` (`src/frontend/parse_expr.cyr`) puts a name in the closure's shadow set (a body-local, not a
capture) only when the token right before it is `var`. Every other identifier goes to `_cl_prescan_ident`, which
captures it if it names an enclosing local. Three declaration forms put the declared name somewhere else:

1. **A `for … in` loop variable**: `i` in `for i in 0..4 { … }`, which follows `for`.
2. **A local const**: `k` in `const k = 3;`, which follows `const`.
3. **The second and later names of a multi-value `var`**: `b` in `var a, b = two();`, which follows `,`.

If the declared name matches an enclosing local, the closure captures that local even though it never reads it.

## Reproduction

`docs/development/issues/repros/2026-10-11-closure-prescan-reads-declared-names-as-captures.cyr`:

```cyrius
include "lib/fnptr.cyr"
fn two(): (i64, i64) { return (3, 4); }
fn fi(): i64 { var i = 3; var cl = |n| { var s = 0; for i in 0..4 { s = s + i + n; } return s; }; return fncall1(cl, 1); }
fn fc(): i64 { var k = 5; var cl = |n| { const k = 3; return k + n; }; return fncall1(cl, 1); }
fn fm(): i64 { var b = 5; var cl = |n| { var a, b = two(); return a + b + n; }; return fncall1(cl, 1); }
syscall(60, fi() + fc() + fm());
```

```sh
cat docs/development/issues/repros/2026-10-11-closure-prescan-reads-declared-names-as-captures.cyr | build/cycc > /tmp/dn \
  && chmod +x /tmp/dn && /tmp/dn; echo $?
# actual:   error:<source>:8:97: a capturing closure needs include "lib/alloc.cyr" for its heap env
#           error:<source>:9:70: (the same)
#           error:<source>:10:79: (the same)
# expected: compiles, exit 22 (10 + 4 + 8). That is what each closure gives with lib/alloc.cyr included
#           and alloc_init() called, and what the file gives with the enclosing locals renamed.
```

## Root cause

`_cl_prescan_body` sets `prev_var` only on a `var` token (`t == 3`), and only the identifier immediately after it is
`_cl_shadow_add`ed. `for IDENT in`, `const IDENT` and `, IDENT` inside a multi-value `var` declare a name that the
body then reads as its own local. The parser resolves those reads to the body's local (the values are right), but the
pre-scan has already counted the enclosing local of that name as a capture.

## Proposed fix

In `_cl_prescan_body`:

- After `const`, shadow the next identifier, as after `var`.
- In a `var` declaration, keep shadowing each `, IDENT` until the declaration's `=` or `;`.
- At `for IDENT in`, shadow `IDENT` for the loop only. Record `_cl_nshadow`, add the name, walk the iterable and
  the body (`_cl_prescan_nested`), then restore `_cl_nshadow`. A read of `i` after the loop is the enclosing `i` again.
  The variable is already visible in the iterable: in a plain fn, `for i in 0..i` reads the new `i`, so shadowing
  from the name onward matches the parser.

Check every other declaration form the closure body can hold, such as a `for (i, x) in` form if one exists, and a
destructure.

Gate: one row per form, compiled without lib/alloc.cyr, plus a control for each. The controls are a read of the
enclosing name after the `for … in` loop, and a const or var name used only as a value, and each must still capture.
Add a mutation per form.

## Consumer-side workaround

Include `lib/alloc.cyr` and call `alloc_init()`, which gives the right result at the cost of an env, or rename the
enclosing local.
