# A top-level `var H: Str = gt;` (gt an inline `Str` global) copies the header where the same declaration in a fn binds to it; an untyped top-level `var H = gt;` keeps the `data` word — OPEN

**Status:** 🟡 **OPEN** — a question for the user. Found 2026-10-15 by the 6.7.13 structs lane (unit S4) while landing
D7 (1) (issues/archived/2026-10-12-inline-str-local-passed-to-str-param-wrong-value.md), which makes `var h: Str = gt;` and
`var h = gt;` IN A FN a handle bound to `gt`'s header (no copy). Measured on the lane tree after that bite, x86_64.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane, wave 2, unit S4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D21 — (a); D22 — (b).
**Severity:** Low (annotated: a copy where a bind is the in-fn rule — values agree until one side is written) /
Medium (untyped: `f(H)` reads the string's bytes as the header, silently).
**Kind:** language (decision) — D7 (1) enumerates fn-local shapes; a top-level declaration from an inline `Str`
global was not asked, and 6.7.13 D6 (b) keeps an untyped top-level declaration a plain word.

## Repro

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str) { return str_len(s); }
var gt: Str = Str { "abcdefg", 7 };
var H: Str = gt;
fn main() { H.len = 3; return f(H) * 10 + gt.len; }
var r = main();
syscall(SYS_EXIT, r);
```

`build/cycc` (the lane tree after D7 (1)): exit 37 — `H` is an inline COPY of `gt` (`H.len = 3` leaves `gt.len` 7;
`f(H)` passes `&H`, 3). The same declaration after a first top-level statement (`alloc_init();` above it) also 37.
In a fn, `var h: Str = gt; h.len = 3;` writes `gt.len` (D7 (1): h is a handle to gt's header), so the same lines
moved into `main` give 33.

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str) { return str_len(s); }
var gt: Str = Str { "abcdefg", 7 };
var H = gt;
fn main() { return f(H); }
var r = main();
syscall(SYS_EXIT, r);
```

exit 0 — an untyped top-level `var H = gt;` is `gt`'s first word (the `data` pointer; D6 (b): "at top level nothing
changes"), and `f(H)` reads the string's bytes as the header. In a fn, `var h = gt;` is a handle to gt's header
(D29 + D7 (1)): 7.

## Root cause

A top-level struct copy-init from a struct global is `_gci_toplevel` (after the first statement) and the declaration
zone's replay (EMIT_GVAR_INITS / `_gvi_*`): both register an inline global and copy the bytes, with no `Str` arm.
D7 (1)'s bind (`_istr_src` / `_istr_decl`, src/frontend/parse_decl.cyr) runs only in a fn (`_try_struct_copy_init`
hands a top-level declaration to `_gci_toplevel` first). An untyped top-level declaration never asks `_uci_ps`.

## The question

At top level, `var H: Str = gt;` (a) binds a handle global (GVPM 1, 8 bytes) to gt's static header, as in a fn, or (b)
stays a copy; and `var H = gt;` (a) is that same handle, or (b) keeps the word (D6 (b) as decided for other structs).
