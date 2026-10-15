# The stub scan's struct-carrier table (`_gcr`) holds 64 entries per generic and drops the rest without a word — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 by the 6.7.11 genfe review on the lane tree (l6711-genfe, the carrier-field
fix ed9456c1). The drop is loud (a parse error), but its cause is unnamed.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 genfe review) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 genfe review.
**Severity:** Low — only a generic with more than 64 struct-carrier slots (parameters and `var x: G<..T..>` locals,
one entry per slot a type parameter takes whole) meets it; the result is the pre-6.7.11 refusal "expected ';', got
'.'" at the 65th carrier's `x.f.g`, not a miscompile.
**Affects:** the 6.7.11 lane tree onward (ed9456c1 added the table).

## Summary

ed9456c1 made a generic that reads its struct carrier's `T` field as a struct (`b.v.y`, `b: Box<T>`) a stub: the
stub scan records each carrier of the fn being scanned in `_gcr` (src/frontend/parse_fn.cyr, `_gcr_note` ->
`_gcr_add`), and mode 0 counts `x.f.g` a struct use when x is recorded (`_gs_cfield`). `_gcr` is an alloc'd 64-entry
table, and `_gcr_add` returns 0 once `_gcr_n >= 64` — the entry is dropped, nothing is reported, and every later
carrier of that generic is invisible to `_gs_cfield`. Its base is then parsed as the i64 instance, where `x.v` is an
i64 and `.y` fails to parse.

## Reproduction

A generic with its parameter `b` (entry 0), 63 `var cN: Box<T>;` locals (entries 1-63) and one more carrier:

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn gy<T>(b: Box<T>): i64 {
    var c1: Box<T>;
    # ... var c2: Box<T>; through var c62: Box<T>; — one per line
    var c63: Box<T>;
    var z: Box<T> = b;
    return z.v.y;
}
fn main(): i64 { var b: Box<Pt>; b.v.x = 3; b.v.y = 44; b.n = 1; return gy(b); }
syscall(60, main());
```

```
actual (lane build/cycc):
error:<source>:69:15: expected ';', got '.'
        return z.v.y;
                  ^
with `var c63` removed (64 entries): compiles, exit 44
expected: exit 44 either way, or a refusal that names the cap
```

## Fix direction

Grow the table on demand (as `_sinst` / `_fn_rpsid` are sized for their caps), or — if a cap stays — report it by
name at the 65th carrier ("too many struct carriers in generic 'gy' (64)") instead of dropping the entry. Row: the
repro above in tests/gates/frontend/generic_type_arg_unknown_refused.sh's CF section (exit 44, or the named refusal).
