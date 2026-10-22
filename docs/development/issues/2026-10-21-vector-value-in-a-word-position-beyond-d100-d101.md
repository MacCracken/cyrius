# A vector value in a word position beyond D100 / D101: a store through a `*V` writes one word, a vector LOCAL read as a word is its lane 0, and a multi-value fn's vector element is read as one word — OPEN

**Status:** 🟡 **OPEN** — D100 / D101 refuse a vector CALL in these places; the vector LOCAL, the store through a `*V`
and a multi-value element are in no decision, and each fix changes what compiles or computes; the s16 lane stopped on
them.
**Placement:** 6.7.17 — the cleanup of the remaining issues (valc lane, wave 1, unit VC1; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D23 — The whole vector.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D24 — Refuse them.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D25 — Refuse it at the element.
**Discovered:** the s16 lane — unit SZ6 (rows 1, 2; its Blocked list), its fix step (row 3; "not fixed").
**Severity:** Medium — rows 1 and 3 compute a wrong value with no diagnostic (row 1 differs by target); row 2 is the
same lane-0 value on every target.
**Kind:** decision.

## Summary

6.7.16's D100 ("refuse it, wherever it sits in the source") and D101 refuse a whole vector CALL used as an operand, a
scalar return or a word argument. A vector VALUE that is not a call meets the same slots unjudged: stored through a
`*f64v2` it writes one word, read as a word it is its first lane, and as a declared multi-value element it is returned
as one word.

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B) on x86_64,
aarch64 (qemu-aarch64), cx (cxvm) and PE (wine 11.20), each compiler built from that tree; every program compiles rc 0
with no diagnostic. Common head:

```cyrius
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn rd(p): i64 { return load64(p) * 10 + load64(p + 8); }
fn take(t): i64 { return t; }
```

**1. A store through a `*V`:**

| body of `fn r(): i64 { var w: f64v2 = mk2(1, 2); … return rd(&w); }` | x86_64 | aarch64 | cx | PE |
|---|---|---|---|---|
| `var u: f64v2 = mk2(4, 7); var pv: *f64v2 = &w; *pv = u;` | 42 | 42 | 42 | 42 |
| `var pv: *f64v2 = &w; *pv = mk2(4, 7);` | 2 | 2 | 42 | 42 |
| `*(&w) = mk2(4, 7);` | 2 | 2 | 42 | 42 |
| control: `var u: f64v2 = mk2(4, 7); w = u;` | 47 | 47 | 47 | 47 |

The local is copied lane 0 only (42 = 4·10 + 2); the call's result register is stored (x86_64 / aarch64 2, cx / PE 42).

**2. A vector local read as a word** (`var w: f64v2 = mk2(4, 7);`):

| use | all four targets |
|---|---|
| `return take(w);` | 4 |
| `return w;` from `: i64` | 4 |
| `var x: i64 = w; return x;` | 4 |
| `return 1 + w;` | 5 |
| `if (w) { return 4; } return 9;` | 4 |

The call in the same slot is refused (D101): `return take(mk2(4, 7));` gives "a vector value cannot be passed to an
integer parameter - 'mk2' returns a vector, passed to parameter 't' of 'take'".

**3. A multi-value fn's declared vector element:**

```cyrius
fn two(): (f64v2, i64) { var v = mk2(41, 7); return (v, 3); }
fn r(): i64 { var a, b = two(); return a + b; }
syscall(60, r());
```

Exit **44** on all four (a = 41, lane 0). A tuple TYPE refuses the element (`var t: (f64v2, i64) = ..` gives "a tuple
element is i64, f64 or bool, not 'f64v2'"); 6.7.16's D90 refuses a struct over 8 B as a `return ( .. )` element; a vector
CALL as the element is refused since the s16 review's fa3418db3 (D100). (A struct ELEMENT TYPE in the declaration, `fn
two(): (P, i64)`, keeps compiling by D90's text.)

## The decision, row by row

| row | refuse | or define / keep |
|---|---|---|
| 1 | refuse a vector store through a `*V` and `*(&w)` | copy the vector, as a store through a `*S` copies the struct (6.7.11) — `*pv = u` gives 47, `*pv = mk2(4, 7)` 47 |
| 2 | refuse the local in each word slot, in D100 / D101's words | keep lane 0 (the same on every target today) |
| 3 | refuse a vector element at the `return ( .. )`, D90's shape (or at the declaration) | keep (lane 0) |

## Acceptance

Each repro gives the decided result on x86_64, aarch64, cx and PE (row 1 the same value on every target); the vector
receives 6.7.11 – 6.7.16 decided (a vector local from a vector, `w = u`, a `*V` parameter, a value-form argument)
unchanged.
