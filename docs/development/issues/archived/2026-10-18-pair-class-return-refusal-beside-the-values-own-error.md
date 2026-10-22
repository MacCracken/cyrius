# A 9-16 B struct fn's `return E;` with a malformed or undefined E reports the pair class's refusal AND E's own error — `return zz;` is two errors, `return &(q);` two — RESOLVED

> ✅ **RESOLVED in v6.7.16** (RV-10, `bc8801954`, with RV-11, `43e661ac0`; the review's RV-10r, `18846b7b8`, takes the same order to the vector class, and RV-15 / RV-16 (`4d40646ad`, `6c7ecca74`) to a returned tuple literal and `ret2(a, b)` — no decision needed: diagnostics only; the default the brief named, E's own error survives as at 8 B). `_ret_struct_pair` records the value's first token and the statement's `_err_n` (`_pair_ret_defer`); PARSE_RETURN asks `_pair_ret_late` once its arms have parsed the value and prints the class refusal there only when the statement reported nothing (never the file-wide `_had_error`), saving and restoring the pending refusal around a `return` inside the value (a closure body's, an `#inline` replay's). The filed `pr2`, verbatim, now gives one error, "2:28: undefined variable 'zz'", on x86_64, aarch64, cx and PE (two before, the refusal at 2:26 first); `return &(q);` one at 2:27, `return 5 + ;` one at 2:30; `return 5;` keeps the refusal at 2:26; the 8 B and 24 B classes are unchanged; the shared method / operator arm (RV-11: `return zz + 1;`, `return q.e(zz);` at 16 and 24 B) yields to the value's error too. Rows: `small_struct_return_type_refused.sh` P1 (pr2 verbatim) – P15 / PC1 – PC9, SX1 – SX5 / SXC1 – SXC2, VE / VEC, TU / TUC, R2E / R2C on four compilers. Mutations each RED (the tree before 68; `_had_error` 8; no save / restore 16; no cursor restore 29; RV-11's 40). Its neighbour `return nofn(1);` (the class refusal and the end-of-compile refusal, both true) stays as decided: D105, the user, 2026-10-20, no change. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S5) beside
issues/archived/2026-10-17-address-of-parenthesised-name-false-second-error.md (whose 8 B repro now reports one error; the 16 B
twin keeps two). Measured on the lane head before S5 and after S5 alike, x86_64 (frontend: every target alike).
Pre-existing.
**Placement:** 6.7.16 — Break 2, repair 6 (receives lane, wave 3, unit R3; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — diagnostics only: the program is refused at the right line; a second error names the same
statement. Not a security id (the developer's own source).
**Kind:** diagnostic cascade.

## Reproduction

```cyrius
struct Q { v; w; }
fn mk(q: *Q): Q { return zz; }
fn main(): i64 { var s: Q; var r: Q = mk(&s); return r.v; }
syscall(60, main());
```

```
$ build/cycc < pr2.cyr > pr2; echo $?
error:<source>:2:26: a fn returning the 9-16 byte struct `Q` is returned in two registers, so `return` takes a local of that struct or a call returning it — got `zz`
error:<source>:2:28: undefined variable 'zz' (missing include or enum?)
    fn mk(q: *Q): Q { return zz; }
                               ^
1
```

The same pair for `return &(q);` ("... got `this expression`" then "expected identifier, got '('") and `return 5 + ;`
("... got `5`" then "unexpected ';'"). The 8 B class (`struct Q { v; }`) reports only the value's own error, and the
over-16 B class only its own refusal ("struct-return fn: return must be a bare local identifier ..." /
"struct-return: identifier is not a local").

## Root cause (not traced to the line)

`_refuse_pair_return` (src/frontend/parse_fn.cyr, reached from the pair class's `return` arm when `_pair_ret_call_ok`
answers 0) prints its refusal BEFORE the value is parsed, and does not latch the panic, so the parse of E that follows
(`_ret_unpeel` -> the scalar path) reports E's own syntax / undefined-name error too.

## Fix direction

One error per statement: either the pair refusal is not printed when E does not parse (or names nothing that exists),
or E's parse runs under the latch the refusal sets. Which error survives (the class's or E's own) is the placement's
call; the 8 B and over-16 B classes each report one.
