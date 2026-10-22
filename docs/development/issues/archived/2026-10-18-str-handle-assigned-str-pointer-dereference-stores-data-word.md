# `h = *p` into a `Str` HANDLE (p a `*Str`) stores the header's data word as the handle — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ST-3, `9c22e44e5` — the user's D20, 2026-10-19: "Rebind h to the header p points at". `_istr_dxa` gains a handle arm, `_istr_dxh`: for a `Str` handle local, parameter or global it parses p and stores it, never through the `*p = v` override. The filed repro exits 5 (was 0, with "warning:<source>:8:11: assigning non-pointer to typed pointer") and prints no diagnostic, on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine): h == p afterwards and a later `h.len = 2` is seen through p — for any `*Str`-typed operand (`*GPS`, `*gsp()`, `*w.p`, `*w.sp()`), wrapped, a for step, a capture and at top level. `h = *pp` was already the rebind. Rows: `tests/tcyr/crossos/inline_str_value.tcyr` hd_* (9) and R_TOP12, `tests/gates/frontend/inline_str_value.sh` HD1 (the filed repro verbatim: exit 5 on seven legs, no warning on the four compilers); mutation RED 18. Not this filing's surface, filed beside it (placed IN 6.7.16, the s16 lane): the `Str` FIELD twin `w.s = *p` (`docs/development/issues/archived/2026-10-19-str-field-assigned-str-pointer-dereference-stores-data-word.md`) and `*q = *p` through a `*Str` (`docs/development/issues/archived/2026-10-19-store-through-str-pointer-from-str-pointer-dereference-stores-data-word.md`, D73). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S3) beside D14 (`t = *p` into an INLINE
`Str` copies since 6.7.15); measured on the lane's tree and the lane base alike: x86_64, aarch64 (qemu), cx (cxvm), PE
(wine).
**Placement:** 6.7.16 — Break 2, repair 6 (structs lane, wave 1, unit S2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D20 — Rebind h to the header p points at.
**Severity:** Medium — the handle points at the string's bytes, read as a header (`str_len(h)` 0 here, a wild length
for a longer string); the only diagnostic is "assigning non-pointer to typed pointer". Not a security id (the
developer's own source).
**Kind:** language (decision) — `*p` of a `*Str` is the header (6.7.10's decision 6); a `Str` handle holds a header's
address. Into a handle the readings are a rebind to p (as `h = t` rebinds h to an inline t's header, 6.7.13's D7 (1)),
a copy into a fresh header, or a refusal by name — not D14's question (an inline destination).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn main(): i64 {
    alloc_init();
    var a = str_from("abcde");
    var p: *Str = a;
    var h = str_from("zz");
    h = *p;
    return str_len(h);
}
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < fh.cyr > fh; ./fh; echo $?
warning:<source>:8:11: assigning non-pointer to typed pointer
0           # h = the header's data word; `var k: Str = *p; h = k;` gives 5
```

## Root cause

`_asg_dstar` (src/frontend/parse.cyr) takes a `*Str` dereference only into an inline `Str` (6.7.15's `_istr_dxa`,
`_istr_inl_dst`); into a handle destination it returns 0 and the statement stores the word the dereference reads.

## The question

`h = *p` into a `Str` handle: rebind h to the header p points at (h == p afterwards), copy the header into a new one,
or refuse by name? (The declaration `var h: Str = *p;` copies into an inline header.)
