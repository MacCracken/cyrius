# `return &x;` in a fn returning a struct, with `x` a scalar, a `*i64` / `*V`, a `**S` or a `Str` handle: at 8 B the slot's ADDRESS is the struct's word; over 8 B refused in other words — RESOLVED

> ✅ **RESOLVED in v6.7.15** (ST-14, `96fa0c2be` — the user's decision D18, 2026-10-18: "Refuse it by name at every size". `_ret_slot_amp`, asked by both class arms before their own refusals, takes a name holding no struct through `_ret_amp_bare`. The filed repro (sn8, which exited an address byte, a different one each run) is one error at 4:31: "a fn returning the struct `S` takes a value of that struct, or a pointer to one — `&n` is the address of n's slot, not a struct"; the table's `&pi`, `&pp`, a `Str` handle's `&t` (", and t is a `Str`") and `&pv` likewise at 8 B, and at 16 / 24 B the classes' nameless refusals become the same named one — on the x86_64, aarch64, cx and PE compilers and the ecb, ach, pi and cass natives. Beyond the filed table: a parameter, a global, an array, an `f64` / `u128`, an inline vector; `&t` of an inline `Str` or a tuple is refused as `&u` of another struct ("got `&t` (a `*Str`)"). Rows: `frontend/small_struct_return_type_refused.sh` R40 (the repro verbatim) – R58, and A15 (a generic used only at `<S8>` compiles); mutations RED. Not closed here (filed, 6.7.16; short of D18's "every size"): a generic's i64 base — `hg(3)` of `fn hg<T>(x: T): S8 { var n: T = x; return &n; }` — is not judged and still returns the slot's address (`2026-10-18-generic-base-return-address-of-local-unjudged-at-i64.md`). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 structs lane (unit S3) on the lane's tree after the D19 (a)
commit (`c778c981`), x86_64; identical on the lane's tree before it (9498bfb3, the S2 tip). Frontend: every target alike.
**Placement:** 6.7.15 — repair 5 (structs lane, wave 2, unit S5; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D18 — Refuse it by name at every size.
**Severity:** Medium — silent at 8 B or less: the caller reads a stack address (a dead frame's slot) as the struct's
field; over 8 B a refusal that names nothing. Not a security id (the developer's own source).
**Kind:** language (decision) — 6.7.14's D19 (a) (issues/archived/2026-10-15-return-address-of-handle-or-pointer-in-struct-fn.md)
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
