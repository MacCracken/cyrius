# A `*Str` dereference into a `Str` parameter (`str_len(*p)`, `f(**pp)`) passes the header's first word (its data pointer), not the header — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 structs lane's review (unit S4), measured on the lane's tree
and at the lane base f133fb2f (the same output on both): x86_64, aarch64 (qemu) and cx (cxvm) alike. Pre-existing.
**Placement:** 6.7.15 — repair 5 (structs lane, wave 2, unit S3; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Medium — silent: the callee reads the string's bytes as a `Str` header (`str_len` 0 here; a longer
string's bytes give a wild length and data pointer). Not a security id (the developer's own source).
**Kind:** bug — `*p` of a `p: *Str` is the header value (6.7.10's decision 6: through a pointer to a struct `*p` is the
struct), and where a `Str` value is taken its address is what travels (6.7.13's D7 (1) for an inline header: an inline
`Str` into `s: Str` passes its header's address). The declaration already reads it so: `var s: Str = *p;` then
`str_len(s)` is 5.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
fn main(): i64 {
    alloc_init();
    var h = str_from("abcde");
    var p: *Str = h;
    var pp: **Str = &p;
    var s1: Str = *p;
    var s2: Str = **pp;
    fmt_int(str_len(s1)); fmt_int(str_len(s2)); fmt_int(str_len(*p)); fmt_int(str_len(**pp));
    return 0;
}
syscall(60, main());
```

```
$ build/cycc < i6t.cyr > i6t && ./i6t
5500        # str_len(s1) 5, str_len(s2) 5, str_len(*p) 0, str_len(**pp) 0 — 5555 is right
```

A user fn with a `Str` parameter alike — `fn f(s: Str): i64 { return str_len(s); }`: `f(*p)` 0, `f(**pp)` 0, `str_len(p)`
5 (the `*Str` itself is the header's address). aarch64 (qemu) and cx (cxvm) print the same. No diagnostic anywhere.

## Root cause

A `Str` parameter is a handle class: the argument expression's value is passed as the header's address. `_istr_arg`
(src/frontend/parse_decl.cyr) re-addresses only an inline `Str` source (`_istr_at`: an inline-`Str` name, 6.7.13's D7
(1)); a dereference `*p` / `**pp` of a `*Str` parses as a word read, so the deref loads the header's FIRST word (the
data pointer) and that word is passed as the header. The struct-value argument path that passes `*p` of a `*S` to a
by-value user struct (`_ess_deref`, 6.7.13) is not taken: `Str` is classified a handle, not a by-value struct. The
declaration `var s: Str = *p;` goes through the struct-copy init and so is right.

## Fix direction

Where a `Str` parameter takes a whole dereference whose operand is a `*Str` (`_hl_psid` answers `Str`: a `*Str` name,
field, call, `pp` of a `**Str` since 7c96547f, `p + n`), pass the operand's word — the header's address — instead of
the dereference (a `*Str` deref there is the header, whose address is the pointer). Rows in
tests/tcyr/crossos/inline_str_value.tcyr on every leg (`str_len(*p)`, `str_len(**pp)`, a user `f(*p)`, a `*Str` field
`str_len(*w.p)`, a method `h.eq(*p)`).
