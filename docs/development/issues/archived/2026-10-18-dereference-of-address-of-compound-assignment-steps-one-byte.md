# `*(&pi) += 1` of a typed pointer steps one byte, where `*(&pi) = *(&pi) + 1` (6.7.15's D21) and `pi += 1` step the element; and `*(&GQ)` of a packed `i32` global reads 8 bytes — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ST-10, `d796ceee5`, row 1 — no decision needed: 6.7.15's D21 A, `*(&p)` is p — and ST-11, `6ceb0805f`, row 3 — the user's D21, 2026-10-19: "x's own width, as x itself". `_deref_store` takes a typed pointer's step word from `_amp_pw`, and the new `_amp_ew` gives `_deref_read` / `_deref_store` a narrow local's or packed global's width. On x86_64, IR=3, aarch64 (qemu), cx (cxvm) and PE (wine), row 1 exits 44 (was 14): `*(&pi) += 1` steps the element, as do `-=`, `+= 2`, the wraps, a parameter, a global, a for step, top level, a `*i64`, a `*S` and a `**T`, while a `*u8` still steps one byte. Row 2 already gave 44 and is unchanged. Row 3 exits 5 (was 59): `*(&GQ)` reads GQ alone, `*(&GQ) = 7` leaves GR, `*(&GQ) += 1` does not carry into it, and `*(&a)` of an i32 -1 is -1. Rows: `tests/gates/frontend/address_of_pointer_param.sh` R3 / R4 (rows 1 and 3 verbatim), `tests/tcyr/crossos/address_of_pointer_param.tcyr` amp_cop_* (12) and amp_narrow_* (16), 57 / 57 on every leg and on ecb, ach, pi and cass; mutations M2 / M3 / M4 RED. ⚠ Narrower than D21's words ("a narrow integer variable"): a narrow PARAMETER and a closure's capture keep the word, as their own reads do. The parameter is not narrowed at all (`docs/development/issues/archived/2026-10-19-narrow-parameter-holds-caller-word-unnarrowed.md`, D72). An `f32` / `f64` / `bool` variable also keeps the word (`docs/development/issues/archived/2026-10-19-dereference-of-address-of-float-variable-is-untyped-word.md`, D70). Both are placed IN 6.7.16, in the s16 lane. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 vectors lane (its review-fix tree, 2e8b3d14f), x86_64 /
x86_64 `CYRIUS_IR=3` / aarch64 (qemu) / cx (cxvm) / PE (wine). Row 1 is pre-existing as a value (the lane base gives 14
too) but is NEW as a disagreement: before the lane `*(&pi) = *(&pi) + 1` also stepped one byte (base 14); after D21
(93478e55d) the plain form steps 4 and the compound form still steps 1. Row 3 is pre-existing (the base gives 59).
**Placement:** 6.7.16 — Break 2, repair 6 (structs lane, wave 1, unit S5; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D21 — x's own width, as x itself.
**Severity:** Low — compiles with no diagnostic; the pointer moves by 1 byte for 4 (a later read through it is
misaligned and reads the wrong element). Row 3: the read takes the neighbouring global's bytes.
**Kind:** row 1 a bug under D21 A (`*(&p)` is p, its type kept — so `*(&p) OP= n` is `p OP= n`); row 3 possibly a
language question (is `*(&x)` of a narrow scalar x?), named here because the D21 vidya line claims `*(&x)` is x for
every x the compiler types.
**Discovered:** 2026-10-18, the review of the 6.7.15 vectors lane — outside the filed surface of
`issues/archived/2026-10-17-dereference-of-address-of-typed-pointer-local-loses-its-pointee.md` (D21: reads, `*(&p) + n`, a
store `*(&pb) = &x`). The guide's `*(&x) OP= v` sentence (docs/guides/cyrius-guide.md, the struct section) names the
struct (refused), the handle and the scalar (the word op) only — not a typed pointer.

## Reproduction

```cyrius
fn run(): i64 {
  var buf: i64[4];
  var pi: *i32 = &buf;
  var q: *i32 = &buf;
  *(&pi) += 1;
  q += 1;
  var a = pi; var b = q; var o = &buf;
  return (a - o) * 10 + (b - o);
}
syscall(60, run());
```

```
row 1 (above)   *(&pi) += 1;           exit 14 on x86_64 / IR=3 / aarch64 / cx / PE   (44 is right: pi stepped 1)
row 2           *(&pi) = *(&pi) + 1;   exit 44 on all five (base: 14)
                (the same program with row 1's statement replaced, `q = q + 1;` for `q += 1;`)
(every row compiles with rc 0 and no diagnostic)
```

Row 3, the packed narrow global:

```cyrius
var GQ: i32 = 5;
var GR: i32 = 9;
fn run(): i64 { var x = *(&GQ); if (x == 5) { return 5; } if (x == 5 + (9 << 32)) { return 59; } return 1; }
syscall(60, run());
```

```
row 3           exit 59 on x86_64 / IR=3 / aarch64 / cx / PE (and on the lane base): `*(&GQ)` read 8 bytes,
                GQ and GR, where GQ is 5
```

## Root cause

D21 (93478e55d) types `*(&p)` as p through `_amp_pw`, read by the dereference's VALUE (`_deref_read`,
src/frontend/parse_expr.cyr) and by the token readers (`_hl_dref_psid` / `_hl_pw`). The statement path for a compound
assignment through a dereference (`*E OP= v`, src/frontend/parse.cyr — the `&` arm `_hl_damp` decides the struct
refusal) does not consult `_amp_pw`, so the place is the slot's untyped word and `+= 1` adds 1 to it. Row 3: `&GQ` is a
byte address and `*` of it is the untyped 8-byte load (`ELOAD64`), whatever GQ's width; packed narrow globals make the
overread visible (a narrow local's 8-byte slot hides it).

## Fix direction

Row 1: the compound statement through `*(&p)` of a typed pointer steps as `p OP= n` does (D21 A's reach). Row 3: either
`*(&x)` of a narrow scalar reads at x's width (the vidya line's claim), or the vidya / guide line names the exception —
the user's call if it changes what a program computes.
