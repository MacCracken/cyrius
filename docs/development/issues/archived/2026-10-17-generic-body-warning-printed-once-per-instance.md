# A warning inside a generic fn's body is printed once per instance (the 6.7.14 latch covers errors only) — RESOLVED

> ✅ **RESOLVED in v6.7.15** (GN-22, `a916f88fc`: WARN heads with `_warn_seen` (6.7.14's table, keyed on the token and a negative identity of the message), and so do the direct `warning:` writers that can run in a body parsed again — `match`, `#must_use`, a nested `@unsafe`, a Str into a cstring parameter, the f64 / integer mix, the PE, Mach-O and ELF-aarch64 syscall warnings. The filed repro's three lines print once; an `#inline` fn's warning 4 -> 1; each direct writer 3 or 4 -> 1 (the Mach-O ones measured on ecb and ach); two different warnings at one token both print. No decision needed (diagnostics only). Rows: `generic_body_error_once.sh` W1 (the filed repro verbatim) - W4 and WD1 - WD9; mutations MW1 - MW3 each RED. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on main after the 6.7.14 waves 1 and 2 (build/cycc 2,416,968 B), x86_64;
the same on the 6.7.14 slot-open compiler. Found by the 6.7.14 release-docs pass reading the generics lane: its G2
handoff took the warning half as already filed under issues/archived/2026-10-10-generic-body-errors-reported-per-instance.md,
whose fix (GN-18, 3bf60734: `_err_once` / `_err_dup` in util.cyr) latches the ERROR emitters only — WARN_AT is untouched.
**Placement:** 6.7.15 — repair 5 (generics lane, wave 1, unit G6; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — diagnostics only: the same warning at the same token is printed once per parse of the body (the
base and each struct instance), so a program with N struct instances of a generic sees N + 1 copies.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P { a; b; }
struct Q { c; d; e; }
fn g<T>(x: T): i64 { var q = 5; var p: *i64 = q; return 1; }
fn run(): i64 { var u = P { 1, 2 }; var w = Q { 1, 2, 3 }; return g(1) + g(u) + g(w); }
syscall(60, run());
```

```
$ build/cycc < w.cyr > w
warning:<source>:4:48: assigning non-pointer to typed pointer
warning:<source>:4:48: assigning non-pointer to typed pointer
warning:<source>:4:48: assigning non-pointer to typed pointer
```

One line is right (as GN-18 made an error inside the same body print once).

## Fix

Route WARN_AT (and the direct `warning:` writers it does not cover) through the same per-token, per-identity latch the
error emitters use (`_err_dup`), with a warning identity of its own, so a repeated parse of a body warns once; a row in
tests/gates/frontend/generic_body_error_once.sh beside E1 – E6 (a warning in a generic body, three instances: one line).
