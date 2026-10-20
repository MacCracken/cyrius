# An enum, `Result`, `Option`, `Tagged` or `cstring` given type arguments compiles with the list unread, a name that is no type included — OPEN

**Status:** 🟡 **OPEN** — raised 2026-10-20 by the 6.7.16 gensig review (file_as_issue 3, the enum) and widened to its
class by the lane's review-fix step. Measured on the lane head 7f3d2260d and the lane's base b73e8d5fe (x86_64):
identical on both, so this is pre-existing, not a regression.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 gensig review, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; f16 lane, wave 4, unit FG3) — never 7.x.
**Decision (user, 2026-10-20, the found issues' round):** D88 — By declaration: refused where none are declared, read where declared.
**Severity:** Low. Nothing is computed wrongly from the written base name: an enum is an i64, and the handles are
8-byte handles. But the list is never read, so a name in it that is no type (`Nope`) or a refused shape (`Pt<i64>`) is
never reported, and one consequence (repro 2) is a trait impl whose return differs that compiles.
**Kind:** language. The rule for a non-generic name given type arguments is the user's (6.7.15's D6, 6.7.16's D7:
"refused once, at the name"). Those decisions name a non-generic struct and a scalar. `_ngt_refuse`'s own comment
says an enum, Result / Option / Tagged and cstring are "not this shape". Refusing them changes what compiles.

## Reproduction 1 — the list is stepped unread

```cyrius
enum Color { Red, Green }
struct H { p: *Color<i64>; k; }
fn g(c: Color<Nope>, s: cstring<i64>, t: Tagged<Zork>): i64 { return 6; }
fn h(): *Color<i8> { return 0; }
fn main(): i64 { var e: Color<i64> = 0; var hh: H; hh.k = 0; return g(0, 0, 0); }
```

```
$ cycc < rn4.cyr > rn4 && ./rn4; echo $?
6          # rc 0, no diagnostic (base and head)
```

```cyrius
fn f(p: Result<Nope>, q: Option<Zork>): i64 { return 3; }
fn main(): i64 { return f(0, 0); }
```

This exits 3. `var r: Result<Nope> = 0; var o: Option<Pt<i64>> = 0;` in a fn also compiles (exit 5). The review's probe
(/home/macro/.cache/c6/s6716/gensig/review/rev/p/en.cyr: `var g: *Color<u8>`, `f(c: *Color<i64>): *Color<i8>`, a
local `*Color<i32>`, a field `*Color<i64>`) is rc 0 on both compilers.

A fn's own return is the exception: `fn g(): Option<i64>` is a parse error with a cascade (`1:15: expected '{', got
'<'` then `1:21: undefined variable 'i64'`). A trait member's `: Option<i64>` return is accepted unread.

## Reproduction 2 — a trait impl whose return differs compiles

```cyrius
struct P { a; b; }
trait T2 { fn sh(self): Result<Nope>; }
impl T2 for P { fn sh(self): i64 { return 4; } }
fn main(): i64 { var p = P { 1, 2 }; return p.sh(); }
```

```
$ cycc < rn1.cyr > rn1 && ./rn1; echo $?
4          # rc 0 (base and head)
```

6.7.15's D4 refuses an impl method whose return differs from its member's (`Result` against `i64` here). It is not
refused here, because the impl check's 6.7.15 name arm (`_tr_rt_bad`, src/frontend/parse_fn.cyr) counts `Nope`
inside the unread list as "a side its own reader refuses" and stands down. No reader refuses it, so nobody reports
it. The `Pt<i64>` form of this, `: Result<Pt<i64>>`, compiled on the lane head after the D7 bite (4c6a024a3). It was
repaired by the review-fix step (b690e6a3d, traits_checked.sh TRR1 / TRR2), whose `_ty_rd_scan` steps such a list.
That repair left 6.7.15's name arm as it was, because counting only read names there makes this program stop
compiling. A formed dyn reports this pair: dyn_checked.sh F8r7, and F8p8 for a parameter.

## Root cause

Each type reader skips the `<..>` after a name that is not a generic struct or `Vec` (`SKIP_GENERICS`, the member
reader's `d` loop in `_trs_type`, the annotation readers). Only a generic struct's list (`_targ_chk`) and `Vec`'s
(`_vec_ann_chk`) are read. D6 / D7 added a refusal for the non-generic struct and scalar shape only (`_ngt_tail`).

## Fix direction (the user's call)

Either refuse a type-argument list after these names once, at the name, as D6 / D7 do for a struct and a scalar.
Then rn1's `Nope` is the reader's refusal and the impl check's stand-down is right. Or keep them accepted. In that
case read the list's names (an unknown name refused), and the impl check's 6.7.15 name arm should count only names a
reader reads (`_ty_rd_scan(.., 1)`), so rn1 is refused "'P.sh' returns i64, trait 'T2' declares Result<Nope>".
