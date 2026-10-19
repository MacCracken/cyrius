# `h = *p` into a `Str` HANDLE (p a `*Str`) stores the header's data word as the handle — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S3) beside D14 (`t = *p` into an INLINE
`Str` copies since 6.7.15); measured on the lane's tree and the lane base alike: x86_64, aarch64 (qemu), cx (cxvm), PE
(wine).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
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
