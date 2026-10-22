# An untyped `var k = h.clone();` (a `: Str` METHOD's result) is not typed `Str` — `k.len()` is refused "no struct type in scope for 'k'", where `var k = str_clone(h);` types k — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ST-5, `f3331c48e` — no decision asked (a false refusal). `_var_rhs_mchain`, the post-parse typing of an untyped declaration whose whole initialiser is a chain ending in a method, answers the `Str` struct when that method is declared `: Str` (`_var_rhs_mstr`). The filed repro exits 5 (was rc 1, "7:17: no struct type in scope for 'k'; a method call needs its struct declaration (missing include?)") on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine); `var k = w.s.clone();`, `h.clone().clone()`, `mks().clone()` and `h.sub(1, 3)` alike, k its own handle. As the filing asked, operators were measured: `k + 1`, `k - h` and `k == h` are unchanged. Overload dispatch does change: `println(k)` / `show(k)` now take the `Str` overload, as `var k = str_clone(h);` does (no decision asked; listed among 6.7.16's behaviour changes). Top level is unchanged (`var K = H.clone();` keeps the word, as `var K2 = str_clone(H);` does). Rows: `tests/tcyr/crossos/method_on_nested_field.tcyr` ms_str_* (9; the file 17 / 17 on x86_64 / IR=1 / IR=3 / DCE / aarch64 / cx / PE); mutation: the rows file refused, 8 errors. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S4) beside
issues/archived/2026-10-17-method-call-on-str-field-does-not-parse.md (whose `var k = w.s.clone();` now parses and meets this);
measured on the lane base (8b4d44602's frontend, the lane head before S4) and after S4 alike: x86_64 (frontend: every
target alike). Pre-existing.
**Placement:** 6.7.16 — Break 2, repair 6 (structs lane, wave 1, unit S2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
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
