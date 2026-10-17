# A top-level untyped `var s = (mks());` with a `: Str` call is not routed as a Str — `println(s)` prints the header's bytes, where `var t = mks();` beside it prints the string — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 receives lane (l6714-receives at 7db743ba, after the in-fn
wrapped-Str bite) with compilers built from that tree: x86_64, aarch64 (qemu), cx (cxvm), PE (wine) alike; the lane
base (4495a693) the same.
**Placement:** 6.7.15 — repair 5 (receives lane; filed from the 6.7.14 receives lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Medium — a silent wrong output on valid code: the overload dispatcher takes the cstring base for the
wrapped global and prints the `Str` header's bytes. Workaround: drop the parentheses, or annotate (`var s: Str = (mks());`).
**Discovered:** 2026-10-17, the receives lane (unit R2), while repairing
`issues/2026-10-16-paren-wrapped-str-call-untyped-receive-is-a-word.md`, whose filed surface (its repro, its root cause
in PARSE_VAR's in-fn peek `_ti_inferred_sid`, its rows) is a declaration in a fn. That bite types the wrapped Str in a
fn; at top level an untyped global is routed by a different record, untouched by it.

## Reproduction

In the declaration zone (the same with `alloc_init();` as a first statement before the two declarations):

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/str.cyr"
fn mks(): Str { return str_from("abcde"); }
var s = (mks());
var t = mks();
println(s);
println(t);
syscall(60, 0);
```

```
$ build/cycc < r.cyr > r && ./r
`
`
abcde
```

(x86_64; aarch64 prints an empty line then a backquote, cx `)`, PE three bytes — the header's address bytes as a
cstring.) The unwrapped `t` prints `abcde` on all four.

## Root cause

An untyped top-level global is a word (6.7.13 D6 (b), 6.7.14's D22 (b)); the overload dispatcher routes `println(t)` to
`println_str` through the global's DIAGNOSTIC record (GVDSID, read by `_glob_name_sid`, parse_fn.cyr), written from the
initialiser when it is exactly one call `f(..);` — `_gv_init_call_sid` (the zone's `PARSE_GVAR_REG`) and
`_gv_rhs_call_sid` (PARSE_VAR's global arm after a first statement), both of which want `IDENT (` at the initialiser's
first token. A wrapped call `(mks());` records nothing, so `s` is an untyped word to the dispatcher.

## Proposed fix

Let `_gv_rhs_call_sid` look through a whole wrap (`_pwrap_name` up to the `;`, then the `f(..)` inside ending at the
wrap's `)`), so the wrapped call records its callee as the unwrapped one does; both writers share it. Rows: the repro
above (zone and after a first statement), `((mks()))`, a crossos row on four legs. (Whether the top-level untyped
receive of a STRUCT binds it is 6.7.14's D29 / D30, `issues/2026-10-16-top-level-untyped-struct-call-receive-infers-nothing.md`
— a `Str` handle's routing here is the existing one-call record, not a new binding.)
