# `*(&t)` of an inline `Str` is not the `Str` value `t` is — `h = *(&t)`, `var h: Str = *(&t);`, `f(*(&t))` and `u = *(&t)` take the data word — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 structs lane (unit S2) while landing D20 (`h = *p` into a `Str`
handle rebinds h; p a `*Str`). Pre-existing: the same output on the lane's compiler before D20 (4acc6f7c4) and after it,
x86_64. `&t` of an inline `Str` is not typed `*Str` by the dereference readers, so none of D20's, D14's or 6.7.15's
`*Str`-dereference arms see it — not D20's filed surface (`*p` of a `*Str`), so filed, not fixed.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 structs lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Low — silent wrong value (the string's bytes read as a header: `str_len` 0 for "xyz"); the assignment
forms warn "assigning non-pointer to typed pointer". An unusual spelling (`*(&t)` for `t`). Not a security id (the
developer's own source).
**Kind:** language (possibly a decision) — 6.7.13 reads `*(&p)` / `*&p` of a plain struct as the struct value p is
(`_hl_dpsid` / `_hl_amp_sid`), and 6.7.15's D21 A reads `*(&p)` of a typed pointer as p; `_hl_amp_sid` excludes `Str`
("not a `Str`, tuple or dyn"), so for an inline `Str` t, `*(&t)` is the untyped 8-byte load of t's first word. Under the
same reading `*(&t)` is t: `h = *(&t)` would rebind h to t's header (as `h = t`, 6.7.13's D7 (1)), `var h: Str =
*(&t);` bind it, `f(*(&t))` pass the header, and `u = *(&t)` copy it (as `u = t`) — or the guide names the exception.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
fn f(s: Str): i64 { return str_len(s); }
fn main(): i64 {
    alloc_init();
    var t: Str = Str { "xyz", 3 };
    var h: Str = *(&t);
    fmt_int(str_len(h)); syscall(SYS_WRITE, 1, " ", 1);
    fmt_int(f(*(&t))); syscall(SYS_WRITE, 1, " ", 1);
    var u: Str = Str { "q", 1 };
    u = *(&t);
    fmt_int(u.len); syscall(SYS_WRITE, 1, "\n", 1);
    var k = str_from("q");
    k = *(&t);
    return str_len(k);
}
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < amp.cyr > amp; ./amp; echo $?
warning:<source>:12:14: assigning non-pointer to typed pointer
warning:<source>:15:14: assigning non-pointer to typed pointer
0 0 1
0           # `t` in each position gives 3 3 3 and 3
```

## Root cause

`_hl_dpsid` (src/frontend/parse_decl.cyr) answers a dereference of `& NAME` through `_hl_amp_sid`, which returns 0 for a
`Str` (`_dx_plain`), and `_hl_psid` answers 0 for `&x`; `_deref_read`'s value is the untyped word load. So the
assignment (`_asg_dstar`), the declaration and the `Str` argument arms never see a `*Str`.

## Fix direction

Decide whether `*(&t)` of an inline `Str` is t (the 6.7.13 / D21 A reading); if so, type `& NAME` of an inline `Str`
local, global or capture as a `*Str` at the dereference readers so the existing arms (D14 / D20 / the 6.7.15 argument
arm, `_istr_*`) take it — a frame's t keeps every would-dangle refusal `t` itself has.
