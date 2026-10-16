# `*pp` of a `pp: **T` is an untyped word, not a `*T`: `*pp + 1` steps one BYTE, and `var q: *T = *pp;` warns "assigning non-pointer to typed pointer" — OPEN

**Status:** 🟡 **OPEN** — a decision for the user (it changes what `*pp + n` computes). Measured 2026-10-13 on the
6.7.11 callargs lane after unit A2: for a `**i64` LOCAL (compiling since 6.6.17) and a `**i64` PARAMETER (compiling
since 6.7.11, `2026-10-10-param-type-annotation-reads-one-token.md`) alike, `*(*pp + 1)` reads 8 bytes at one BYTE past
the pointee (exit 1 / 2 below, x86_64 and aarch64), and `var q: *i64 = *pp;` draws "assigning non-pointer to typed
pointer" — the filed repro (b) of the param-annotation issue (`fn f(p: **i64): i64 { var q: *i64 = *p; return *q; }`)
exits 42 with that warning.
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D9 — (a).
**Discovered:** 2026-10-13, the 6.7.11 callargs lane (unit A2), running the param-annotation repro (b).
**Severity:** Low. A spurious warning on correct code, and a byte step where an element step is meant; `pp + 1`
itself steps 8, as the guide says. Workaround: bind it first (`var q: *i64 = *pp;`, warning and all) and step `q`.
**Affects:** every target (frontend typing); `**T` / `***T` of any T, locals, globals and parameters.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
fn second(pp: **i64): i64 { return *(*pp + 1); }
fn main(): i64 {
    var a: i64[2];
    store64(&a, 5);
    store64(&a + 8, 42);
    var p: *i64 = &a;
    var pp: **i64 = &p;
    var q: *i64 = *pp;          # warns: assigning non-pointer to typed pointer
    if (*(q + 1) != 42) { return 3; }
    if (*(*pp + 1) != 42) { return 1; }   # a `**i64` local: `*pp + 1` steps one byte
    if (second(pp) != 42) { return 2; }   # a `**i64` parameter (6.7.11): the same
    return 0;
}
var rc = main();
syscall(60, rc);
```

```
warning:<source>:9:22: assigning non-pointer to typed pointer
x86_64 exit 1, aarch64 exit 1 (want 0); without the local row: exit 2
```

## Root cause

A dereference's result carries no pointer scale: `*p` through a `*i64` is "the untyped word" (the guide's *Pointers*:
"`*p` through a `*f64` is the untyped word ... `**pp` ... read and written 8 bytes as before"), and the step word of a
`**T` slot (`_mark_ptr_param` / `_ptr_annot`: 8, kind 0) says only that `pp + n` steps a pointer — nothing records that
the pointee is a `*T` with step sizeof(T). So `*pp` is a plain word (GPSC 0): `+ 1` adds one, and the declaration's
check (`PARSE_VAR`: `pscale > 0`, `expr_ps == 0`) warns.

## The question

Should `*pp` of a `**T` be a `*T` (its step sizeof(T); `var q: *T = *pp;` silent; `*pp + 1` one element)? That changes
what `*pp + n` computes in code that compiles today (a `**T` local), so it is the user's call; the alternative is to
document `*pp` as an untyped word and drop the warning for a `**T` source.
