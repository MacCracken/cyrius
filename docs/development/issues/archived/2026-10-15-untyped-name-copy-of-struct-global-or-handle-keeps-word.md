# An untyped `var q = G;` (a struct global) or `var q = h;` (a handle) in a fn still binds a word — does D29's typed copy reach them? — RESOLVED

> ✅ **RESOLVED in v6.7.13** (ST-13, `44ab2052`: the user's decision D6 (b), 2026-10-15, as the question was put to the user — "the global copies; the handle keeps the word" (this file's own option list letters the choices differently: its (b), a by-name refusal of `q.y`, is not what was chosen). An untyped `var q = G;` in a fn, G an inline struct global, is a copy of G as `var q: P = G;` is: the filed repro 1 exits 4 (was refused "no struct type in scope for 'q'") and repro 2 exits 4 (was 139 / aarch64 139 / cx 1 / PE 5) on x86_64, aarch64, cx and PE, at every size, wrapped, in a fn and inside a closure. Repro 3 (`var q = h;`, a handle) keeps the word and is still refused "no struct type in scope for 'q'", as decided; a handle global and a local or captured handle shadowing G alike; top level unchanged. Rows: `crossos/untyped_struct_name_copy.tcyr` 26 → 46 rows, `closure_captured_slice_fields.sh` Q10-Q18 (Q10 / Q11 the filed repros 1 and 2 verbatim), QK7-QK10, UK1-UK3 (UK1 repro 3); mutations RED. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — a question for the user. Found 2026-10-15 by the 6.7.12 fixfirst lane (unit X2) while landing
D29 (a) (`var q = p;` of a fn-local struct value is a typed copy), measured on the lane tree (8d7bd6b1, x86_64).
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D6 — (b).
**Severity:** Low — a loud refusal (`q.y`) or a documented fault (`take(q)` of a word into a by-value struct
parameter); no silent wrong value.
**Kind:** language (decision).

## What D29 decided, and what it left

D29 (the user, 2026-10-15): "Does an untyped `var q = p;` (p a fn-local struct VALUE) declare q a copy of p's struct
type, as `var q: P = p;` does?" — (a) yes. The fix (`_uci_ps`, src/frontend/parse_decl.cyr) takes exactly that
scope: an inline struct local, a by-value struct parameter, a closure's captured copy of one. Two neighbouring name
sources keep the word, because the question named neither:

1. **A struct GLOBAL named in a fn** — `var q = G;` with `var G: P = P { 3, 4 };`. The annotated `var q: P = G;`
   copies (6.6.5).
2. **A handle** (a pointer-mode struct local, `var h: P = alloc(16);`) — `var q = h;`. The annotated `var q: P = h;`
   rebinds (a second handle to the same struct, 6.6.5 / the 6.7.10 handle line).

## Repro

```cyrius
include "lib/syscalls.cyr"
struct P { x; y; }
var G: P = P { 3, 4 };
fn main(): i64 {
    var q = G;
    return q.y;
}
syscall(60, main());
# error:<source>:6:15: no struct type in scope for 'q'; a '.field' access needs its struct declaration (missing include?)
```

```cyrius
include "lib/syscalls.cyr"
struct P { x; y; }
var G: P = P { 3, 4 };
fn tk(a: P): i64 { return a.y; }
fn main(): i64 {
    var q = G;
    return tk(q);
}
syscall(60, main());
# exit 139 (q is G's first word, 3, passed as the struct's address — the guide's "an argument that is
# not a struct faults there"); with `var q = p;` from a LOCAL p this is 4 since D29
```

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct P { x; y; }
fn main(): i64 {
    alloc_init();
    var h: P = alloc(16);
    h.x = 3; h.y = 4;
    var q = h;
    return q.y;
}
syscall(60, main());
# error:<source>:9:15: no struct type in scope for 'q'; ...   (q is the heap address, an untyped word)
```

## Root cause

`_uci_ps` answers only for `FINDLOCAL` hits that are inline (GLAGG) or address-passed parameters, and for captures
with words or a captured address-passed parameter; a global (`FINDVAR`) and a non-inline, non-parameter local (a
handle) return 0, so PARSE_VAR keeps its scalar init (the first word / the address).

## Options (the user's)

- (a) Extend D29: `var q = G;` in a fn is a typed copy (as `var q: P = G;`), and `var q = h;` binds q as a handle of
  P (as `var q: P = h;`) — `q.y` reads G's copy / h's struct. Helper: `_uci_ps` gains a global rung
  (`_sci_global_src`'s inline-global test) and a handle rung (GLAGG 0, not a parameter, not a `*T`).
- (b) Keep the word and refuse `q.y` by name ("q is an untyped copy of G's first word - annotate it: `var q: P = G;`").
- (c) Keep as is (the guide § untyped bindings already lists both as unchanged).
