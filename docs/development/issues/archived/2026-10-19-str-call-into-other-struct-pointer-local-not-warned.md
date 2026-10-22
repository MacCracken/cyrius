# `p = str_from(..);` into a `*P` LOCAL (P not Str) gives no "assigning non-pointer to typed pointer"; the declaration and a `*P` global warn — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FF-21, `7bab85ee5`, with FF-23 `ff48c4449` and FF-24 `1af546597` — no decision needed (a fix to what the source says; a warning only). Into a `*T` local or `p: *T` parameter the value is typed as one whole primary (`_tpv_sid`, src/frontend/parse.cyr) and exempt only when it is T; a struct call into a handle stays a quiet rebind. The filed repro warns at 11:24 (the `*P` local), 12:25 and 13:32 (it warned at the last two only) and still exits 23; a `p: *P` parameter, `q = str_from(..)` into a `*i64` and `h = mkq()` / `h = mkh().n` / `h = str_from(..) + 0` into a `*Str` warn too; a `: Str` call / field / method into a `*Str` and any struct call into a handle stay quiet. FF-24: a classic-for step into a `*T` warns as the statement does (6.7.13's D18 (a)). One corpus test gains a warning (struct_receive_paren_call.tcyr:423), its binary unchanged. Rows: tests/gates/diagnostics/typed_pointer_warn_sign.sh axis 16 SC5 (the filed repro verbatim) – SC7 and axis 17 FS1 – FS3 on five legs; mutants RED. Staged beside it (the user's call): a struct result assigned into a `Str` handle local, and `var p: *P = s;` from an inline struct local, compile and SIGSEGV. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 frontend lane (l6716-frontend at 478e4f6cd, x86_64), the
same on the lane's compiler before F5 (11dfa7bff). Noted by the structs-lane triage of
issues/archived/2026-10-18-str-call-into-str-pointer-declaration-or-global-warns-typed-pointer.md ("the LOCAL arm's exemption
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
