# Into a tuple parameter, a float literal — `take(1.5)`, `take(-1.5)`, `take((2.0))` — compiles and is dereferenced as the tuple's address — RESOLVED

> ✅ **RESOLVED in v6.7.16** (RV-2, `7a3186753`, and the RV-2r review fix `b45799db7` — D23, the user, 2026-10-19: "Refused at the argument". `_tal_scan` takes a float literal (token 61) as an operand and `_tty_arg` types the value as the compiler does (RV-2r: `+ - * /` keep an f64 on either side, a saturating / checked link its right operand's type, `~` keeps an f64; `& | ^ % << >> >>>` give an integer, 6.7.13's D12). The filed table, verbatim — `take(1.5)`, `take(-1.5)`, `take((2.0))` — is now refused once on x86_64, aarch64, cx and PE, no binary: "cannot pass an f64 to tuple parameter 't' (i64, i64) of 'take' - it takes a tuple" (2:27 / 2:27 / 2:28); they compiled and exited 139 / 139 / 1 / 5. A float constant expression (`take(2.0 * 1.5)`, `take(1.5 + 1)`, `take(1 + 1.5)`, `take(~1.5)`) is "an f64" too, a float comparison `take(1.5 < 2.0)` "a bool" (D23's text), and an integer-typed mix (`take(1.5 & 1)`, `take(1.5 +| 1)`, `take(-!1.5)`) "an integer" — ⚠ beyond D23's text, words only. A name — an `f64` const too — is still passed as the address (6.7.15's D36). `take(2 +| 1.5)` says "an f64" until D104's unit (f16 FG4, 6.7.16) makes the saturating / checked operators integer; R17y16 follows it. Rows: `tuple_checked.sh` R17y1 (the repro verbatim) – R17y18b on four legs (R17y11: the `f64` const control compiles). Mutations each RED: `_tal_scan` without token 61 (40 rows), a float literal read as an integer (32), `_tty_bin` typing by its left operand (24), `~` an integer (4). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 receives lane (unit R1) while landing 6.7.15's D36
(issues/archived/2026-10-17-tuple-parameter-negated-bool-or-constant-expression-literal-dereferenced.md: an argument made
only of integer / char / bool literals and operators is refused into a tuple parameter). D36's answer gives the
words for an integer and a bool only ("cannot pass an integer …", "'a bool' for `true` / `false`"); a float literal
is outside that text, so it was filed rather than given new words. Measured with the lane after R1 (140fd4c3e) and
built from that tree: `build/cycc`, the aarch64 cross compiler (qemu-aarch64), the cx compiler (cxvm) and
`CYRIUS_TARGET_WIN=1` (wine, a private prefix).
**Placement:** 6.7.16 — Break 2, repair 6 (receives lane, wave 3, unit R1; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D23 — Refused at the argument.
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
