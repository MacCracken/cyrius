# `w.s = *p` / `GW.s = *p` into a `Str` FIELD (p a `*Str`) stores the header's data word, where `v.s = p` rebinds (the field twin of 6.7.16's D20) — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 structs review (the D20 bite, 9c22e44e5) while probing beyond
D20's filed surface (a `Str` handle NAME destination). Pre-existing: the same output on the slot-open compiler
(480de63eb) and on the lane's compiler, on x86_64, aarch64 (qemu) and cx (cxvm). Not that filing's surface, so filed,
not fixed.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 structs review, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; s16 lane, wave 4, unit SS2) — never 7.x.
**Severity:** Medium — a silent wrong value on valid code: the field gets the header's first word (its data pointer) as
the handle, so `str_len(w.s)` reads whatever the string's bytes hold; no diagnostic. Not a security id (the developer's
own source).
**Kind:** language (likely a one-line decision) — the field-destination twin of 6.7.16's D20 (`h = *p` into a `Str`
handle rebinds h to the header p points at, h == p). A `Str`-typed struct field (`s: Str`) is a one-word handle, as a
`Str` local is; `v.s = p` already stores p (the rebind). `w.s = *p` does neither.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
struct WS { s: Str; n; }
var GW: WS = WS { 0, 0 };
fn main(): i64 {
    alloc_init();
    var a = str_from("abcde");
    var p: *Str = a;
    var w: WS = WS { str_from("zz"), 1 };
    var v: WS = WS { str_from("zz"), 1 };
    w.s = *p;
    v.s = p;
    GW.s = *p;
    fmt_int(sizeof(WS)); fmt_int(w.s == a); fmt_int(w.s == load64(a)); fmt_int(v.s == a); fmt_int(GW.s == load64(a));
    return str_len(w.s) * 100 + str_len(v.s) * 10 + str_len(GW.s);
}
var r = main();
syscall(SYS_EXIT, r % 256);
```

```
$ build/cycc < sf.cyr > sf && ./sf; echo " exit=$?"
160111 exit=50
# sizeof(WS) 16 (s is a one-word handle), w.s == a 0, w.s == the header's data word 1, v.s == a 1,
# GW.s == the header's data word 1; str_len(w.s) 0, str_len(v.s) 5, str_len(GW.s) 0 -> 50 (want 555 % 256 = 43)
```

No warning or error at compile (rc 0). aarch64 (qemu-aarch64) and cx (cxvm) print the same `160111` and exit 50; the
slot-open compiler 480de63eb gives the same.

## Root cause

A field store whose source is a dereference asks `_fsc_dstar` (src/frontend/parse_decl.cyr). For `*p` of a `*Str`,
`_hl_dstar_x` answers `Str`, and `_fsc_dstar` declines it (`_dx_plain(S, ps) == 0` -> return 0, a `Str` is no plain
struct copy), so the field store parses `*p` as a value: the word `*p` reads, the header's data pointer, is stored as the
handle. 6.7.16's D20 fix (`_istr_dxh`, sent from `_asg_dstar`) covers a `Str` handle local, parameter or global only;
the field destination never reaches it.

## The question

`w.s = *p` (w.s a `Str` handle field, p a `*Str`): rebind the field to the header p points at (store p, as `v.s = p`
and D20's `h = *p` do), or refuse by name?
