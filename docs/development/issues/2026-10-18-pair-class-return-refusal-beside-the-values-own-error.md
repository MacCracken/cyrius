# A 9-16 B struct fn's `return E;` with a malformed or undefined E reports the pair class's refusal AND E's own error — `return zz;` is two errors, `return &(q);` two — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S5) beside
issues/2026-10-17-address-of-parenthesised-name-false-second-error.md (whose 8 B repro now reports one error; the 16 B
twin keeps two). Measured on the lane head before S5 and after S5 alike, x86_64 (frontend: every target alike).
Pre-existing.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
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
