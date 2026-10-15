# `var p: P = f();` with a multi-value `f` compiles and crashes (the first value is taken as a pointer) — RESOLVED

> ✅ **RESOLVED in v6.7.11** (RET-5, commit 561e1afa, with issues/archived/2026-10-09-multi-value-call-into-named-struct-slot.md: a multi-value call where a named struct is expected is refused by name. The repro `var p: P = g2(5);` (SIGSEGV on x86_64 and aarch64, a guest error on cx, an access violation on PE) is *a multi-value call 'g2' does not initialize struct 'P' - bind it first: `var a, b = g2(..);`* on all four. The user's decision D21 (2026-10-13): refuse by name. Row: `multi_value_into_named_struct.sh` V1 (the repro verbatim, on the x86_64, aarch64, cx and PE compilers). CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — verified 2026-10-09 against the merged 6.7.7 compiler (l677-int @ 881895f6): the repro builds and exits 139 (SIGSEGV) on x86 (aarch64 the same, per the 6.7.7 aarch64 lane).
**Placement:** 6.7.11 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*); refusing it is the user's call at the open (a crashing program stops compiling) — placed 2026-10-09 — never 7.x.
**Discovered:** the 6.7.7 B4 lane (T0, as a note) and the aarch64-registers lane; filed 2026-10-09.
**Severity:** Medium — a crash, not a silent value; the tuple capture refuses the same mismatch by name
**Affects:** cycc ≤ 6.7.7

## Summary

A struct-annotated `var` initialised from a non-struct call takes pointer mode (the documented rule), so a call to a
fn declared `: (i64, i64)` is read as a pointer to a `P`. The compiler knows the callee returns two values — the B4
capture `var t: (i64, i64) = f();` refuses the analogous mismatch by name.

## Reproduction

```
struct P { a; b; }
fn g2(x): (i64, i64) { return (x, x + 1); }
fn main(): i64 { var p: P = g2(5); return p.a * 10 + p.b; }
var r = main(); syscall(60, r);
```
Exits 139.

## Proposed fix

Refuse a declared multi-value callee as a struct `var`'s initializer, naming the tuple capture as the fix.
