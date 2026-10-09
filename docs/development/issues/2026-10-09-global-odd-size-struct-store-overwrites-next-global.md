# A whole-struct store of 3 / 5 / 6 / 7 bytes into a global writes 8 bytes — the next global is overwritten — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against `build/cycc` @ e44470b7 (6.7.6 + the merged 6.7.7 fixes): the
repro exits 0 where 77 is right (the global after `G` is overwritten); without the `G = l;` store it exits 77. The
6.7.x release-plan sizing (B7's sizer) measured `{i8,i8,i8}`, `{i32,i8}`, `{i32,i16}` and `{i32,i16,i8}` — both
`G = l` and `G = mk()` overwrite the global at +3..+7; sizes 1, 2 and 4 store exactly.
**Placement:** 6.7.7 (roadmap.md § Release sequence) — placed 2026-10-09 — never 7.x.
**Discovered:** 2026-10-09 by the 6.7.x release-plan sizing (the B7 sizer's probes); filed 2026-10-09.
**Severity:** High — silent memory corruption of an unrelated global, on valid code, with today's `i8` / `i16` /
`i32` fields.
**Affects:** cycc since narrow struct fields packed (v6.6.10) through 6.7.6.

## Summary

Narrow scalar globals and narrow struct fields are PACKED, so a struct global can be 3, 5, 6 or 7 bytes. Storing a
whole struct value into such a global (`G = l;`, `G = mk();`) emits an 8-byte store, which writes past the end of
`G` into whatever global is packed after it.

## Reproduction

`docs/development/issues/repros/2026-10-09-global-odd-size-struct-store-overwrites-next-global.cyr`:

```
struct S3 { a: i8; b: i8; c: i8; }
var G: S3 = S3 { 0, 0, 0 };
var N1: i8 = 77;
fn main() { var l: S3; l.a = 1; l.b = 2; l.c = 3; G = l; return N1; }
var r = main(); syscall(60, r);
```

`cat repro.cyr | build/cycc > a && ./a; echo $?` → **0** (want 77). Remove `G = l;` → 77.

## Root cause

Probable (the sizer's reading; verify which store path `G = l` takes): `_gv_store`
(`src/frontend/parse_decl.cyr:3508`) sizes only widths 1 / 2 / 4 (`EVSTORE_W`) and sends every other width to the
8-byte `EVSTORE`; its own comment says "an inline struct global can be 3/5/6/7 bytes, and those keep the full store".
The struct sibling of the 6.6.13 narrow-scalar-global fix (CHANGELOG [6.6.13]).

## Proposed fix

Store exactly `w` bytes for an odd width (a 4 + 2 + 1 decomposition, or a byte loop) on every backend, with rows for
every size 1–8 (and a 9–15 B struct global, whose tail word has the same shape), `G = l` and `G = mk()`, x86 / aarch64 /
cx / PE.
