# A generic fn's inline-replayed `return` inside a fn that returns a struct by value runs under THAT fn's struct-return class: `fn gpg<T>(): *T { return GPA; }` is refused ("… the 9-16 byte struct `P2` … got `GPA`") — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 struct lane (`l6711-struct` at 3fc1dbbb, before unit S3,
x86_64) and on the installed 6.7.9 and 6.7.10 compilers: identical refusals.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (generics lane, wave 1, unit G1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 struct lane (unit S3), writing a `return gpg<P2>();` row for
issues/archived/2026-10-13-small-struct-return-of-pointer-global-or-call-decision.md.
**Severity:** Medium — valid source refused (loud, no wrong code). The message names a struct the generic never
mentions, at a `return` inside the generic, so the cause is hard to see.
**Affects:** cycc 6.7.9 – the 6.7.11 tree (measured 6.7.9, 6.7.10, 3fc1dbbb); every target (frontend).

## Reproduction

```sh
cat > /tmp/gi.cyr <<'X'
struct P2 { x; y; }
struct P3 { x; y; z; }
struct B8 { v; }
var GS16 = B8 { 5 };
var GPA = 0;
fn gpg<T>(): *T { return GPA; }
fn r(): P2 { var q: *B8 = gpg<B8>(); var t: P2; t.x = q.v; return t; }
fn main(): i64 { GPA = &GS16; var c: P2 = r(); return c.x; }
syscall(60, main());
X
build/cycc < /tmp/gi.cyr > /tmp/gi; echo $?
# 1: error:<source>:6:26: a fn returning the 9-16 byte struct `P2` is returned in two registers, so `return` takes
#    a local of that struct or a call returning it — got `GPA`
```

Expected: compiles, exit 5. Measured variants (each refused at line 6, the generic's `return GPA;`):

| the fn the call sits in | `T` | message |
|---|---|---|
| `fn r(): P2` (16 B) | `B8` | "a fn returning the 9-16 byte struct `P2` … got `GPA`" |
| `fn r(): P2` | `P2` | the same |
| `fn r(): P3` (24 B) | `P2` or `B8` | "struct-return: identifier is not a local" |
| `fn r(): i64` | `P2` | compiles, right value (control) |
| `fn main(): i64` only, `r` not calling it | `P2` | compiles, right value (control) |

The message names the ENCLOSING fn's struct (`P2` with `T = B8`), and the class follows the enclosing fn (pair at 16 B,
retptr at 24 B). Order does not matter: the generic defined below its users, or an `i64` fn making the same call
first, is refused the same. A two-statement body (`{ var r = GPA; return r; }`) compiles, right value. A one-call body
(`return gsel(sizeof(T));`, as tests/tcyr/crossos/generic_ptr_struct_source.tcyr writes it) is refused too when the
enclosing fn is 9-16 B (the leaked pair class diverts its tail call to the pair refusal: "… got `gsel`").

## Root cause

A generic fn is an INLINE candidate (src/frontend/parse_fn.cyr, PARSE_FN_DEF's classification: `_MONOMORPH_OK == 1 &&
GFTP(S, fi) != 0`, at most 2 parameter slots, at most 32 body tokens, no control flow and no `var`), so `gpg<B8>()` is
not called but REPLAYED at the call site (the inline replay, `SIDEP(S, GIDEP(S) + 1)` in parse_fn.cyr). The replayed
`return GPA;` goes through PARSE_RETURN with the CALLER's per-fn state — `_cur_fn_ret_sid` / `_cur_fn_ret_pair` /
`_cur_fn_ret_stash` are r's — so the 9-16 B arm (`_ret_struct_pair` -> `_refuse_pair_return`) or the retptr arm
(`_ret_struct_big`: "identifier is not a local") judges the callee's value against the caller's struct. The
two-statement body is not a candidate (its `var`), which is why it compiles.

## Proposed fix

Find the write (or the unsnapshotted parse) and give the instance its own return state; a row per class (8 / 16 / 24 B
enclosing fn, T a struct and a scalar), the controls above, a mutant RED.
