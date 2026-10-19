# An untyped `var k = h.clone();` (a `: Str` METHOD's result) is not typed `Str` — `k.len()` is refused "no struct type in scope for 'k'", where `var k = str_clone(h);` types k — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S4) beside
issues/2026-10-17-method-call-on-str-field-does-not-parse.md (whose `var k = w.s.clone();` now parses and meets this);
measured on the lane base (8b4d44602's frontend, the lane head before S4) and after S4 alike: x86_64 (frontend: every
target alike). Pre-existing.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — a refusal (valid-looking source does not compile; nothing miscompiles). Not a security id (the
developer's own source).
**Kind:** frontend (typing of an untyped declaration).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn main(): i64 {
    alloc_init();
    var h: Str = str_from("abcde");
    var k = h.clone();
    return k.len();
}
syscall(SYS_EXIT, main());
```

```
$ build/cycc < b_cl3.cyr > b_cl3; echo $?
error:<source>:7:17: no struct type in scope for 'k'; a method call needs its struct declaration (missing include?)
1
```

The same with `var k = w.s.clone();` on a `Str` field (it parses since 6.7.15) and `var k2 = h.clone().clone();`.
Controls: `var k = str_clone(h); return k.len();` compiles and exits 5 (a free `: Str` call types an untyped
declaration); `var k: Str = h.clone(); return k.len();` exits 5; `return str_len(k);` with the untyped k exits 5 (the
word IS the handle). method_on_nested_field.tcyr records that a method's 8 B struct result (6.7.0 A5) and a method's
16 / 24 B by-value result type an untyped declaration.

## Root cause (not traced to the line)

`_var_rhs_msid` (src/frontend/parse_decl.cyr) types `var u = x.m(..);` only for a struct result of 8 B or less
(`STRUCTSZ > 8` returns 0), and a larger by-value result is typed through its temp-receive path (`_sc_var_receive`);
a `Str` is 16 B but returned as a handle in rax (no temp), so neither path types it, where the free call's `: Str`
result is typed by the call peek.

## Fix direction

Type an untyped declaration whose whole initialiser is a method (or a chain ending in one) declared `: Str` as the free
`: Str` call's is — a `Str` handle (`k.len()` / `k.cat(..)` start compiling; whether an operator on such a k changes
meaning — `k + 1` — is to be measured when it is placed).
