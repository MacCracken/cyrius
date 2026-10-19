# A `*Str` dereference into a `Str` parameter (`str_len(*p)`, `f(**pp)`) passes the header's first word (its data pointer), not the header — RESOLVED

> ✅ **RESOLVED in v6.7.15** (ST-7, `9360a80bc`, with the review fix ST-7r, `7eef07639` — no decision needed: 6.7.10's decision 6, `*p` of a `*Str` is the header, whose address is p. `_sarg_byval_small` asks `_sarg_istr_dx` first: into a `Str` parameter (not a `p: *Str`), a whole argument that is one dereference `* E` of a `*Str`-typed E, in any parentheses, passes E. The filed repro prints 5555 (was 5500; cx read a wild length) on x86_64, IR=1, IR=3, DCE, aarch64, cx and PE, and on ecb, ach, pi and cass; the fix direction's rows — `str_len(*p)`, `str_len(**pp)`, a user `f(*p)`, `str_len(*w.p)`, `h.eq(*p)` — and the wraps, `*(p + 0)`, a `: *Str` call or method, a tail call, a capture and top level pass the header. A `p: *Str` parameter given `*pp` and an untyped parameter given `*p` are unchanged. One value changes beyond the filing, with no decision asked: `var p: *Str = &h;` (h a handle; `&h` is its slot) now reads the slot as the header (`str_len(*p)` 3 → 0). Rows: `frontend/inline_str_value.sh` SD1 (the repro verbatim) on seven legs; `crossos/inline_str_value.tcyr` sd_* (14) and R_TOP8; mutation RED 14. Not closed here (filed, 6.7.16): a generic's `x: T` at T = Str given `*p` still passes the data word (`2026-10-18-generic-str-instance-dereference-argument-passes-data-word.md`). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 structs lane's review (unit S4), measured on the lane's tree
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
