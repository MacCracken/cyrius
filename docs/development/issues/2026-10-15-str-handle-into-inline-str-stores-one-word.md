# `t = a;` with `t` an inline `Str` and `a` a `Str` handle stores the handle word into `t.data` (a pun), where `t = u` between two inline `Str`s copies the header — whether `var t: Str;` (no initialiser) joins D7 (1) waits on it — OPEN

**Status:** 🟡 **OPEN** — a question for the user. Found 2026-10-15 by the 6.7.13 structs lane (unit S4): landing D7
(1) (issues/2026-10-12-inline-str-local-passed-to-str-param-wrong-value.md) on every inline `Str` local — the
uninitialised `var t: Str;` included — turned tests/tcyr/crossos/struct_ptrmode_assign_copy.tcyr's 6.6.16 row "the
inline Str pun keeps the handle" red (got 16, expected 5). The lane's review (2026-10-16) found the widening past D7
(1)'s wording (`var t: Str = Str { .. }`); the review fix (structs lane, 2026-10-16) keeps the bare `var t: Str;` —
and a copy of it — outside D7 (1) until this question is answered: the pinned row is green unedited again. Measured
on the lane tree after the review fix, x86_64 (the cross values as noted).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane; filed from the 6.7.13 structs lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Medium — the answer decides what three shapes compute; one of them (row 3) reads a stale frame word
silently on the lane.
**Kind:** language (decision) — 6.6.16 C2 copies a struct a handle points at into an inline struct (`q = a`), with
`Str` / `Result` / `Option` / `Tagged` excluded by name ("heap handles ... every assignment rebinds"); an inline `Str`
cannot be rebound, so the excluded assignment stores one word into its first field.

## Repro

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn main() {
    alloc_init();
    var a = str_from("abcde");
    var t: Str;
    t = a;
    return str_len(t);
}
var r = main();
syscall(SYS_EXIT, r);
```

Through 6.7.12 and on the lane after the review fix: exit 5 — `t = a` stores `a` (the header's address) into
`t.data` and leaves `t.len` the frame's old bytes; `str_len(t)` takes t's first word, which is `a` itself (the pun the
6.6.16 row pins). With D7 (1) widened to the bare declaration (the lane before the review fix) `str_len(t)` passed `&t`
and read `t.len`: 0 on x86_64 / aarch64 / cx / PE (the tcyr row read 16).

Control: `var u: Str = Str { "abcde", 5 }; var t: Str; t = u; return str_len(t);` exits 5 — between two inline
`Str`s the assignment copies the 16-byte header (`_try_aggregate_copy_assign`).

## The rows the answer decides (moved here from the lane's tests by the review fix)

1. tests/tcyr/crossos/inline_str_value.tcyr's former `b_bare`: `var t: Str; t.data = "abc"; t.len = 3; return f(t);`
   (`fn f(s: Str): i64 { return str_len(s); }`) — 3 if the bare declaration is an inline `Str` under D7 (1) (its
   header's address); 0 now (f gets t's first word, the "abc" pointer, as the header — as through 6.7.12).
2. tests/gates/frontend/inline_str_value.sh's former X3: `fn mk(): Str { var t: Str; t.data = "abc"; t.len = 3;
   return t; }` — refused by D7 (1)'s "cannot return the inline Str 't' from a fn returning Str ..." if the bare
   declaration joins it; compiles now and returns the first word (as through 6.7.12).
3. A pun copied into a LITERAL-declared inline `Str`: `var t: Str; t = str_from("hello"); var h: Str = Str { "zz", 2
   }; h = t; return str_len(h);` — 5 through 6.7.12 (h's first word, `a`); on the lane (before and after the review
   fix) h is a D7 (1) `Str` (its declaration is a literal), `h = t` copied t's half-written header, and `str_len(h)`
   reads t's never-written length: 0 on x86_64 (frame bytes). Option (a) below makes it 5 again; (c) keeps the stale
   length.

## Root cause

`_agc_plain_big` (src/frontend/parse.cyr) excludes `Str` by name, so a `Str` handle is no copy-assign operand
(`_agc_handle_local` answers 0) and `t = a` falls to the one-word store into `t`'s first slot.

## The question

`t = a` (inline `Str` ← `Str` handle, or a `Str`-returning call): (a) copies the 16-byte header `a` points at into
`t`, as every other struct does (6.6.16 C2) and as `t = u` between inline `Str`s already does — then the bare `var t:
Str;` can join D7 (1) (rows 1 and 2 as listed, row 3 gives 5, the pun row reads 5 through t's own header); (b) is
refused by name (an inline `Str` takes only an inline `Str` or a literal); or (c) stays the one-word store, and the
bare declaration stays outside D7 (1) (`_istr_bare`, parse_decl.cyr).
