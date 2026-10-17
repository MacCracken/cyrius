# `**pp += 1` through a `**S` is refused as "compound assignment to the struct 'pp' points at" — pp points at a pointer, not the struct — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 structs lane (unit S2), landing
issues/2026-10-16-struct-double-pointer-dereference-is-no-struct-value.md (its `**pp OP= v` is refused as `*p OP= v` is,
6.7.11's decision (a) with 6.7.13's D9 (a)). The refusal is new with that fix (7c96547f); its wording is `_dst_struct`'s.
**Placement:** 6.7.15 — repair 5 (structs lane; filed from the 6.7.14 structs lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Low — diagnostics only: the right statement is refused once, at the right place; its words name the
wrong operand.
**Kind:** bug (diagnostic wording).

## Reproduction

```cyrius
struct P3{x;y;z;}
fn main(): i64 { var s: P3 = P3{1,2,3}; var p: *P3 = &s; var pp: **P3 = &p; **pp += 1; return s.x; }
var r = main(); syscall(60, r);
```

```
$ build/cycc < c5.cyr > c5; echo $?
error:<source>:2:82: compound assignment to the struct 'pp' points at is refused - a struct value is not an integer or a float (write `*p = *p + b`)
1
```

The same for a top-level `**GPP -= 1` ("the struct 'GPP' points at"). Expected: the operand named as it is written —
"the struct '*pp' points at" (or "'**pp' is a struct value") — and the hint in its spelling (`**pp = **pp + b`).

## Root cause

`_dst_struct` (src/frontend/parse.cyr) names the operand's last name (`_hl_lastnm(S, d + 1, ..)`) — right for `*p`,
where p points at the struct; for `**pp` the operand of the outer `*` is `*pp`, which `_hl_lastnm` reduces to `pp`.
`_err_in_sync` takes a name offset, so the leading `*`s of the operand (`_sval_stars`'s count, parse_fn.cyr, is the
pattern) are not printed.

## Fix direction

Print the operand's leading `*`s before its name, and the hint in the same spelling; rows in
tests/gates/frontend/struct_copy_type_checked.sh C5 / C6 (grep the full message).
