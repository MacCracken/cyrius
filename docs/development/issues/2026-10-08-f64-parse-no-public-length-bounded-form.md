# `lib/math.cyr` has no public length-bounded `f64_parse` — the correctly rounded core is internal (`_f64_parse_n`) — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b: `f64_parse(s)` reads a NUL-terminated
string to the first non-number byte (`f64_parse("2.57,")` with the wanted span "2.5" gives 2.57); the length-bounded
core `_f64_parse_n(s, n)` is the only bounded entry and is underscore-internal; `f64_parse_n` is undefined. The
vendored bayan still carries its own copy of the algorithm, `bayan_f64_parse(s, n)` (`lib/bayan.cyr:4696`).
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** the 6.6.13 f64-parse rounding fix (I4) ported bayan's parser as the internal `_f64_parse_n`
("internal until bayan calls it", `lib/math.cyr:1354`); the ask is bayan's B-4; filed 2026-10-08 from roadmap.md.
**Severity:** Low — an API gap with a working stopgap (bayan's duplicate parser).
**Affects:** cycc ≤ 6.7.6 `lib/math.cyr`.

## Summary

A JSON / TOML / CSV reader holds a number as a span `(ptr, len)` inside a larger buffer, not as a NUL-terminated
string. cyrius's correctly rounded parser (Clinger fast path → DiyFp tier → 800-digit exact decimal, CHANGELOG
[6.6.13]) is already length-bounded internally — `_f64_parse_n(s, n)` (`lib/math.cyr:1355`) — but the public
surface is only `f64_parse(s)` (`:1445`, calls `_f64_parse_n(s, 2147483647)`) and `f64_parse_ok(s, out)` (`:1471`).
So bayan keeps a second implementation of the same algorithm (`bayan_f64_parse`, `_jp_atof`, the `_d_*` tables —
which is why cyrius's helpers carry the `_f64p_` prefix: a shared name would only warn and swap bodies), i.e. two
copies of a numerically delicate routine to keep in step.

## Reproduction

```cyr
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/math.cyr"
alloc_init();
var buf = "2.57,";                      # the field is the first 3 bytes
var a = f64_parse(buf);                 # 2.57 — the public API cannot bound the span
var b = _f64_parse_n(buf, 3);           # 2.5  — only the internal core can
var c = f64_parse_n(buf, 3);            # ← undefined: "refusing to emit binary with 1 reachable undefined function(s)"
```

```sh
cat probe.cyr | /home/macro/Repos/cyrius/build/cycc > /tmp/p    # rc 1 on the `f64_parse_n` line; drop it → a = 2.57, b = 2.5
```

## Root cause

A deliberate deferral at 6.6.13: the bounded core was kept internal until bayan delegated to it.

## Proposed fix

Add a public `f64_parse_n(s, n)` in `lib/math.cyr` as a thin wrapper over `_f64_parse_n` with documented semantics —
it must decide one point the two current fronts disagree on: `_f64_parse_n` reads ANY `n`/`N` start as NaN and any
`i`/`I` start as ±Inf (bayan's JSON leniency), while `f64_parse` accepts only strict `nan` / `inf`. The sensible
default is `f64_parse`'s strict front applied within `n` bytes, with bayan keeping its leniency on its side. Then
bayan (in its source repo) delegates `bayan_f64_parse` to it and drops `_d_*`, released as a bayan patch and
re-vendored. Gates: `tests/tcyr/math/f64_parse_rounding.tcyr`'s corpus through the new entry with explicit lengths
(including a span followed by digits), and `removed_symbol_census.sh` stays clean (addition only).
