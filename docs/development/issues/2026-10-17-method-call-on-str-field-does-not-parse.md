# A method call on a `Str` FIELD (`w.s.len()`, `w.s.clone()`, `w.s.eq(x)`) does not parse — "expected ';', got '.'" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 structs lane (unit S4), x86_64, on the lane's tree and on
c778c981 (before the unit) alike: pre-existing. Frontend: every target alike.
**Placement:** 6.7.15 — repair 5 (structs lane; filed from the 6.7.14 structs lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
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
