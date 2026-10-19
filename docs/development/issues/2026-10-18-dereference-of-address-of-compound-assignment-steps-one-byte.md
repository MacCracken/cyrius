# `*(&pi) += 1` of a typed pointer steps one byte, where `*(&pi) = *(&pi) + 1` (6.7.15's D21) and `pi += 1` step the element; and `*(&GQ)` of a packed `i32` global reads 8 bytes — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 vectors lane (its review-fix tree, 2e8b3d14f), x86_64 /
x86_64 `CYRIUS_IR=3` / aarch64 (qemu) / cx (cxvm) / PE (wine). Row 1 is pre-existing as a value (the lane base gives 14
too) but is NEW as a disagreement: before the lane `*(&pi) = *(&pi) + 1` also stepped one byte (base 14); after D21
(93478e55d) the plain form steps 4 and the compound form still steps 1. Row 3 is pre-existing (the base gives 59).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 vectors review, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — compiles with no diagnostic; the pointer moves by 1 byte for 4 (a later read through it is
misaligned and reads the wrong element). Row 3: the read takes the neighbouring global's bytes.
**Kind:** row 1 a bug under D21 A (`*(&p)` is p, its type kept — so `*(&p) OP= n` is `p OP= n`); row 3 possibly a
language question (is `*(&x)` of a narrow scalar x?), named here because the D21 vidya line claims `*(&x)` is x for
every x the compiler types.
**Discovered:** 2026-10-18, the review of the 6.7.15 vectors lane — outside the filed surface of
`issues/2026-10-17-dereference-of-address-of-typed-pointer-local-loses-its-pointee.md` (D21: reads, `*(&p) + n`, a
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
