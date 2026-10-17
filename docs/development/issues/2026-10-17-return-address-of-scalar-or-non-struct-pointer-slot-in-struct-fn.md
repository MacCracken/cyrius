# `return &x;` in a fn returning a struct, with `x` a scalar, a `*i64` / `*V`, a `**S` or a `Str` handle: at 8 B the slot's ADDRESS is the struct's word; over 8 B refused in other words — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 structs lane (unit S3) on the lane's tree after the D19 (a)
commit (`c778c981`), x86_64; identical on the lane's tree before it (9498bfb3, the S2 tip). Frontend: every target alike.
**Placement:** 6.7.15 — repair 5 (structs lane; filed from the 6.7.14 structs lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Medium — silent at 8 B or less: the caller reads a stack address (a dead frame's slot) as the struct's
field; over 8 B a refusal that names nothing. Not a security id (the developer's own source).
**Kind:** language (decision) — 6.7.14's D19 (a) (issues/2026-10-15-return-address-of-handle-or-pointer-in-struct-fn.md)
refuses `return &q;` by name when q is a handle, a `*S` (any struct pointer) or an untyped `self`, and 6.7.13's D4 (a)
reads `&s` of an inline struct as the struct. The triage of that issue put `&n` of a scalar out of its scope; what
`&x` of a NON-struct name means in a `: S` fn's return is not decided.
**Discovered:** 2026-10-17, landing D19 (a): the refusal (`_ret_slot_amp`, src/frontend/parse_fn.cyr) takes the
struct-typed names only (`_hl_name_ty > 0`); the shapes below still reach the old arms.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct S { v; }
fn h(): S { var n = 5; return &n; }
fn main(): i64 { alloc_init(); var c = h(); return c.v; }
syscall(60, main());
```

```
$ build/cycc < sn8.cyr > sn8 && ./sn8; echo $?     (twice)
48, then 0              # the low byte of &n (a dead frame's slot, ASLR-dependent); no diagnostic
```

The same at 8 B, each compiling with no diagnostic and exiting an address byte that changes run to run:

| `h()` body (S 8 B) | exits (two runs) |
| --- | --- |
| `var n = 5; var pi: *i64 = &n; return &pi;` | 248, 56 |
| `var s: S; var p: *S = &s; var pp: **S = &p; return &pp;` | 0, 16 |
| `var t = str_from("ab"); return &t;` (a `Str` handle; lib/string.cyr + lib/str.cyr) | 96, 144 |
| `var a: f64v2 = f64v2_make(1, 2); var pv: *f64v2 = &a; return &pv;` (lib/simd.cyr) | 128, 192 |

Over 8 B (S `{ v; w; }` / `{ v; w; x; }`) the classes' own refusals, naming nothing:

```
16 B: error: a fn returning the 9-16 byte struct `S` is returned in two registers, so `return` takes a local of that
      struct or a call returning it — got `this expression`
24 B: error: struct-return fn: return must be a bare local identifier, or a call to a fn returning the same struct
```

## Root cause

`_ret_small_ptr` (8 B or less) and `_ret_ptr_src` (the pair and retptr classes) type the value with `_hl_dpsid`, whose
`& IDENT` arm answers only for an inline struct; D19 (a)'s `_ret_slot_amp` answers for a struct-typed handle / `*S` /
untyped `self`. A scalar, a `*i64` / `*V`, a `**S` (its local carries no struct type, `_hl_name_ty` 0) and a `Str`
handle (`_dx_plain` 0, excluded) reach neither: at 8 B the scalar tail returns the address as the struct's word; over
8 B the class refuses it generically.

## Options (the user's)

- (a) Refuse by name at every size, as D19 (a) does: "`&n` is the address of n's slot, not a struct". 8 B programs
  that compile today (and return a stack address) stop compiling.
- (b) Leave it (the 8 B word; the over-8 B refusals keep their wording) and document it beside the guide's D19 sentence.
