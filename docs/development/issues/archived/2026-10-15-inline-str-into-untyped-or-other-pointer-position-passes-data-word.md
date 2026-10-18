# An inline `Str` where no `Str` value is taken — an untyped parameter (`h.eq(t)`), `fncall1(&f, t)` / `callptr(&f, t)`, a `*Str` local, a tuple element, an if-expression branch — still passes its `data` word — RESOLVED

> ✅ **RESOLVED in v6.7.14** (ST-13, `11dc74b46`: the user's decision D18 (c), 2026-10-16, "only where a type says Str". `lib/str.cyr` types `Str_eq` / `Str_cat`'s `other`, `Str_contains`' `needle`, `Str_starts_with`'s `prefix` and `Str_ends_with`'s `suffix` `Str`. The filed `h.eq(t)` is 1 on x86_64 / IR=1 / IR=3 / DCE / aarch64 / cx / PE (was 0), and `h.cat(t)` / `h.contains(t)` / `h.starts_with(t)` / `h.ends_with(t)` read t. A string literal there is passed as a `Str`, so `h.eq("abc")` / `h.contains("cde")` are 1. A handle argument builds byte-identical. `var p: *Str = t;` takes t's header as a `p: *Str` parameter does (`str_len(p)` 7, was 0), and `var p: *Str = gt;` is no longer warned; ST-14 adds the declaration-zone twin. By the decision, `fncall1` / `callptr` / `vec_push` / a tuple element / an untyped if-expression branch keep the data word (pinned). Rows: `inline_str_value.tcyr` `q_*` and `R_TOP4`; `inline_str_value.sh` D18a (the filed repro verbatim), D18b, D18c, K9, CMP; mutations e1 - e4 RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — a question for the user. Found 2026-10-15 by the 6.7.13 structs lane (unit S4) while landing
D7 (1) (an inline `Str` is its header's address wherever a `Str` value is taken,
issues/archived/2026-10-12-inline-str-local-passed-to-str-param-wrong-value.md). Measured on the lane tree after that bite
(x86_64; the positions are frontend shapes, the same on every target).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane, wave 2, unit S4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D18 — (c).
**Severity:** Medium — silent: the callee reads the string's bytes as the header (`h.eq(t)` 0 where 1 is right).
**Kind:** language (decision) — D7 (1) covers the positions that take a `Str` VALUE (a `Str` / `*Str` parameter, a
`Str` declaration, an assignment into a `Str` handle; refusals for `return t;` from a `: Str` fn and stores into a
`Str` global / field / through a `*Str`). These positions take no `Str` value by their type, so they keep the
pre-6.7.13 word: whether the bare name of an inline `Str` is its header's address there too is not decided.

## Repro

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/fnptr.cyr"
fn f(s: Str): i64 { return str_len(s); }
fn main() {
    alloc_init();
    var t: Str = Str { "abcdefg", 7 };
    var h = str_from("abcdefg");
    return h.eq(t);          # Str_eq(self, other): `other` is untyped
}
var r = main();
syscall(SYS_EXIT, r);
```

`build/cycc` (the lane tree after D7 (1)): exit 0 — `Str_eq` (lib/str.cyr, `fn Str_eq(self, other)`) forwards the
untyped `other` to `str_eq(a: Str, b: Str)`, which reads `t`'s `data` word as the header. Want 1 (as `h.eq(&t)`).

The same program with the `return` replaced (each exits 7 when the header's address is passed):

| shape | exit |
|---|---|
| `return h.eq(t);` — a method's untyped parameter (every `Str_*` method's `other`) | 0 (want 1) |
| `return fncall1(&f, t);` | 0 |
| `return callptr(&f, t);` | 0 |
| `var p: *Str = t; return str_len(p);` — a `*Str` local | 0 |
| `var v = vec_new(); vec_push(v, t); return f(vec_get(v, 0));` — an untyped stdlib parameter | 0 |
| `var x = (t, 1); return f(x.0);` — a tuple element (an i64) | 0 |
| `var c = 1; return f(if (c == 1) { t } else { h });` (h = `str_from("zz")`) — an if-expression branch | 122 |
| control: `return f(t);` (D7 (1)) | 7 |
| control: `fn fp(p: *Str) { return str_len(p); }` … `return fp(t);` (D7 (1): the parameter records `Str`) | 7 |

## Root cause

D7 (1) is keyed on the destination's type (`_istr_*`, src/frontend/parse_decl.cyr): an argument whose parameter
records `Str` (`_sarg_byval_small`), PARSE_VAR's `Str` declaration, an assignment into a `Str` handle, a `: Str`
return, a `Str` field, a `*Str` dereference store. Every other consumer parses the bare name as the factor does for
any inline struct — its first word (the `data` pointer). The fn-pointer intrinsics' arguments are untyped, the
`Str_*` methods take `other` untyped, an if-expression of struct branches is a struct value only for a declared
struct type (`_ie_struct_sid`), and a tuple element is an i64 slot.

## The question

For an inline `Str` in a position that takes no `Str` value by its type: (a) its bare name is its header's address
there too (the option's title read literally: then an untyped store — `G = t` with an untyped `G`, `store64(p, t)`,
an untyped fn's `return t;` — can carry a frame's address out, and would need the D7 refusals or none); (b) it keeps
the word (today, and what every other inline struct does in an untyped position); or (c) the `Str_*` methods'
`other` / `self` parameters are typed `Str` (a stdlib change that makes `h.eq(t)` a D7 position), with (b) elsewhere.
