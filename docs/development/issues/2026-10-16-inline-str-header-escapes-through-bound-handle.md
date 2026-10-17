# An inline `Str`'s header escapes its frame through a handle bound to it: `var h: Str = t; return h;` / `G = h` compile with no refusal and the returned handle dangles — OPEN

**Status:** 🟡 **OPEN** — a decision (refuse, or document). Found 2026-10-16 by the 6.7.13 structs lane's review
(unit i11, probe s20), re-measured by the lane's fix step on the lane tree after the review fixes (95516c2f).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane, wave 2, unit S4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D23 — (b).
**Severity:** Medium — silent: a read through a dead frame, whose value depends on what the stack held (7 by luck on
three targets here, 0 on aarch64).
**Kind:** language (decision) — beyond D7 (1)'s filed surface (issues/2026-10-12-inline-str-local-passed-to-str-param-
wrong-value.md, the user's decision D7 (1), 2026-10-15).

## Repro

```cyrius
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str) { return str_len(s); }
fn smash(): i64 { var a: i64[32]; var i = 0; while (i < 32) { a[i] = 0; i = i + 1; } return a[3]; }
fn mk(): Str { var t: Str = Str { "abcdefg", 7 }; var h: Str = t; return h; }
fn main() { var h = mk(); smash(); return f(h); }
var r = main();
syscall(SYS_EXIT, r);
```

Compiles clean (no error, no warning) on x86_64, aarch64, cx and PE. Exit: x86_64 7, aarch64 (qemu) 0, cx 7, PE (wine)
7 — `h` holds `&t`, the header in mk's frame, which `smash()` reuses.

The global twin: `var G: Str = 0; fn mk() { var t: Str = Str { "abcdefg", 7 }; var h: Str = t; G = h; return 0; }
fn main() { mk(); smash(); return f(G); }` — clean, and the same exits (7 / 0 / 7 / 7).

Controls (refused by name since D7 (1), tests/gates/frontend/inline_str_value.sh X1 / X4): `return t;` from a fn
returning `Str` ("cannot return the inline Str 't' from a fn returning Str - its header lives in this frame and would
dangle (return a handle: str_new(data, len))") and `G = t;` ("cannot store the inline Str 't' into a global - ...").

## Root cause

D7 (1) makes `var h: Str = t;` (and `var h = t;`, `h = t`) bind h to t's header (`&t`, `_istr_decl` / `_istr_asg`,
src/frontend/parse_decl.cyr), and refuses the escapes only where the value is t's own name (`_istr_ret`, `_istr_asg`,
`_istr_fsc`, `_istr_lit`, `_istr_dsto` all test `_istr_at` — the expression is the bare name of the inline `Str`). A
handle that holds `&t` is an ordinary `Str` handle afterwards: nothing records that it points into this frame, as
nothing records it for `var p = &t;` (cyrius does not track an address-of either).

## The question

(a) refuse the bound handle's escapes too — record "bound to a frame's inline `Str`" on the handle slot when D7 binds
it (`var h: Str = t;`, `var h = t;`, `h = t`) and refuse `return h;` / `G = h` / a `Str` field store / `*ps = h` as
`return t;` is (flow-insensitive, as the float flag is; a later `h = str_new(..)` would have to clear it); or (b)
document it beside `&t`: the bound handle is the header's address, and it dangles when the frame dies, as `&t` does.
