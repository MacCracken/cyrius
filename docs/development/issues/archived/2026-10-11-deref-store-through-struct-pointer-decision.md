# `*p = l` through a `p: *S` (a struct pointer) stores neither the struct nor one word consistently — a zero-size `S` is overrun by 8 bytes, a small `S` gets its first field only, a 16-byte `S` its first 8 bytes — OPEN (a decision) — RESOLVED

> ✅ **RESOLVED in v6.7.11** (ST-9, the user's decision D4 (2026-10-13, (a)): `*p = v` through a `*S` — a local or parameter, `*self`, `*GP`, `*(p + n)`, `*gp()`, `*w.p` — copies exactly sizeof(S) bytes, none for a zero-size struct, from any S value `G = v` takes (a `*S` or a handle source copies its struct); another struct is refused naming both, `*p OP= v` is refused as `l += a` is, and an untyped value is stored as the struct's word at sizeof(S) bytes, at most 8. The zero-size repro gives 77 (it gave 0) and the 16 B repro 90 (it gave 42) on x86_64, aarch64, cx and PE; the 3 / 4 / 8 B rows store the struct with the neighbour intact. Rows: `crossos/deref_store_struct_copy.tcyr` (322: 0 / 3 / 4 / 5 / 6 / 7 / 8 / 9 / 16 / 24 B, `small_struct_handle_line.sh` R15 on seven legs), `struct_copy_type_checked.sh` R17–R25, C1–C4, A10 / A11 (the repros verbatim). Filed beside it: whether the untyped store over 8 B should zero bytes 8.. (issues/2026-10-14-untyped-store-through-struct-pointer-over-8-bytes-reading.md) and `*p = mv()` from a multi-value fn (issues/2026-10-14-multi-value-call-stored-through-struct-pointer-decision.md). CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN — a decision for the user** (what `*p = v` means when `p` points at a struct). Raised by the
6.7.9 critical lane (bite 1, the zero-size global store), which fixed `G = l` for a zero-size global and left the
pointer form, as a language question. Verified 2026-10-11 against the merged 6.7.9 tree (`build/cycc` @ 27220379,
2,057,736 B) on x86_64; the zero-size and 16-byte rows also on aarch64 (qemu) and cxvm, with the same results. The
installed 6.7.0 and 6.7.8 compilers give the same exits.
**Placement:** 6.7.11 — repair 1 (roadmap.md § *The releases after 6.7.8*; the deref store in `parse.cyr`
`_deref_store` / `_deref_ed`) (the user's call, asked at that release's open) — placed 2026-10-11 — never 7.x.
**Discovered:** 2026-10-11 during 6.7.9's
[zero-size struct global store](2026-10-09-zero-size-struct-global-store-overwrites-neighbour.md) fix.
**Severity:** Medium — silent: every shape compiles clean; a zero-size or sub-word store can corrupt a neighbour or
leave the target half-written.
**Affects:** cycc 6.7.0 – 6.7.9 (measured), every target.

## Summary

6.7.8 (C2-5, the user's decision) made `*p = v` through a NARROW scalar `*T` store T's bytes, and left "every other
operand" a WORD address, stored 8 bytes (guide § Pointers). A struct pointer is in neither list explicitly, and what
it does today depends on the struct's shape — never a whole-struct copy, which is what `G = l`, `var x: S = l`,
`b.v = l` and a by-value argument all do (6.6.6 / 6.6.10 / 6.7.7):

| `S` | `*p = l` (with `l: S`, `p: *S = &G`) | measured |
|---|---|---|
| `struct E { }` (0 B) | 8 bytes stored over the next global | `N1: i8 = 77` after `G` reads 0 |
| `{ a: u8; b: u8; c: u8; }` (3 B) | `G.a` only (1 byte) | `{1,2,3}` ← `{4,5,6}` gives `{4,2,3}`, neighbour intact |
| `{ a: u16; b: u16; }` (4 B) | `G.a` only (2 bytes) | `{1,2}` ← `{4,5}` gives `{4,2}` |
| `{ a: i32; b: i32; }` (8 B) | the whole struct (one word) | `{4,5}` |
| `{ x; y; }` / `{ a: i64; b: u8; }` (16 B) | the first 8 bytes | `G.x + G.y` = 40 + 2 = 42 (want 90) |

## Reproduction

```cyrius
struct E { }
var G: E = E { };
var N1: i8 = 77;
fn run(): i64 { var l: E; var p: *E = &G; *p = l; return 0; }
var rr = run();
syscall(60, N1);          # actual 0 · 77 if nothing (or the zero bytes of E) is stored
```

```cyrius
struct P2 { x; y; }
var G: P2 = P2 { 1, 2 };
fn run(): i64 { var l: P2 = P2 { 40, 50 }; var p: *P2 = &G; *p = l; return 0; }
var rr = run();
syscall(60, G.x + G.y);   # actual 42 (only x copied) · 90 for a whole-struct copy · 3 if nothing is stored
```

## The decision

- **(a) `*p = v` copies the whole struct** when `p: *S` and `v` is an `S` value (a local, parameter, global, field,
  call / method / operator result), exactly `sizeof(S)` bytes — 0 for a zero-size struct — as `G = v` does; a value of
  another struct type is refused naming both, as the assignment is. Recommended: it is the only reading in which
  `*p = l` and `G = l` (with `p = &G`) agree.
- **(b) Refuse `*p = v` through a struct pointer** by name, pointing at the copy spellings (`G = l`, or a field-wise
  store), and keep raw word stores to `store64`.
- **(c) A word store, stated** — the C2-5 "every other operand" rule extended to struct pointers: always 8 bytes
  (which still overruns a sub-8-byte struct), documented in the guide.

Today's per-shape behaviour (the first-field-only store for a 3- or 4-byte struct is neither a word nor the struct) is
not an option on the list. (a) and (b) change what compiles or computes. Rows for any answer: the five shapes above
plus 5-, 6-, 7-, 9- and 24-byte structs, a global and a local target, on x86_64, qemu-aarch64, cxvm and PE (wine);
`*p OP= v` through a struct pointer refused (or dispatched to the operator) as the chosen rule says.
