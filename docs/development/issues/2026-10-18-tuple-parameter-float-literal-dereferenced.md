# Into a tuple parameter, a float literal — `take(1.5)`, `take(-1.5)`, `take((2.0))` — compiles and is dereferenced as the tuple's address — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 receives lane (unit R1) while landing 6.7.15's D36
(issues/archived/2026-10-17-tuple-parameter-negated-bool-or-constant-expression-literal-dereferenced.md: an argument made
only of integer / char / bool literals and operators is refused into a tuple parameter). D36's answer gives the
words for an integer and a bool only ("cannot pass an integer …", "'a bool' for `true` / `false`"); a float literal
is outside that text, so it was filed rather than given new words. Measured with the lane after R1 (140fd4c3e) and
built from that tree: `build/cycc`, the aarch64 cross compiler (qemu-aarch64), the cx compiler (cxvm) and
`CYRIUS_TARGET_WIN=1` (wine, a private prefix).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 receives lane, wave 3; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — compiles clean and crashes at run time; an f64 literal can never be a tuple's address, and the
spelling is unusual.
**Kind:** language — needs the user's words for the refusal (D36 named integer and bool only), or a decision that a
float literal stays an untyped word.

## Reproduction

Each program alone (`<ARG>` replaced by the argument in the table):

```cyrius
fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }
fn f(): i64 { return take(<ARG>); }
syscall(60, f());
```

| argument | compile | x86_64 | aarch64 (qemu) | cx (cxvm) | PE (wine) |
|---|---|---|---|---|---|
| `1.5` | rc 0, no diagnostic | 139 | 139 | 1 | 5 |
| `-1.5` | rc 0, no diagnostic | 139 | 139 | 1 | 5 |
| `(2.0)` | rc 0, no diagnostic | 139 | 139 | 1 | 5 |
| `-5` (D36, control) | refused: `2:27: cannot pass an integer to tuple parameter 't' (i64, i64) of 'take' - it takes a tuple` | — | — | — | — |

## Root cause

`_tal_scan` (src/frontend/parse_fn.cyr, 6.7.15) accepts integer / char literals (token 1) and `true` / `false`
(169 / 170) as the operands of a literal-only argument; a float literal is token 61, so the argument is exempt, falls
to the value push, and the callee reads through the f64's bits as the tuple's address.

## Proposed fix

Once the words are decided: `_tal_scan` also takes token 61 and answers a third kind (for example "cannot pass an
f64 to tuple parameter …"), so `take(1.5)`, `take(-1.5)`, `take((2.0))` and a float constant expression are refused
by name at the argument, the parse in step. Rows beside tuple_checked.sh's R17w rows on all four legs.
