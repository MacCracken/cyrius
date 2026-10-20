# `p = str_from(..);` into a `*P` LOCAL (P not Str) gives no "assigning non-pointer to typed pointer"; the declaration and a `*P` global warn — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 frontend lane (l6716-frontend at 478e4f6cd, x86_64), the
same on the lane's compiler before F5 (11dfa7bff). Noted by the structs-lane triage of
issues/2026-10-18-str-call-into-str-pointer-declaration-or-global-warns-typed-pointer.md ("the LOCAL arm's exemption
(`_asg_ret_sid > 0`, any struct) also silences `lq = mkq()` (a `: Str` call) into a `*P` local") and measured here.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF4) — never 7.x.
**Severity:** Low — a missing warning: the `*P` local is given a `Str` header's address, silently.
**Kind:** bug (diagnostics).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct P { a; b; }
var GP: *P = 0;
fn main(): i64 {
    alloc_init();
    var s: P;
    s.a = 1;
    s.b = 2;
    var p: *P = &s;
    p = str_from("abc");
    GP = str_from("abc");
    var d: *P = str_from("abc");
    return p.b + s.b * 10;
}
syscall(60, main());
```

```
warning:<source>:12:25: assigning non-pointer to typed pointer     # GP = str_from(..)
warning:<source>:13:32: assigning non-pointer to typed pointer     # var d: *P = str_from(..)
```

rc 0, exit 23: `p.b` read the Str's length (3) — p holds the Str header's address — and line 11 (`p = str_from(..)`
into the `*P` local) said nothing.

## Root cause

`_PARSE_STMT_IMPL`'s local arm (src/frontend/parse.cyr, `if ((lt < 0 || GLPTRP(S, idx) == 1) && _asg_ret_sid <= 0)`)
skips the warning for ANY call whose declared return sid is a struct (v6.5.28's "a call whose DECLARED return sid is a
struct IS a typed pointer"), whatever the destination's pointee. Exempting only a call whose return is the pointee
(a `: P` call into a `*P` is copied through it, 6.7.10 B7-1c; a `: Str` into a `*Str` is its address — 6.7.16's
`_tp_call_pointee`) would warn here as the declaration and the global do. A row beside
tests/gates/diagnostics/typed_pointer_warn_sign.sh axis 16.
