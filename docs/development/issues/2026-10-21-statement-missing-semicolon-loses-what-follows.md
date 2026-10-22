# A statement missing its `;` before a `}` or a statement keyword loses what follows: the next fn is "defined inside" the last, and later statements' own errors are never reported — OPEN

**Status:** 🟡 **OPEN** — a cross-cutting repair of a day or more (43 sites in six frontend files plus the zone replay's
latch); a first fix was tried in the f16 lane and reverted, and the f16 lane stopped on it.
**Placement:** 6.7.17 — the cleanup of the remaining issues (feb lane, wave 2, unit FB1; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Discovered:** the f16 lane, unit FG2.
**Severity:** Low — refused programs' diagnostics (one missing `;` hides or invents errors); nothing that compiles
changes.
**Kind:** repair.

## Summary

After "expected ';'", the parser consumes the token it found in the `;`'s place. When that token is the `}` that closes
the fn, the fn never closes: the next fn is reported as nested and the file ends inside it. When it is the next
statement's keyword (`var`), that statement is parsed from its second token, and its own error is never reported. In the
declaration zone the replay's latch swallows the following declarations' errors the same way.

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B), x86_64
(the shared frontend).

```cyrius
fn h(): i64 { return 1 }
fn main(): i64 { return 2; }
syscall(60, main());
```

```
error:<source>:1:24: expected ';', got '}'
error:<source>:2:1: fn 'main' is defined inside fn 'h'; define it at top level
  note: a local function is a closure (`var f = |x| { .. };`); a fn inside a top-level block is allowed
error:<source>:3:21: expected '}', got end of file
```

```cyrius
fn main(): i64 {
var a = 1
var b = zz;
return a; }
syscall(60, main());
```

```
error:<source>:3:1: expected ';', got var
```

— the undefined `zz` on line 3 is never reported. (The lane's measurement at the f16 base also printed an invented
"undefined variable 'b'"; the merged compiler prints the one line.)

```cyrius
var g = 1
fn f1(): i64 { return zz1; }
fn f2(): i64 { return zz2; }
syscall(60, g);
```

```
error:<source>:2:1: expected ';', got fn
```

— neither fn's own error (`zz1`, `zz2`) is reported.

## Repair plan

- **The sites:** 43 places in six frontend files call `ERR_EXPECT(S, 5)` and then consume the next token
  unconditionally (the f16 lane's count, FG2), plus the zone replay's latch path (EMIT_GVAR_INITS / pass 1's zone
  scan), which is a separate mechanism.
- **What was tried (never committed):** a `_semi_end` helper that does not consume a `}`, the end of file or a statement
  keyword. It fixed the three probes and kept the seed chain, but full check.sh went red on
  struct_literal_type_refused.sh S22 — `var P = 3; P { 5 };`, where the `}` closing the unparsed literal's `{` was then
  taken as the fn's end ("unexpected ';'", "return outside a fn body").
- **So:** each site needs statement-start brace accounting (does the `}` close a brace this statement opened?), and
  the zone variant needs its own latch release. Every one of the 43 sites sits in files the parser lanes edit, so it is a
  slot of its own.
- **Rows:** the three repros above, each reporting each mistake once (the `;`, then `zz`, then `zz1` and `zz2`), on
  x86_64, aarch64, cx and PE; S22 and the corpus unchanged.
