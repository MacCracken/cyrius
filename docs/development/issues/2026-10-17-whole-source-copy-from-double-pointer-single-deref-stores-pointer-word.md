# `l = *pp` / `G = *pp` / `*q = *pp` (pp a `**S`) store the pointer word where `l = p` copies the struct, and `var t: S = *pp;` binds a handle where `var t: S = p;` copies — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 structs lane's review (unit S2,
issues/archived/2026-10-16-struct-double-pointer-dereference-is-no-struct-value.md, 7c96547f), measured on the lane's tree and
at the lane base f133fb2f (the same output on both): x86_64, aarch64 (qemu) and cx (cxvm) alike. Pre-existing.
**Placement:** 6.7.15 — repair 5 (structs lane; filed from the 6.7.14 structs review, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Medium — silent: the destination's first field takes the pointer `*pp` holds, the rest is left stale; a
declaration aliases the struct where its `*S`-name twin copies. No diagnostic. Not a security id (the developer's own
source).
**Kind:** bug — 6.7.13's D9 (a) made `*pp` of a `pp: **S` a `*S`, and 6.7.11 copies the struct a `*S` source points at
into a struct destination (`l = p`, `G = p`, `*q = p`, `var t: S = p;`). 7c96547f taught the typed-pointer reader
(`_hl_psid`) to read `*pp` as that `*S`, so `return *pp;`, `l = *pp + 0` and `bs(*pp)` see the struct; the WHOLE-source
copy arms do not consult it.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
struct P { x; y; }
var G = P { 0, 0 };
fn bs(v: P): i64 { return v.y; }
fn main(): i64 {
    var s = P { 3, 4 };
    var p: *P = &s;
    var pp: **P = &p;
    var d = P { 0, 0 };
    var q: *P = &d;
    G = *pp;
    *q = *pp;
    var a = bs(*pp);
    fmt_int(G.y); fmt_int(d.y); fmt_int(a);
    return 0;
}
syscall(60, main());
```

```
$ build/cycc < i6p.cyr > i6p && ./i6p
004         # G.y 0, d.y 0 (the pointer went into .x); `G = p; *q = p;` prints 444
```

Locals and declarations:

```cyrius
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
struct P { x; y; }
fn main(): i64 {
    var s = P { 3, 4 };
    var p: *P = &s;
    var pp: **P = &p;
    var l1 = P { 0, 0 };
    var l2 = P { 0, 0 };
    l1 = p;
    l2 = *pp;
    var t3: P = (*pp);
    var q: *P = *pp;
    var t4: P = q;
    s.y = 9;
    fmt_int(l1.y); fmt_int(l2.y); fmt_int(t3.y); fmt_int(t4.y);
    return 0;
}
syscall(60, main());
```

```
$ build/cycc < i6n.cyr > i6n && ./i6n
4094        # l1 = p copies (4); l2 = *pp left l2.y 0; t3 aliases s (9 after s.y = 9); t4 = q copies (4)
```

| statement (16 B `P`; the 8 B `struct P { x; }` twin alike) | lane / f133fb2f | `*S`-name twin |
| --- | --- | --- |
| `l = *pp;` | l.x = &s, l.y stale | `l = p;` copies |
| `G = *pp;` (G a `P` global) | G.x = &s, G.y stale | `G = p;` copies |
| `*q = *pp;` (q: `*P`) | d.x = &s, d.y stale | `*q = p;` copies |
| `var t: P = *pp;` / `var t: P = (*pp);` | t a handle on s (reads 9 after `s.y = 9`) | `var t: P = p;` copies (4) |
| control `l = *pp + 0;`, `return *pp;` from a `: P` fn, `bs(*pp)` | copy / the struct (since 7c96547f; `bs(*pp)` before too) | — |

aarch64 (qemu) and cx (cxvm) print the same 004 / 4094.

## Root cause

The whole-source copy arms key on the source's shape, not on its type. `_asg_dstar` (src/frontend/parse.cyr) and the
declaration's `_hl_dstar_t` (src/frontend/parse_decl.cyr) copy a source `* E` only when E's POINTEE is a struct
(`_hl_dpsid(E)` > 0) — right for `*p`, but `*pp`'s operand `pp` is a `**S`, whose pointee is the pointer `*S`, so they
answer 0. The `*S`-source copy (`l = p`, `G = p`, `*q = p`, `var t: S = p;`) runs on a NAME operand (`_agc_operand`),
and `*pp` is no name. So the source falls to the plain expression: the word `*pp` reads is stored into the
destination's first field, and the declaration binds `t` as a handle to it. The operand reader that knows `*pp` is a
`*S` (`_hl_psid` → `_hl_dref_psid`, 7c96547f) is consulted only where an operand is typed (an operator, a by-value
argument, a `return`).

## Fix direction

Where a whole source is a dereference `* E` whose `_hl_psid` answers a struct S through a `**S` operand (E's pin names
`*S`), copy the struct E's word points at — the `*S`-name twin's copy (6.7.11) — into a local, a global, the pointee of
a `*S` / handle, and in a declaration. Rows beside double_pointer_struct_value.tcyr's `return *pp` / `l = *pp + 0` rows
(both sizes, top level, a for step), and the guide's `**pp` paragraph loses its "Not yet" sentence.
