# A dereference of a `*S` as a tuple literal's element stores the struct's first word, where a struct value element is refused by name — OPEN

**Status:** 🟡 **OPEN** — a question for the user (it would stop code compiling). Measured 2026-10-14 on the 6.7.11
callargs lane (unit A3, x86_64; the element check is frontend, so every target): `var t: (i64, i64) = (*ps, *pw);`
with `ps: *P8`, `pw: *P16` compiles with no diagnostic and stores each struct's FIRST word (exit 75 below), while
`(s, w)` — the struct values themselves — is refused "a tuple element is i64, f64 or bool, not struct 'P8'" (6.7.7 R8).
Since 6.7.10 (decision 6) `*p` is a struct VALUE at every size, and 6.7.11 refuses it by name as one into a by-value
argument of 8 B or less (`take8(*pu)`), but the tuple element reads its static struct through `_expr_struct_sid`,
which has no dereference arm (the A3 arm is the argument's: `_ess_deref`, called from `_sarg_byval_small` only).
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 callargs lane (unit A3), checking what the dereference arm would change in the
fn it shares (`_tup_elem_val`).
**Severity:** Low — a missed refusal; the stored word is the struct's first field (an i64 there), not garbage.
**Affects:** 6.7.7 (tuples) onward; every target.

## Reproduction

```cyrius
struct P8 { a; }
struct P16 { a; b; }
fn go(): i64 {
    var s: P8; s.a = 7;
    var w: P16; w.a = 5; w.b = 9;
    var ps: *P8 = &s;
    var pw: *P16 = &w;
    var t: (i64, i64) = (*ps, *pw);
    return t.0 * 10 + t.1;
}
syscall(60, go());
```

```
$ build/cycc < td.cyr > td && ./td; echo $?
75                     # no diagnostic; `(s, w)` is refused "a tuple element is i64, f64 or bool, not struct 'P8'"
```

## Root cause

`_tup_elem_val` (parse_decl.cyr) judges an element by `_expr_struct_sid` (parse_fn.cyr): a name, a whole call, a
method / operator result, a whole field — not a dereference, so `*ps` has no struct and passes as an i64.

## Proposed fix

The user's call: (a) refuse a whole dereference of a `*S` element by name, as a struct value (call `_ess_deref` from
`_tup_elem_val` too, so the rule is one); or (b) keep it, documented as the struct's first word. Rows in
tests/gates/frontend/tuple_checked.sh beside R8a / R8f.
