# `Str` shapes beyond D19 / D20 / D71 / D73: a struct result assigned into a `Str` handle (SIGSEGV), a nested literal's `*Str`-sourced leaf, a captured inline `Str`'s `*(&t) = v`, a `Str` field's named init, and a top-level untyped `str_from` — RESOLVED

> ✅ **RESOLVED in v6.7.17** (valb lane, unit VB1, `7ac6f02ff` + `9d0149083` + `03082b20a` (D18), `9312d6d24` (D19), `e29376442` (D20), `bff68bf08` (D21), `3de26d3e3` (D22), met `818d8e92c`, `f040edb38`, `749c65517`, `88f4f3997`, `4cedbfaa1`, `025ad6a12`; the finish pass's D98 `6b37cde17`, D99 `4196cc4c1`, met `21b18dff9`): a struct value of another type into a `Str` handle or slot is refused by name (D18); `O { *p, 1, 2 }` stores p, the header's address (D19); `*(&t) = v` copies into a closure's copy of t (D20); a struct literal's named `Str` field compiles (D21); an untyped top-level declaration from a whole call returning `Str` is a `Str` handle global (D22); a `Str` name as a nested literal's first leaf stores the header (D98), and a multi-value call into a `Str` slot is refused (D99). Rows: inline_str_value.sh SH / SP / NS / CA / NM / ZS / ND rows and tests/tcyr/crossos/inline_str_value.tcyr, struct_copy_type_checked.sh NW1-NW6, struct_literal_type_refused.sh R13 / R13b / A5. CHANGELOG [6.7.17])

**Status:** ✅ **RESOLVED in v6.7.17** (see the banner). Was: 🟡 **OPEN** — each fix changes what compiles or computes beyond the decided answers; the f16 and s16 lanes
stopped on them.
**Placement:** 6.7.17 — the cleanup of the remaining issues (valb lane, wave 1, unit VB1; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D18 — Refuse it.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D19 — p (the header's address).
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D20 — Copy into the closure's copy of t.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D21 — Accept it.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D22 — Type it Str.
**Discovered:** the f16 lane, unit FF4 (row 1; the f16 review's file_as_issue, staged as
2026-10-21-struct-result-assigned-into-str-handle-local-sigsegv.md); the s16 lane, unit SS2 (rows 2 – 5).
**Severity:** Medium — row 1 compiles silently and crashes; rows 2 and 3 store a value other than their decided
siblings'; rows 4 and 5 refuse spellings their siblings accept.
**Kind:** decision (one per row).

## Summary

A `Str` variable holds the address of a 16-byte `{ data; len; }` header, and 6.7.13 – 6.7.16 decided what each `Str`
position takes (the guide's *An inline `Str` passes its header*). Five positions are in no decision: a struct result of
another type into a `Str` HANDLE by assignment (the aggregate operand check excludes `Str` by name), a NESTED literal's
`Str` leaf from `*p`, a CAPTURED inline `Str` as `*(&t)`'s destination, the NAMED initialiser of a `Str` field, and a
top-level untyped declaration from a free `: Str` call.

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B) on x86_64,
and where shown on aarch64 (qemu-aarch64), cx (cxvm) and PE (wine 11.20), each compiler built from that tree.

**1. A struct result assigned into a `Str` handle local:**

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct Q1 { a; }
fn mkq(): Q1 { var q: Q1; q.a = 5; return q; }
fn main(): i64 { alloc_init(); var h: Str = str_from("x"); h = mkq(); return str_len(h); }
syscall(60, main());
```

rc 0, no diagnostic; x86_64 139 (SIGSEGV), aarch64 SIGSEGV, cx 252 (a read through 5), PE an access violation (exit 5):
h takes Q1's word (5). The declaration `var h: Str = mkq();` is refused ("fn return struct-id differs from declared var
type"), and so is the same assignment into a `P` handle: `var h: P = alloc(16); h = mkq();` gives "cannot copy 'mkq'
into a variable of a different struct/vector type: 'h'". `Str` (with Result / Option / Tagged) is excluded from the
aggregate operand check by name (6.6.16's C2).

**2. A nested struct literal's `Str` leaf from `*p` takes the header's data word:**

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct WS { s: Str; n; }
struct O { v: WS; m; }
fn main(): i64 { alloc_init(); var a = str_from("abcdefg"); var p: *Str = a; var o = O { *p, 1, 2 }; if (o.v.s == a) { return 10; } if (o.v.s == load64(a)) { return 50; } return 99; }
syscall(60, main());
```

Exit **50** on all four: o.v.s holds `load64(a)`, the header's first word. The direct literal `WS { *p, 1 }` stores p
(exit 10 with the same tests; 6.7.16's SS-8, D20 carried to a literal's `Str` field); `O { a, 1, 2 }` is refused
("cannot copy 'a' into a struct field of a different struct type: 'v'").

**3. `*(&t) = v` with t a closure's captured inline `Str`:**

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/fnptr.cyr"
fn main(): i64 { alloc_init(); var t: Str = Str { "abcdefg", 7 }; var v = str_from("xy"); var f = |k| { *(&t) = v; return t.len + k; }; return fncall1(f, 0); }
syscall(60, main());
```

Exit **7** on all four: v's word is written into the capture's data word and t.len stays 7. In a fn, `*(&t) = v` copies
the header (exit 2; 6.7.16's SS-13, D71's "t itself" carried to the store); in the closure `t = v` is refused ("'t' is
captured by value; a captured name is not assignable in a closure — copy it into a local (`var t_l = t;`)"), and a
captured STRUCT's `*(&s) = v` copies into the capture's copy (exit 78 for `S { 1, 2 }` ← `S { 7, 8 }`; 6.7.13).

**4. A `Str` field's named initialiser:**

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct V { s: Str; n; }
fn main(): i64 { alloc_init(); var a = str_from("abc"); var v = V { s: a, n: 1 }; return str_len(v.s) + v.n; }
syscall(60, main());
```

```
error:<source>:4:72: named init not supported for nested struct fields — use positional
```

The positional `V { a, 1 }` compiles and exits 4: a `Str` field is a one-word handle, not a nested struct.

**5. A top-level untyped declaration from `str_from`:**

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
alloc_init();
var bb = str_from("xyz");
syscall(60, bb.len);
```

```
error:<source>:5:19: no struct type in scope for 'bb'; a '.field' access needs its struct declaration (missing include?)
```

The same on all four, and in the declaration zone (`var bb = str_from("xyz");` above a fn reading `bb.len`: 4:31, the
same words). In a fn, `var bb = str_from("xyz"); return bb.len;` types bb `Str` and exits 3. (6.7.16's ST-5 types a
fn's untyped `var k = h.clone();` and leaves top level unchanged; the zone lane's ZN-10 routes an untyped `Str` global's
overloads by its initialising call, which is not a `.field` type.)

## The decision, row by row

| row | refuse / change | or keep |
|---|---|---|
| 1 | refuse `h = mkq();` (a struct result of another type into a `Str` handle) with the declaration's words | keep the word (today: the crash) |
| 2 | the nested leaf takes p, as the direct literal's field does (SS-8) | keep the data word (today) |
| 3 | follow 6.7.13's captured-struct precedent: copy the header into the capture's copy | refuse it as `t = v` is refused there; or keep the one-word write (today) |
| 4 | accept the named form (`V { s: a, n: 1 }` compiles, as the positional one does) | keep the refusal (today) |
| 5 | type it `Str` at top level, in the zone and after the first statement (`bb.len` compiles) | keep untyped (today) |

## Acceptance

Each repro gives the decided result on x86_64, aarch64, cx and PE; the decided `Str` positions (the guide's *An inline
`Str` passes its header* and *A dereference of an address-of is the struct it names*) unchanged.
