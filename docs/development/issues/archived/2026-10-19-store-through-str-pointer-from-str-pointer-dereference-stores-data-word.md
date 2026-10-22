# `*q = *p` (q and p `*Str`) stores the header's data word through q, where `*q = *pp` / `*q = gt` store a header's address — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-11, `f508e1f91`, with SS-12 `0c2108b1c` (a handle's name into a `*Str` no longer warns, met) — D73 (the user, 2026-10-20: "q's first word becomes p"), applied to every slot that holds a header's address. `_deref_store` asks `_istr_dsdx` first, and the `*Str` name, declaration, field, literal element, argument and return arms take `*p` as p. The filed repro prints `20120121` (it printed `21020121`) on every leg; the same through a `**Str`, into a `*Str` name, declaration (fn, zone, after a statement), field, literal element, a `s: *Str` argument and `return *p;` from a `: *Str` fn, with no false "assigning non-pointer to typed pointer". To copy the header, `q.data = p.data; q.len = p.len;`. Rows: `inline_str_value.sh` DS1 (the repro verbatim, seven legs); `crossos/inline_str_value.tcyr` ds_* and R_TOP19; `typed_pointer_warn_sign.sh` TH1 / TH2; mutant u1 RED 14. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 structs lane (unit S1) while checking that `t = *pp` (pp a
`**Str`) left the other `*Str` stores alone. Pre-existing: the same output on the slot-open compiler (480de63eb) and after
that fix, on x86_64, aarch64 (qemu) and cx (cxvm). Not that filing's surface (an inline `Str` destination), so filed, not
fixed.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 structs lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; s16 lane, wave 4, unit SS2) — never 7.x.
**Decision (user, 2026-10-20, the found issues' round):** D73 — q's first word becomes p.
**Severity:** Medium — silent: the header q points at gets the other string's data pointer as its data word and keeps its
own length; no diagnostic. Not a security id (the developer's own source).
**Kind:** language (likely a decision) — the pointee-destination twin of 6.7.16's D20 (`h = *p` into a handle). `*p` of a
`*Str` is the header (6.7.10's decision 6); a `Str` value stored through a `*Str` is a header's ADDRESS since 6.7.13's
D7 (1) (`*ps = gt` stores `&gt`, `_istr_dsto`), and `*q = *pp` stores p; 6.7.11's decision (a) copies a struct through a
`*S` but excludes `Str` (`_dx_plain`). `*q = *p` does neither: it stores the word `*p` reads, the header's first field.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
var gt: Str = Str { "abcdefg", 7 };
fn main(): i64 {
    alloc_init();
    var a = str_from("abcde");
    var p: *Str = a;
    var pp: **Str = &p;
    var b = str_from("xy");
    var q: *Str = b;
    *q = *p;
    fmt_int(str_len(q)); fmt_int(load64(q) == load64(a)); fmt_int(load64(q) == a);
    var c = str_from("uv");
    var r: *Str = c;
    *r = *pp;
    fmt_int(str_len(r)); fmt_int(load64(r) == load64(a)); fmt_int(load64(r) == a);
    var d = str_from("st");
    var s: *Str = d;
    *s = gt;
    fmt_int(str_len(s)); fmt_int(load64(s) == &gt);
    return 0;
}
syscall(60, main());
```

```
$ build/cycc < sq.cyr > sq && ./sq
21020121
# *q = *p:  str_len(q) 2, q's data word == a's data word (1), == a (0) — the header's DATA word stored, len stale
# *r = *pp: str_len(r) 2, == a's data word (0), == a (1)            — the header's ADDRESS stored (as D7 (1) stores)
# *s = gt:  str_len(s) 2, == &gt (1)                                  — the header's ADDRESS stored (D7 (1), `_istr_dsto`)
```

aarch64 (qemu) and cx (cxvm) print the same 21020121. No warning on any line.

## Root cause

`*q = <src>` with q a `*Str` is no struct copy: `_dst_struct` (src/frontend/parse.cyr) takes a plain struct only
(`_dx_plain` excludes `Str`), so `_deref_store` parses the source as a value and stores one word at q. `_istr_dsto` turns
an INLINE `Str` source into its header's address for that store (D7 (1)), but a `*Str` dereference source is no inline
`Str`: `*p` leaves the word it reads (the header's data pointer) in rax, `*pp` the `*Str` it reads.

## The question

`*q = *p` with q and p `*Str`: store p (the header's address, as `*q = *pp` and `*q = gt` do under D7 (1), and as D20
rebinds `h = *p`), copy p's header into the one q points at (6.7.11's decision (a) carried to `Str`), or refuse by name?
