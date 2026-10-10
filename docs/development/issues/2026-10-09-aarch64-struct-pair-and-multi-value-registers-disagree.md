# aarch64: a 16-byte struct return travels in x0:x1, a multi-value return in x0:x2 — where the two meet, the second word is lost — RESOLVED

> ✅ **RESOLVED in v6.7.7** (6f27b485; CHANGELOG [6.7.7]) every 9-16 B struct return on aarch64 carries its high word in BOTH x1 (the struct pair) and x2 (the multi-value slot): `EFLLOAD_STRUCT_INT_PAIR` writes x2 too and a struct fn's `return (a, b[, c]);` / `ret2` land through `_mret_land` (`ESTRUCT_PAIR_HI_SYNC`, `mov x1, x2`; a no-op on x86 / cx), so every row of the table below gives the x86 value on qemu, pi and ecb — gate `codegen/struct_pair_multi_value_crossing.sh`, `crossos/struct_pair_multi_value_crossing.tcyr`.

**Status:** ✅ **RESOLVED in v6.7.7** — see the banner above (filed OPEN 2026-10-09 against 6.7.6 @ e44470b7:
repro A 55 and repro B 50 on aarch64 / pi, 55 / 250 on ecb, where x86_64 and PE gave 56).
**Placement:** 6.7.7 — shipped (the integration lane "aarch64 registers", decisions 2026-10-09).
**Discovered:** 2026-10-08 by the 6.7.7 B4 (tuples) planners' cross-target probes (u1, t6); filed 2026-10-09 by the
B4 lane (bite T0).
**Severity:** High — a silent miscompile of valid source on aarch64 (Linux, macOS arm64, native), correct on x86_64.
**Affects:** cycc 6.7.6 (measured); the two conventions date from v5.10.45 (the int-class struct pair) and the
aarch64 multi-value return, so every version since is likely affected (speculation — not bisected).

## Summary

cyrius has two ways to hand back two machine words, and on x86_64 they use the same registers:

| Convention | x86_64 / PE / Mach-O x86 | aarch64 (ELF, Mach-O arm64, native) | cx |
|---|---|---|---|
| a 9–16 B struct returned by value (`E*_STRUCT_INT_PAIR`) | rax : rdx | **x0 : x1** | refused |
| a multi-value return (`return (a, b);`, `ret2`, `EMOVRDXRAX` / `EMOVRA_RDX`) | rax : rdx | **x0 : x2** | r0 : r4 |

The frontend lets the two meet in both directions, and on x86_64 that is correct by coincidence. On aarch64 the
second word is read from the wrong register:

1. **Multi-value producer, struct consumer.** A fn declared `: P` (P is 16 B) whose body says `return (x, x + 1);`
   or `ret2(x, x + 1);` puts the second word in x2. The caller's `var p: P = mk(5);` or `p = mk(5);` stores x0:x1,
   so `p.b` is whatever x1 held (repro A: `p.b` = 5 where 6 is right).
2. **Struct producer, multi-value consumer.** A fn declared `: P` that returns a P local loads x0:x1. A destructure
   `var a, b = mk(5);` reads its second value from x2 (repro B: `b` = 0 on pi, garbage on ecb). The destructure
   accepts a struct callee over 8 B by design (`_dt_arity_check`: "a struct over 8 B … can carry a second word"),
   and so does `rethi()`.

No diagnostic on any target. The x86_64 result is the one the source means.

## Reproduction

Repro A (u1) — the multi-value return in a struct-returning fn:

```cyrius
struct P { a; b; }
fn mk(x): P { return (x, x + 1); }
fn main(): i64 { var p: P = mk(5); return p.a * 10 + p.b; }
var r = main(); syscall(60, r);
```

Repro B (t6) — the destructure of a struct-returning call:

```cyrius
struct P { a; b; }
fn mk(x): P { var p: P; p.a = x; p.b = x + 1; return p; }
fn main(): i64 { var a, b = mk(5); return a * 10 + b; }
var r = main(); syscall(60, r);
```

```sh
cat src/main_aarch64.cyr | build/cycc > /tmp/cc_a64 && chmod +x /tmp/cc_a64
cat repro.cyr | /tmp/cc_a64 > /tmp/r && chmod +x /tmp/r && qemu-aarch64 /tmp/r; echo $?    # A: 55   B: 50
cat repro.cyr | build/cycc  > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?                  # A: 56   B: 56
```

Expected 56 on every target. Measured (6.7.6 @ e44470b7):

| Shape | x86_64 | aarch64 (qemu) | pi | ecb | cx | PE (wine) |
|---|---|---|---|---|---|---|
| A — `return (x, x + 1);` in a `: P` fn, `var p: P = mk(5);` | 56 | 55 | 55 | 55 | refused | 56 |
| B — `var a, b = mk(5);` from a `: P` fn returning a P local | 56 | 50 | 50 | 250 | refused | 56 |
| A with `ret2(x, x + 1);` in place of `return (…)` | 56 | 55 | | | refused | 56 |
| A with the assignment `p = mk(5);` into an existing P | 56 | 55 | | | refused | 56 |
| B at top level, in the declaration zone (`var a, b = mk(5);` before the first statement) | 56 | 50 | | | refused | 56 |
| B at top level, after the first statement | 56 | 50 | | | refused | 56 |
| `mk(5); var b = rethi();` (expected 6) | 6 | 0 | | | refused | 6 |

## Root cause

- The struct-pair emitters use x0:x1 on aarch64: `EFLLOAD_STRUCT_INT_PAIR` / `EFLSTORE_STRUCT_INT_PAIR`
  (`src/backend/aarch64/emit.cyr:3055` / `:3077`).
- The multi-value emitters use x2 on aarch64: `EMOVRDXRAX` / `EMOVRA_RDX` (`src/backend/aarch64/emit.cyr:402-403`;
  x1 is the backend's rcx peer, which is presumably why the multi-value return moved to x2 — speculation).
- The crossings in the frontend:
  - producers of the multi-value convention: PARSE_RETURN's `return (a, b)` arm (`src/frontend/parse_fn.cyr:1071`;
    arity 3 at :1055) and the `ret2` builtin (`src/frontend/parse_expr.cyr:4790`). Neither looks at whether the fn
    is declared to return a 9–16 B struct (`_cur_fn_ret_pair`).
  - consumers of the struct pair: the call receive `EFLSTORE_STRUCT_INT_PAIR` (`parse_fn.cyr:2764`, `:2978`).
  - producers of the struct pair: `EFLLOAD_STRUCT_INT_PAIR` (`parse_fn.cyr:1942`, `:1958`).
  - consumers of the multi-value convention: the destructure drains (`src/frontend/parse_decl.cyr:5209` fn scope,
    `:5247` top level, `:4499` the declaration-zone replay) and `rethi()` (`parse_expr.cyr:4805`).

## Proposed fix

Bridge at the crossings, so neither convention changes:
- a 9–16 B struct-returning fn (`_cur_fn_ret_pair == 1`) that returns through the `return (a, b)` arm or `ret2`
  moves the second word into the struct pair's register before the epilogue (aarch64 `mov x1, x2`; nothing on x86,
  where both are rdx);
- a multi-value consumer (the three destructure drains and `rethi()`) whose callee returns a 9–16 B struct reads
  the second word from the struct pair's register (aarch64 x1).

One backend emitter pair would carry this (no-op on x86 / PE / Mach-O x86, the x1 move on aarch64; cx follows
whatever register the cx issue below chooses for the pair's high word). Alternative: move the aarch64 struct pair to
x0:x2 — only if no 16 B struct crosses an external C ABI boundary, which AAPCS64 fixes at x0:x1 (speculation, not
checked). A gate row per crossing in the table above, run on aarch64 (qemu locally; pi and ecb at the release gate).

Related:
- [`2026-10-08-cx-16b-struct-return-refused.md`](2026-10-08-cx-16b-struct-return-refused.md) — cx has no struct pair
  at all yet; its proposed fix puts the high word in r4, the multi-value peer, which would avoid this split on cx.
- The 6.7.7 tuples (B4) do not widen this: a tuple return is the multi-value convention, never the struct-pair
  class, and the tuple capture (`var t: (i64, i64) = f();`, `t = f();`) and the new multi-value assignment
  `a, b = f();` refuse a struct- or vector-returning callee by name. `a, b = f();` took one until the B4 review
  (2026-10-09) — a new crossing site: a 16 B struct callee gave 59 on x86 and PE and 50 on aarch64 (qemu), a 24 B one
  wrong values everywhere; refused since (tuple_checked.sh R19i-R19o, R19m on the aarch64 compiler). The pre-existing
  destructure `var a, b = mk(5);` (repro B) still takes a struct callee and is this issue's to fix.

## Consumer-side workaround

Return a 16 B struct by naming a local (`var p: P = …; return p;`) and receive it into a struct (`var p: P = mk(5);`
or `q = mk(7);`) — the struct pair on both sides is consistent (exits 64 on x86_64, aarch64 and PE for
`p.a * 10 + p.b + q.b`). Do not destructure a struct-returning call, and do not `return (a, b);` or `ret2` from a
struct-returning fn.
