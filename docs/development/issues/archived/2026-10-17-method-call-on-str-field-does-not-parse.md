# A method call on a `Str` FIELD (`w.s.len()`, `w.s.clone()`, `w.s.eq(x)`) does not parse — "expected ';', got '.'" — RESOLVED

> ✅ **RESOLVED in v6.7.15** (ST-10, `45dc4863b` — no decision needed: a false refusal of valid source. `_fld_meth_inline` answers 1 for a `Str` field and `_load_inline_hop` sends it to `_load_str_hop`, which loads the field's word and parks it as the `*Str` receiver: the method's `self` is the header the field holds, as `str_len(w.s)` passes it. The filed repro `return w.s.len();`, refused "7:15: expected ';', got '.'", exits 5; `var k = w.s.clone();` 5 and `return w.s.eq(w.s);` 1; the controls `w.s.len` / `str_len(w.s)` still 5 — on x86_64, IR=1, IR=3, DCE, aarch64, cx and PE, and on ecb, ach, pi and cass. Also through a `*W`, two levels down, a `*T` field, a call's or method's result, `self.s`, a global, a capture, a wrap, a statement writing through `self`, a chain and top level. Rows: `frontend/str_field_method.sh` (new; F1 – F3 the repros verbatim, C1 / C2 the controls, T) on seven legs; `crossos/str_field_method.tcyr` (16); mutations RED 28 each. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 structs lane (unit S4), x86_64, on the lane's tree and on
c778c981 (before the unit) alike: pre-existing. Frontend: every target alike.
**Placement:** 6.7.15 — repair 5 (structs lane, wave 2, unit S4; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — a refusal with a misleading message (valid-looking source does not compile; nothing
miscompiles). Not a security id (the developer's own source).
**Kind:** frontend (parse).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct W { s: Str; n; }
fn main(): i64 {
    alloc_init();
    var w: W = W { str_from("abcde"), 1 };
    return w.s.len();
}
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < sC.cyr > sC; echo $?
error:<source>:7:15: expected ';', got '.'
1
```

`var k = w.s.clone();` and `return w.s.eq(w.s);` give the same error. Controls that compile and exit 5:
`return str_len(w.s);` and `return w.s.len;` (the field's `.len`, a hop through the handle, 6.6.17). A method on a
`Str` LOCAL (`h.len()`, `h.clone()`) parses.

## Root cause (not traced to the line)

The field walker stops at a `Str` field — "a Str field is a pointer slot: no walk INTO it" (src/frontend/parse.cyr,
the `IS_STR_FIELD` arms) — and `_rlf_more` declines a `.method(` on a nested field, so the method step after a
`Str` field is never taken and the `.` is left for the statement.
