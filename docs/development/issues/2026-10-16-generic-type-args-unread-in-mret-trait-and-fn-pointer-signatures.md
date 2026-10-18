# A multi-value return element, a trait member's signature and a `*fn(..)` parameter type leave a generic struct's type arguments unread (`(Box<Zork>, i64)`, `b: Box<nosuch>`, `*fn(Box<Zork>)`) — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-16 by the 6.7.14 generics lane (unit G3), surveying the positions next to
issues/archived/2026-10-09-undeclared-generic-type-arguments-accepted.md (D6 (a): a fn definition's parameter and return now
read their generic struct's type arguments at the definition). Pre-existing: identical on the slot-open compiler
(2600f67f's build/cycc) and on the lane tree after G3 (fce26f17).
**Placement:** 6.7.15 — repair 5 (generics lane, wave 1, unit G3; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D7 — (a) Refuse each once, naming the type.
**Severity:** Low — an undeclared type argument compiles silently as the base struct.
**Kind:** language — D6's question listed four shapes (`m: Mp<K, V>`, `m: *Mp<K, V>`, `: Mp<K, V>`, `m: Box<Zork>`);
these three positions are other readers (whether D6's rule extends to them is the user's call; the guide's
"every type-argument position checks its names", § Generic Functions v6.6.8, suggests yes).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
fn mv(): (Box<Zork>, i64) { return (0, 1); }
trait Sh { fn a(self, b: Box<nosuch>): i64; }
fn ap(cb: *fn(Box<Zork>): i64): i64 { return 0; }
fn main(): i64 { var a, c = mv(); return c + ap(0); }
syscall(60, main());
```

```
$ build/cycc < n2.cyr > n2 && ./n2; echo $?
1
```

Expected (with D6's rule): each refused once, "unknown type 'Zork' as a type argument (...)", as
`fn gm(m: Box<Zork>)` and `var b: Box<Zork>;` are. Already refused: a multi-value `(*Mp<K, V>, i64)` element
(through `_ptr_annot`), a `**Box<Zork>` parameter, a `: *Mp<K, V>` return.

## Root cause

- `_mret_elem` (src/frontend/parse_fn.cyr) calls `_gtype_sid`, which keeps the base when an argument does not
  resolve; the fn definition's sites call `_gtype_sid_def` since 6.7.14, `_mret_elem` (pass 1 and pass 2) does not.
- `_trs_type` (the trait-signature reader) `_trs_name`s the struct and skips its `<..>` (6.7.14 reads a `Vec<..>`
  there only).
- `_pty_name` (a name inside a `*fn( .. )` parameter type) checks the name and `_pty_gen_end` skips its `<..>`.

## Fix direction

`_mret_elem` with `quiet == 0`: `_gtype_sid_def` in place of `_gtype_sid`; `_trs_type` and `_pty_name`: when the
name is a generic struct followed by `<`, `_targ_chk(S, <the '<' token>)` (read, nothing minted; the fn's / the trait
member's own type parameters stay names). Rows: the three shapes, once each; controls `(Box<Pt>, i64)`,
`b: Box<i64>` in a trait, `*fn(Box<Pt>): i64`.
