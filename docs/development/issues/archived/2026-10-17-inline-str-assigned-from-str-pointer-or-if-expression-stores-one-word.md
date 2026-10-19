# `t = p` / `t = *p` (p a `*Str`) and `t = if (c) { a } else { b }` (Str handles) into an inline `Str` still store one word, where `t = a` copies the header since 6.7.14 — RESOLVED

> ✅ **RESOLVED in v6.7.15** (ST-8, `549746832` — the user's decision D14, 2026-10-18: "A copy of the header p points at"; and ST-9, `9fe6f9860` — the user's decision D15, 2026-10-18: "Keep the one-word store, documented". `_istr_hop` takes a `*Str` local, parameter or global as the copy source a handle is, and `_asg_dstar` asks `_istr_dxa` for `*E` of a `*Str` into an inline `Str`. The filed repro `t = p;` exits 55 (was 22); the table's `t = *p;` exits 55 with no warning (was 22 + "assigning non-pointer to typed pointer"); also a `*Str` global source, `**pp` / `*w.p` / `*gsp()`, wraps, for steps, an inline-global destination, a closure and top level — on x86_64, IR=1, IR=3, DCE, aarch64, cx and PE, and on ecb, ach, pi and cass. The table's if-expression `t = if (c == 1) { a } else { a };` keeps the one-word store (22, with its warning), as D15 decides, documented in the guide's D20 (a) paragraph: assign in each branch. Rows: `frontend/inline_str_value.sh` D14a (the repro verbatim), D14b, D15; `crossos/inline_str_value.tcyr` ps_* (11), R_TOP9 / R_TOP10; mutations RED. Not closed here (filed, 6.7.16): `t = *pp` with pp a `**Str` still stores one word (`2026-10-18-inline-str-from-double-str-pointer-single-deref-stores-one-word.md`), and `h = *p` into a `Str` handle stores the data word (`2026-10-18-str-handle-assigned-str-pointer-dereference-stores-data-word.md`, a decision). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 structs lane (unit S4) on the lane's tree after the D20 (a)
commit (`0807784c`), x86_64; the same before it (c778c981). Frontend: every target alike.
**Placement:** 6.7.15 — repair 5 (structs lane, wave 2, unit S3; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D14 — A copy of the header p points at.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D15 — Keep the one-word store, documented.
**Severity:** Medium — silent: t.data takes the pointer's (or the branch's) word and t.len is left stale (the
6.6.16 pun the user's D20 (a) retired for a `Str` handle source). Not a security id (the developer's own source).
**Kind:** language (decision) — 6.7.14's D20 (a) (issues/archived/2026-10-15-str-handle-into-inline-str-stores-one-word.md)
copies the header a `Str` HANDLE points at into an inline `Str` (a handle local, parameter, global, a `: Str` call or
method, a `Str` field). Its filed surface was the handle; a `*Str` pointer and an if-expression of handles are
`Str`-typed sources outside it, so they keep the one-word store.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str): i64 { return str_len(s); }
fn main(): i64 {
    alloc_init();
    var a = str_from("abcde");
    var p: *Str = a;
    var t: Str = Str { "zz", 2 };
    t = p;
    return t.len * 10 + f(t);
}
var r = main();
syscall(SYS_EXIT, r);
```

```
$ build/cycc < sA.cyr > sA && ./sA; echo $?
22          # t.data = p, t.len still 2; `t = a;` in the same place exits 55 (the D20 (a) copy)
```

| the assignment (same program) | exit | note |
| --- | --- | --- |
| `t = p;` (p a `*Str` local) | 22 | no diagnostic |
| `t = *p;` | 22 | warns "assigning non-pointer to typed pointer" |
| `var c = 1; t = if (c == 1) { a } else { a };` | 22 | warns "assigning non-pointer to typed pointer" |
| control `t = a;` (a `Str` handle) | 55 | the D20 (a) copy |
| control `var t: Str = *p;` (a declaration) | 55 | a copy (a later `a.len = 1` leaves it) |

## Root cause

`_agc_plain_big` (src/frontend/parse.cyr) excludes `Str` by name, so a `*Str` local is no copy operand
(`_agc_handle_local` answers 0 — 6.7.10's decision 6, "a copy through a `*T` copies the struct", skips Str), and
`_asg_dstar` refuses `*p` of a `*Str` (`_dx_plain` excludes Str). 6.7.14's `_istr_hop` / `_istr_call` / `_istr_hcp`
(src/frontend/parse_decl.cyr) take a `Str` handle name, a `: Str` call or method and a `Str` field only; an
if-expression's value is untyped (`_ie_struct_sid` names no handle).

## The question

Should a `*Str` source (`t = p`, `t = *p`) and an if-expression whose branches are `Str` handles copy the header
into an inline `Str`, as D20 (a) made a handle do (and as `var t: Str = *p;` already copies), or keep the one-word
store (documented)?
