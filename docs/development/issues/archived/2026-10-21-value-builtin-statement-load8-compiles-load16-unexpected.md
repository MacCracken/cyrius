# A value builtin as a bare statement: `load8(p);` compiles while `load16(p);` / `load32(p);` / `load64(p);` / `f32_from(x);` / `f32_to(x);` are "unexpected load16" — RESOLVED

> ✅ **RESOLVED in v6.7.17** (fea lane, unit FA2, `6620050a1` (D32), met `df752e24d`, `dce149274`, `7f4215d72`, `b955d8589`; D32, "Refuse every one in D11's words"): a value builtin as a whole statement (`load8(p);`, `f64_sqrt(x);`, `rethi();`, the dot products — 40 builtins) is refused in D11's words; a builtin's malformed call is one error and its block still closes; a value builtin, an identifier intrinsic or a bare name used as a statement with no `(` / `=` (`load16;`, `mulh64;`, `p;`) is one error and the statement ends in sync. Rows: intrinsic_names_reserved.sh, tests/tcyr f64_le_ge_trunc_builtins.tcyr and token_renumber_79_111.tcyr. CHANGELOG [6.7.17])

**Status:** ✅ **RESOLVED in v6.7.17** (see the banner). Was: 🟡 **OPEN** — whether a value builtin may stand as a statement, and in which words it is refused, is beyond
6.7.16's D11 (which decided `mulh64(..);` / `sizeof(..);`); the f16 lane stopped on it.
**Placement:** 6.7.17 — the cleanup of the remaining issues (fea lane, wave 1, unit FA2; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D32 — Refuse every one in D11's words.
**Discovered:** the f16 lane, unit FF6.
**Severity:** Low — one builtin compiles where its five siblings are refused, and the refusal's words are the generic
"unexpected".
**Kind:** decision.

## Summary

6.7.16's D11 refused `mulh64(2, 3);` and `sizeof(H);` as statements: "the value of 'mulh64(..)' is discarded - a
statement is an assignment or a call". Its reason said "every other value-only statement is already refused:
'load64(&g);'". That holds for `load16` / `load32` / `load64` / `f32_from` / `f32_to`, refused as "unexpected <name>" —
but `load8(p);` compiles (parse.cyr's builtin statement arms list `load8` and not the others).

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B); the `load8`
row also on aarch64, cx and PE: the same.

```cyrius
var b: i64 = 7;
fn main(): i64 { var p = &b; load8(p); return 3; }
syscall(60, main());
```

rc 0, no diagnostic, exit 3. With `load16(p);` in its place:

```
error:<source>:2:30: unexpected load16
```

`load32(p);` and `load64(p);` the same ("unexpected load32" / "unexpected load64"); `fn main(): i64 { var x = 3;
f32_from(x); return 3; }` gives `error:<source>:1:29: unexpected f32_from`, and `f32_to(x);` "unexpected f32_to".

## The decision

- (a) Refuse all six with D11's words ("the value of 'load8(..)' is discarded - a statement is an assignment or a call"):
  `load8(p);` stops compiling; the other five keep failing, in D11's words.
- (b) Keep `load8(p);` compiling (a load whose value is dropped) and give the other five D11's words.
- (c) Accept all six as statements, value dropped (the five newly compile).

## Acceptance

The six statements give the decided result on x86_64, aarch64, cx and PE, once each, with the next statement still
reporting its own error; `var v = load8(p);` and every store builtin (`store8(p, v);`) unchanged.
