# `t = *pp` (pp a `**Str`, so `*pp` is a `*Str`) into an inline `Str` still stores one word, where `t = p` copies since 6.7.15's D14 — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ST-2, `4acc6f7c4` — no decision needed: 6.7.15's D14, `t = p` / `t = *p` with p a `*Str` copy the header, with 6.7.13's D9 (a), `*pp` of a `**Str` is a `*Str`. `_hl_dpp_sid` answers `Str` in a mode 2 that only the assignment (`_asg_dstar`) asks, so `_istr_dxa` copies the 16-byte header through the `*Str` `*pp` reads. The filed repro exits 55 (was 22), no warning before or after, on x86_64, IR=1, IR=3, DCE, aarch64 (qemu), cx (cxvm) and PE (wine) — and a bare `var t: Str;`, an inline global, a for step, the wraps, `*pp` of a parameter, global, field or `: **Str` call, `**ppp`, a capture and top level alike. `q = *pp` into a `*Str` and `h = *pp` into a handle stay the rebind. Rows: `tests/tcyr/crossos/inline_str_value.tcyr` pps_* (11) and R_TOP11, `tests/gates/frontend/inline_str_value.sh` PP1 (the filed repro verbatim, every leg); mutation RED 14. Beside it, not this filing's surface and filed (placed IN 6.7.16, the s16 lane): the declaration `var u: Str = *pp;` binds a handle (`docs/development/issues/archived/2026-10-19-str-declaration-from-double-str-pointer-single-deref-binds-handle.md`; the user's D74, 2026-10-20: its own copy). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S3), measured on the lane's tree after the
D14 commit: x86_64, aarch64 (qemu), cx (cxvm) and PE (wine) alike (22, no diagnostic). The same on the lane base.
**Placement:** 6.7.16 — Break 2, repair 6 (structs lane, wave 1, unit S1; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Medium — silent: t.data takes the header's address, t.len stays stale (the pun 6.7.14's D20 (a) and
6.7.15's D14 retired for a handle and a `*Str` name). Not a security id (the developer's own source).
**Kind:** bug — outside D14's filed table (`t = p`, `t = *p` with p a `*Str`): the `*Str` spelled `*pp`. Its plain-
struct twin (`l = *pp` with pp a `**S`) copies since 6.7.15 (be6522d6b, `_hl_dpp`), but that arm takes a plain struct
only (`_hl_dpp_sid` asks `_dx_plain`).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str): i64 { return str_len(s); }
fn main(): i64 {
    alloc_init();
    var a = str_from("abcde");
    var p: *Str = a;
    var pp: **Str = &p;
    var t: Str = Str { "zz", 2 };
    t = *pp;
    return t.len * 10 + f(t);
}
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < fpp.cyr > fpp && ./fpp; echo $?
22          # t.data = *pp (the header's address), t.len still 2 — 55 is right
```

`var u: Str = *pp; t = u;` exits 55; `t = p` and `t = **pp` exit 55 since D14.

## Root cause

`_asg_dstar` (src/frontend/parse.cyr) reads `*pp` through `_hl_dstar_x(.., pp 1)`: `_hl_dpsid` answers 0 for the
operand `pp` (a `**Str` name is no `*Str`), and the `**S` twin (`_hl_dpp_sid`, parse_decl.cyr) returns 0 for `Str`
(`_dx_plain`), so no copy arm takes the source; `_istr_hop` reads names only.

## Fix direction

Let `_hl_dpp_sid` answer for `Str` when asked by `_asg_dstar` and route it to `_istr_dxa` with the whole `*pp` parsed
(`_hl_dpp` 1: rax = the `*Str`), as the plain struct's copy does. Rows beside tests/tcyr/crossos/inline_str_value.tcyr's
ps_* rows (a local, a global destination, a for step).
