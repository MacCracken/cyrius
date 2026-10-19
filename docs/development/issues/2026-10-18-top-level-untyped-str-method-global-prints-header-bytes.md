# A top-level untyped `var s = BB.mks();` with a `: Str` METHOD is not routed as a Str: `println(s)` prints the header's bytes — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 receives lane (c44fab9c2, which made a WRAPPED
free `: Str` call's global route as a Str); measured on the lane after its review fixes (l6715-receives, x86_64,
the aarch64 cross compiler under qemu-aarch64, the cx compiler under cxvm) and on the lane base 4862a462e
(x86_64): the same. Pre-existing.
**Placement:** 6.7.16 — Break 2, repair 6 (zone lane, wave 2, unit Z3; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Medium — compiles clean and prints wrong bytes (exit 0); nothing tells the developer.
**Kind:** bug (overload routing of an untyped global's value).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/io.cyr"
struct B { a; }
impl B { fn mks(self): Str { return str_from("abcde"); } }
var BB = B { 1 };
var s = BB.mks();
println(s);
```

```
$ build/cycc < s1.cyr > s1 && ./s1 | od -An -c
 214 016   `  \n            (x86_64; exit 0 — the Str header's bytes, not "abcde")
 < 016   `  \n               (aarch64, qemu-aarch64)
 i 270 002                  (cx, cxvm)
```

The same after a first statement (`alloc_init();` before `var BB`). The review measured PE (wine) printing garbage
bytes too. Controls, each prints `abcde`: the free call `var s = mks2();` (`fn mks2(): Str`), and the annotation
`var s: Str = BB.mks();`.

Related, not this filing: in a fn, `var s = b.mks(); println(s);` prints garbage the same way (x86_64 `| 016 \``) —
the untyped-local case of issues/2026-10-18-untyped-declaration-from-str-method-result-not-typed-str.md (filed by the
structs lane: `k.len()` refused there), whose fix should cover the `println` routing too.

## Root cause

An untyped `Str` global is routed by the one call that initialised it: GVDSID records the callee of a whole free
call, read by `_gv_rhs_call_sid` (src/frontend/parse_fn.cyr), which wants `IDENT (` (inside any wrap, since
c44fab9c2). A method `BB.mks()` is `IDENT . IDENT (`, so nothing is recorded and `println(s)` takes the cstring base
of the overload, printing the Str header's bytes. The guide's 6.7.15 wording — "routes an untyped `Str` global by
the one call that initialised it, wrapped or not" — reads as if it covered this shape.

## Fix direction

Record the method's `: Str` return for a whole method initialiser (and a chain ending in one), as the free call's
callee is recorded; rows on x86_64 / aarch64 / cx / PE, the zone and after a first statement; the guide sentence names
methods once they route.
