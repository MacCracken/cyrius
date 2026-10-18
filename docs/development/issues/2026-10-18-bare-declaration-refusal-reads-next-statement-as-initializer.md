# A bare `var c;` (and `var c: ;`) in a fn or after the first statement reads the NEXT statement as its initializer — "undefined variable" follows — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend, unit F2, x86_64; the
frontend, every target), identical on the slot-open compiler (b2e1f4c48's build/cycc) and on the lane's compiler.
**Placement:** unplaced — filed from the 6.7.15 frontend lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Low — refused either way (rc 1); the first error is the right one, one invented error follows.
**Kind:** bug (diagnostic cascade).
**Discovered:** 2026-10-18, by unit F2 fixing issues/2026-10-16-var-missing-annotation-reported-as-expected-equals.md:
its `var b: ;` (now "expected a type for variable 'b', got ';'", the bare-declaration refusal standing down) inherits
the bare declaration's recovery below. Not that issue's filed surface (its repro is `var b: = 0;` / `var G: = 4;`,
each one error).

## Reproduction

```cyrius
fn f(): i64 {
    var c;
    var d = 9;
    return d;
}
syscall(60, f());
```

```
error:<source>:2:10: uninitialized variable not allowed; use `var X = 0;` or initial value
error:<source>:4:13: undefined variable 'd' (missing include or enum?)
```

The same after the first top-level statement (`syscall(39);\nvar c;\nvar d = 9;\nsyscall(60, d);` -> 2:6 then
`4:14: undefined variable 'd'`), and with the 6.7.15 annotation form `var c: ;` (2:12 "expected a type for variable
'c', got ';'" then the same `undefined variable 'd'`). In the declaration zone (`var c;\nvar d = 9;\nsyscall(60, d);`)
it is one error. A next statement that declares nothing (`return 9;`, an `if`) is swallowed silently: one error.

Expected: one error; the declaration ends at its `;` and the next statement is parsed as a statement.

## Root cause

PARSE_VAR (src/frontend/parse_decl.cyr), after the refusal (`_decl_eq_err` since 6.7.15; before, the inline
`ERR_MSG` + `ERR_EXPECT(S, 4)`), steps one token as if it were the `=` — here the `;` — and reads an initializer from
the next statement's first token under the panic latch; the resync then drops the whole next statement, so its
declaration never registers. The comment beside the struct-literal arm explains why an early `return` is not the fix
(top-level pass 2 has no `_sync_skip`); the stand-down has to leave the cursor on the `;` for the declaration's own
end-of-statement check instead of stepping it.
