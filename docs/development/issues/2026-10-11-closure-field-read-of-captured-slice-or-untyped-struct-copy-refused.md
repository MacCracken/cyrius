# Inside a closure, `s.len` of a captured slice and `q.y` of a captured untyped struct copy (`var q = p;`) are refused as "undefined variable" — OPEN

> ⚠ **HALF RESOLVED in v6.7.11 — half 1 only** (GF-15: inside a closure, `s.len` / `s.ptr` of a captured slice read the captured copy, the user's decision (a), D13, 2026-10-13. Repro 1 exits 8 (it was `undefined variable 's'`) on x86_64, qemu-aarch64 and cxvm, and the `async fn` form across an await on x86_64 (aarch64 and cx refuse a mid-body await by name); any other field is refused as on a local, and a store into the copy is refused by name. Rows: `frontend/closure_captured_slice_fields.sh`, `crossos/closure_captured_slice_fields.tcyr`. **Half 2 is NOT resolved:** repro 2 (`var q = p;` untyped, then `q.y` in a closure, expected 45) is still refused `undefined variable 'q'` on the merged wave-2 tree (ac8fdac8); it was routed to the untyped-binding decision, whose fix covers method chains, if-expressions and wrapped results, not a name copy. CHANGELOG [6.7.11])

**Status:** 🟡 6.7.12 open (2026-10-15): PARTIAL — Repro 1 verbatim builds, exits 8 (half 1 is fixed, df77c157). Repro 2 verbatim: `error:<source>:10:21: undefined variable 'q'`. PREMISE WRONG: `var q = p; return q.y;` with no closure is refused too (`6:15: no struct type in scope for 'q'`) on build/cycc and on the installed 6.7.10, 6.7.9 and 6.6.0. Repro 2's own `q.y * 10` outside the closure is hidden by the cascade latch. Today `var q = p;` wit Was: 🟡 **OPEN** — reported by the 6.7.9 critical lane (bite 12, the coroutine closure capture) as two loud
refusals met in passing. Verified 2026-10-11 against the merged 6.7.9 tree (`build/cycc` @ 27220379, 2,057,736 B):
both repros are refused, `undefined variable 's'` / `undefined variable 'q'`, at the closure's use; the same reads
outside the closure compile, and a closure reading `p.y` of a captured TYPED struct local (`var p: P = …`) compiles
and runs (exit 5). The installed 6.6.0, 6.7.0 and 6.7.8 compilers refuse both the same way.
**Placement:** 6.7.12 — repair 2: the platform release (fixfirst lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D29 (fork) — (a) an untyped `var q = p;` is a typed copy.
beside [the declared-name pre-scan](archived/2026-10-11-closure-prescan-reads-declared-names-as-captures.md)) — placed
2026-10-11 — never 7.x.
**Discovered:** 2026-10-11 during 6.7.9 crit bite 12.
**Severity:** Low — a loud refusal of valid source, with a message that names the wrong thing (the name IS defined
and captured); no wrong value. Workaround below.
**Affects:** cycc 6.6.0 – 6.7.9 (measured), every target (frontend).

## Summary

A closure captures by value, and 6.7.9 made every captured struct, tuple, u128, array and slice arrive in field order
(`coroutine_midbody_suspend.sh` axis 11 reads a captured slice through `slice_len(&v)` / `slice_ptr(&v)`). Two field
reads on such captures do not compile inside the closure body:

1. **`s.len` (or `s.ptr`) of a captured slice** — `undefined variable 's'`. The guide refuses a captured slice's
   SUBSCRIPT by name ("pass `slice_ptr(&s)` / `slice_len(&s)`, or declare the slice in the closure", § Slices); its
   fields are not covered by that rule and get the generic "undefined" message.
2. **`q.y` of an untyped copy of a struct** (`var q = p;` with `p: P`) — `undefined variable 'q'`. Outside the closure
   `q.y` reads the copy; a `var q: P = p;` (typed) copy is the working spelling inside one.

## Reproduction

```cyrius
# 1 — a captured slice's field
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/slice.cyr"
fn main(): i64 {
    alloc_init();
    var buf[16];
    var s: [u8] = 0;
    slice_of(&s, &buf, 7);
    var c = |x| s.len + x;
    return fncall1(c, 1);
}
syscall(60, main());
# error:<source>:10:23: undefined variable 's'      expected: exit 8
```

```cyrius
# 2 — an untyped struct copy's field
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
struct P { x; y; }
fn main(): i64 {
    alloc_init();
    var p: P = P { 3, 4 };
    var q = p;
    var c = |k| q.y + k;
    return fncall1(c, 1) + q.y * 10;
}
syscall(60, main());
# error:<source>:9:21: undefined variable 'q'      expected: exit 45
```

## Root cause

Not traced. Speculation: the capture pre-scan / env layout records the capture's slot but not the slice type or the
struct type an UNTYPED `var q = p;` inferred (`_ti_inferred_sid`), so inside the body the `.field` arm finds no typed
local and falls through to the undefined-name path; a declared `var p: P` carries its type and works.

## Proposed fix

Carry the capture's type (the slice type; the inferred struct type of an untyped copy) into the closure's local table,
so `s.len` / `s.ptr` and `q.y` read the captured copy as they read the local outside. If the slice fields cannot be
carried in this release, refuse them BY NAME with the subscript's message (`slice_len(&s)` / `slice_ptr(&s)`), never as
"undefined variable". Rows on x86_64 and qemu-aarch64 (and cxvm): both repros; a coroutine (`async fn`) form across
an await; the typed-copy control unchanged.

## Consumer-side workaround

Read the field before the closure (`var n = s.len; |x| n + x`), use `slice_len(&s)` inside it, or declare the copy
with its type (`var q: P = p;`).
