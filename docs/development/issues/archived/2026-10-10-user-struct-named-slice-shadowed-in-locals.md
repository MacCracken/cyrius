# A program's own `struct slice` is used by a parameter / pointer but not by a fn-local `var x: slice` — RESOLVED

> ✅ **RESOLVED in v6.7.11** (GF-8: a declared `struct slice` (or `struct slice<T>`) is what a fn-local `slice` / `slice<T>` annotation names too; the built-in stays reachable as `[T]` — the user's decision (b), D10, 2026-10-13. The filed repro builds on every fork; its `var x: slice = 0;` on the 24-byte struct is a NULL handle under 6.7.10's handle line, so it faults (139 on x86_64 / aarch64) exactly as the same program with the struct renamed does — the expected 14 is what `var x: slice;` gives, and that row is pinned. The flip side, pinned by GF-8r (review fix): with a `struct slice` declared, a fn-local `slice<u8>` used as the built-in (`s.len`) stops compiling; respell it `[u8]`. Rows: `frontend/slice_position_refused.sh` K2b-K2g, `crossos/user_struct_named_slice.tcyr` (every fork). CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) with its
`build/cycc`: with `struct slice { a; b; c; }`, `fn f(s: *slice)` reads the user's 24-byte struct, but
`var x: slice = 0;` in a fn is not that struct — `x.a = 5;` is refused "no struct type in scope for 'x'"; with a
generic `struct slice<T>`, `var x: slice<i64> = 0;` is the built-in 16-byte slice ("slice has only .ptr and .len
fields"), and without `= 0` either form is "uninitialized variable not allowed". The repro is refused the same way
by the installed 6.6.10, 6.6.20, 6.7.0, 6.7.3, 6.7.5, 6.7.6 and 6.7.7 compilers.
**Placement:** 6.7.11 — repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-10 — never 7.x (the fix
is the user's call, asked at that release's open: either `slice` becomes a reserved type name and `struct slice` is
refused by name — a program that compiles today stops — or a declared `struct slice` wins in a local annotation too).
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, bite C2-6a (the slice-position refusals leave a user's
`struct slice` alone — gate row K2 in `tests/gates/frontend/slice_position_refused.sh`).
**Severity:** Low — loud: the local is refused or mistyped with an error; no silent wrong value was found.
**Affects:** cycc 6.6.10 – 6.7.8 (every target)

## Summary

`slice` is not a reserved word: a program may declare `struct slice`, and a parameter (`s: slice`, `p: *slice`), a
pointer target and `sizeof(slice)` resolve it as the program's struct (6.7.8 keeps that working, row K2). A fn-local
annotation does not: PARSE_VAR tests the annotation's word against `slice` (the built-in `slice<T>` ident spelling)
BEFORE it looks up structs, so `var x: slice<..>` — and a bare `var x: slice`, as a slot with no element type — is
always the built-in 16-byte {ptr, len} slot: one name means two types depending on where it is written.

## Reproduction

`docs/development/issues/repros/2026-10-10-user-struct-named-slice-shadowed-in-locals.cyr`:

```cyrius
include "lib/syscalls.cyr"
struct slice { a; b; c; }
fn f(s: *slice): i64 { return s.c; }     # the user's 24-byte struct
fn main(): i64 {
    var x: slice = 0;                    # the BUILT-IN 16-byte slice local, not the user's struct
    x.a = 5;                             # refused: "no struct type in scope for 'x'"
    var B: i64[3];
    store64(&B + 16, 9);
    return f(&B) + x.a;                  # want 14 (9 + 5), with `x` the user's struct
}
var rc = main();
syscall(60, rc);
```

```
actual:   error:<source>:7:9: no struct type in scope for 'x'; a '.field' assignment needs its struct declaration
          (and the same at 10:23)
expected: either `struct slice` refused by name at its declaration ("`slice` is a built-in type"), or the program
          builds and exits 14
```

## Root cause

PARSE_VAR's annotation ladder (`src/frontend/parse_decl.cyr`, the arm at `:6189` that compares the word against
`"slice\0"` — `0x006563696C73` — and consumes it, `:6197`) runs before the struct lookup in the `else` arm that
follows (`_tn_head` / `_tn_var_ann`). The parameter and pointer-target paths resolve the name through the struct
table first.

## Proposed fix

The user's call between: (a) reserve `slice` as a type name — refuse `struct slice` / `enum slice` / `union slice`
by name at the declaration, which also removes the ambiguity in parameters (a program that compiles today, like K2's
fixture, stops); or (b) make PARSE_VAR consult the struct table before the built-in word, so a declared
`struct slice` wins everywhere and the built-in stays reachable as `[T]`. Rows either way: K2 updated; a local, a
field and a global of the user's type; `[u8]` locals unchanged.

## Consumer-side workaround

Do not name a struct `slice`.
