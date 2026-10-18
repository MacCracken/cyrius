# `var s = (mks());` with a `: Str` call binds an untyped word — `println(s)` prints the header's bytes, `s.len()` is refused — RESOLVED

> ✅ **RESOLVED in v6.7.14** (RC-5, `7db743ba` — no decision needed: the wrap is transparent (guide § Parentheses): in a fn, `var s = (mks());` — any number of parentheses — with `mks` declared `: Str` is a `Str`, as `var s = mks();` is (`_var_rhs_wsid` returns the `Str` sid; the wrapped forms compile byte-identical to the unwrapped one). The filed repro prints `abcde` twice (it printed the header's bytes) and its `s.len() * 10 + t.len()` form exits 55 (it was refused "no struct type in scope for 's'"), on x86_64, aarch64, cx and PE. Rows: `crossos/struct_receive_paren_call.tcyr` ws, ws_2, ws_fn, ws_ov, ws_cl, ws_u (also on cass and pi); `frontend/struct_receive_inference_checked.sh` WS0 (the repro verbatim, `docs/development/issues/repros/2026-10-16-paren-wrapped-str-call-untyped-receive-is-a-word.cyr`, its stdout read) – WS2; mutation N34 RED. Not closed here (filed, 6.7.15; outside the filed surface, a declaration in a fn): at TOP LEVEL `var s = (mks());` still prints the header's bytes (`2026-10-17-top-level-wrapped-str-call-global-prints-header-bytes.md`). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 receives lane (unit R1, after its 8 B wrapped-receive
commit) with compilers built from that tree: x86_64, aarch64 (qemu), cx (cxvm), PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives + multi-value lane, wave 2, unit R2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Medium — a silent wrong output on valid code (`println(s)` takes the integer / cstring overload and
prints the Str header's bytes); the method form is refused loudly. Workaround: drop the parentheses, or annotate
(`var s: Str = (mks());`).
**Discovered:** 2026-10-16, the receives lane, while repairing
`issues/archived/2026-10-14-paren-wrapped-call-untyped-receive-8b-call-and-16b-method.md` (the 8 B half), whose filed surface
is a struct of 8 B or less; a `Str` is 16 B and was left as the brief's plan says ("over 8 B the receive takes it").

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/str.cyr"
fn mks(): Str { return str_from("abcde"); }
fn main(): i64 { alloc_init(); var s = (mks()); println(s); var t = mks(); println(t); return 0; }
syscall(60, main());
```

```
$ build/cycc < r.cyr > r && ./r
P
`
abcde
```

The wrapped binding prints two garbage lines (the overload chosen for an untyped word); the unwrapped one prints
`abcde`. With `return s.len() * 10 + t.len();` instead the program is refused on all four targets:
`error:<source>:6:76: no struct type in scope for 's'; a method call needs its struct declaration`.

## Root cause

PARSE_VAR's untyped peek (`src/frontend/parse_decl.cyr`, `_ti_inferred_sid`) types `var t = mks();` as `Str`
through `_var_rhs_csid` (v5.10.4: a `Str` handle is typed so `println` dispatches to `println_str`). The wrapped
form goes to `_var_rhs_wsid` (6.7.13), which returns a struct of 8 B or less only; over 8 B the receive
(`_rcv_peel`) gives a 9-16 B struct its pair storage and type — but it skips a `Str` (`_look_sid != _STR_SID`), so
the wrapped `Str` gets neither. The wrap is transparent everywhere else (guide § Parentheses).

## Proposed fix

`_var_rhs_wsid` also returns `_STR_SID(S)` when the wrapped call returns `Str` (the unwrapped peek's result). Rows
beside tests/tcyr/crossos/struct_receive_paren_call.tcyr's w8 rows: `println`-free value checks (`s.len()`,
`str_len(s)`, an overload probe) wrapped and double-wrapped, on the four targets.
