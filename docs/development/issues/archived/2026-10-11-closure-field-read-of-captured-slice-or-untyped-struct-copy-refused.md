# Inside a closure, `s.len` of a captured slice and `q.y` of a captured untyped struct copy (`var q = p;`) are refused as "undefined variable" — RESOLVED

> ✅ **RESOLVED in v6.7.12** (half 2 — FX-5 and its lane-gate fix FX-8, the user's decision D29 (a), 2026-10-15: an untyped `var q = p;` is a typed copy; half 1 shipped in 6.7.11 (GF-15, 6.7.11's D13: a captured slice's `s.len` / `s.ptr`). With `p` an inline struct local, a by-value struct parameter (`self: T` too) or a closure's captured copy of one — by name or as `(p)` — `var q = p;` declares `q` a copy of `p`'s struct, as `var q: P = p;` does (`_uci_ps`, PARSE_VAR), so `q.y` reads and writes the copy in a fn and in a closure, `take(q)` passes the struct and `q + p` dispatches `P_add`. Repro 2 exits 45 on x86_64, IR=3, aarch64 (qemu), cx and PE (wine) — it was `undefined variable 'q'`. The premise was narrower than the defect: outside a closure `q.y` was refused too ("no struct type in scope for 'q'", 6.6.0 through 6.7.11) — `q` was `p`'s first word. A `*T` source, an untyped impl `self`, a handle and a struct global named in a fn stay words; an untyped global keeps the word; a bare `q` value (`return q;`, `raw(q)`) is still the first word. Rows: `frontend/closure_captured_slice_fields.sh` Q1-Q9, QK1-QK6, repro 2 verbatim, a new PE leg (mutations m1-m3 RED; 117 rows), `crossos/untyped_struct_name_copy.tcyr` (26 rows) on every leg and 293 / 293 crossos files on ecb, ach, cass and pi. The two name sources D29 did not name (a struct global in a fn, a handle) are filed: 2026-10-15-untyped-name-copy-of-struct-global-or-handle-keeps-word.md (6.7.13). CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 6.7.12 open (2026-10-15): PARTIAL — Repro 1 verbatim builds, exits 8 (half 1 is fixed, df77c157). Repro 2 verbatim: `error:<source>:10:21: undefined variable 'q'`. PREMISE WRONG: `var q = p; return q.y;` with no closure is refused too (`6:15: no struct type in scope for 'q'`) on build/cycc and on the installed 6.7.10, 6.7.9 and 6.6.0. Repro 2's own `q.y * 10` outside the closure is hidden by the cascade latch. Today `var q = p;` wit Was: 🟡 **OPEN** — reported by the 6.7.9 critical lane (bite 12, the coroutine closure capture) as two loud
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
