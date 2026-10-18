# `**pp` through a `**S` is no struct value: `take(**pp)` into a by-value `S`, `var t: S = **pp;` fault, and `**pp` of a 3-byte struct reads 8 bytes — RESOLVED

> ✅ **RESOLVED in v6.7.14** (ST-7, `7c96547fd`; review fixes ST-7r, `17dee946b`, and ST-7r2, `ee3af1dc1` (guide only): `_hl_psid` reads `* E` with E a `**S` as a `*S` by its pin (`_hl_dref_psid` / `_hl_pw`), so `**pp` is the struct value `*p` is at every dereference consumer. No decision needed: 6.7.10's decision 6 with 6.7.13's D9 (a). Repro 1 stays 4 (6.7.13's VC-11). Repro 2 gives 4 on x86_64, aarch64, cx and PE (was 139 / 139 / 0 / 5). Repro 3 gives 11 on all four (was 10). The same holds through a parameter, field, global, capture, `: **S` call (generic too), `**(pp + n)` and `***ppp`; `**pp + a` dispatches, and `return **pp;` compiles over 8 B. By 6.7.11's D4 with D9 (a), `**pp = u` copies (56, was 54) and `**pp OP= v` is refused (was 134). By 6.7.13's D1 (a), a `{ **pp }` branch over 8 B is refused; of 8 B or less it copies. Rows: new `crossos/double_pointer_struct_value.tcyr` (31), 31 / 31 on ecb, ach, cass and pi; `small_struct_handle_line.sh` R16 and R16a - R16c (the three filed repros verbatim, every leg); `struct_copy_type_checked.sh` R27, R28, C5, C6, A14; mutations MP1 - MP4 RED. Not part of this file's `**pp` surface, filed by the review (6.7.15): a whole-source copy from `*pp` (`l = *pp`, `var t: S = *pp;`) still stores or binds the pointer word (2026-10-17-whole-source-copy-from-double-pointer-single-deref-stores-pointer-word.md). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 structs lane (unit S5, after D9 (a) made `*pp` of a
`**T` a `*T`), and the same on the lane's tree before that commit (unchanged by it).
**Update (2026-10-16, the 6.7.13 integration):** repro 1 (`take(**pp)` into a by-value `P`) passes on main since the
vectors lane's d9aa49ec (VC-11: a pin carries its pointee's struct) — 4 on x86_64, measured; repros 2 (`var t: P =
**pp;`, 139) and 3 (the 3-byte read, 10) stay open.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane, wave 2, unit S2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Medium — compiles clean and faults on every target (by-value argument, declaration); a small struct's
read takes bytes past the object. No diagnostic.
**Discovered:** 2026-10-16, the 6.7.13 structs lane (S5), probing the struct side of D9 (a) (issues/2026-10-13-double-
pointer-dereference-is-an-untyped-word.md). Sibling, not duplicate: issues/2026-10-15-vector-deref-through-address-of-
or-double-pointer-into-vector-pointer-param.md (vectors lane) files `take(**pps)` into a `*P3` PARAMETER; its vector
half (`rd(**ppb)`) passes since S5 (42 on x86_64 / aarch64 / cx / PE), its struct half still faults (139 / 139 / 252 / 5).
The shapes below are the other struct-value positions with the same root cause.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P { x; y; }
fn take(v: P): i64 { return v.y; }
fn main(): i64 {
    var s = P { 3, 4 };
    var p: *P = &s;
    var pp: **P = &p;
    return take(**pp);         # want 4
}
syscall(60, main());
```

```cyrius
include "lib/syscalls.cyr"
struct P { x; y; }
fn main(): i64 {
    var s = P { 3, 4 };
    var p: *P = &s;
    var pp: **P = &p;
    var t: P = **pp;           # want a copy of s: t.y 4
    return t.y;
}
syscall(60, main());
```

```cyrius
include "lib/syscalls.cyr"
struct C3 { a: u8; b: u8; c: u8; }
var G: u8[8];
fn main(): i64 {
    store64(&G, 0x7766554433020100 + 0x0000000000010203 - 0x0000000000020100);
    var pc: *C3 = &G;
    var ppc: **C3 = &pc;
    var w = **ppc;             # a 3-byte struct value: want 0x010203's bytes only (66051), its padding 0
    var v = *pc;               # the same through the *C3 (6.7.11): byte-exact
    return (w == v) + 10 * (v == 0x010203);
}
syscall(60, main());
```

```
take(**pp):        x86_64 139, aarch64 (qemu) 139, cx 1 (cxvm: guest address fault), PE (wine) 5     want 4
var t: P = **pp;   x86_64 139, aarch64 139, cx 0, PE 5                                                want 4
**ppc (3 B):       10 on all four (w is the 8-byte word 0x7766554433010203, v is 66051)              want 11
(the lane's tree before S5: the same codes)
```

## Root cause

The struct-value consumers of a dereference (`_deref_small`, `_dlo_park`, `_hl_dstar` for a declaration, the by-value
argument arms) type the operand of `*` with `_hl_dpsid` / `_hl_psid` (src/frontend/parse_decl.cyr), a token reader
whose `_hl_pchain` answers 0 for an operand that starts with `*`. So `**pp` — a dereference of `*pp`, which D9 (a)
types `*S` through its step word — is read as the word: `take(**pp)` passes S's first field as S's address, `var t: P
= **pp;` binds a handle holding that word, and a struct under 8 B is the 8-byte load where `*pc` reads it
byte-exact (6.7.11). D9 (a)'s step word (`_pp_inner`, parse_types.cyr) is not consulted by that reader.

## Proposed fix

Teach `_hl_psid` (or `_hl_dpsid`, which the dereference consumers ask) a `* E` operand whose E is a `**S` — a name,
field, call, or `pp + n` typed by `_hl_pchain` with one more level — answering S, so `**pp` is the struct value `*p`
is (6.7.10 decision 6) at every consumer: a by-value argument, a declaration copy, a `*S` argument (the vectors-lane
issue's struct half), an operator's left operand, a small struct's byte-exact read. Rows beside
double_pointer_deref_step.tcyr on x86_64 / aarch64 / cx / PE.
