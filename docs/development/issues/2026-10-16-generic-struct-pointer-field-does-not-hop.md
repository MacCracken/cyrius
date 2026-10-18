# A generic struct's `*T` field does not hop in its instance: `b.p.y` with `b: Pb<Pt>` (`struct Pb<T> { p: *T; n; }`) is "expected ';', got '.'" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.14 generics lane (unit G4) on the slot-open compiler (2600f67f's
build/cycc) and on the lane's tree: identical.
**Placement:** 6.7.15 — repair 5 (generics lane, wave 1, unit G2; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Discovered:** 2026-10-16, 6.7.14 generics G4, probing the edges of the bounded-carrier-field bite (a carrier
`b: Pb<T>` whose field is `p: *T`).
**Severity:** Low — a loud refusal of valid source; workaround: bind the field to a `*Pt` local first
(`var t: *Pt = b.p; return t.y;` exits 9).
**Affects:** every cycc with generic structs and 6.6.17's pointer-field hop (not bisected); every target (frontend).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Pb<T> { p: *T; n; }
fn go(): i64 { var q: Pt; q.x = 1; q.y = 9; var b: Pb<Pt>; b.p = &q; b.n = 1; return b.p.y; }
syscall(60, go());
```

```
actual:   error:<source>:4:89: expected ';', got '.'
expected: exit 9 — as the non-generic `struct Pb { p: *Pt; n; }` gives (6.6.17: "a field chain through a pointer field")
```

Controls (both exit 9): the non-generic `struct Pb { p: *Pt; n; }` with the same `b.p.y`; the generic one through a
local, `var t: *Pt = b.p; return t.y;`. Inside a generic (`fn g<T>(b: Pb<T>): i64 { return b.p.y; }`, `g<Pt>(b)`) the
same "expected ';', got '.'".

## Root cause (not traced to the line)

6.6.17's hop (`_fld_hop_sid` -> `_fld_ptr_sid`, src/frontend/parse_decl.cyr) continues a chain through a field whose
recorded pointee is a struct. A generic struct instance's `p: *T` field (minted as `Pb$Pt`) apparently records no
pointee struct for the instance, so the chain stops after `b.p` and the `.y` is left to the statement.

## Fix direction

Record the pointee for an instance's `*T` field when T binds a struct (as the non-generic `*Pt` field records it), so
`b.p.y`, `b.p.y = 3` and `b.p.m()` hop. Rows: the repro (9) on every target; a store; a method; inside a generic.
