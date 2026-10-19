# A statement whose destination is parenthesised — `(*p) += 1;`, `(*(&s)) -= 1;`, `(n) = 7;` — is "unexpected '('" — RESOLVED

> ✅ **RESOLVED in v6.7.15** (ST-15, `62e8a934d` — the user's decision D19, 2026-10-18: "No: one error that names the rule". `_stmt_paren_field` asks `_stmt_paren_dst` when the token after the statement's outermost `)` is an assignment and the inside a place. The filed repro is "1:48: an assignment's destination is not parenthesised - write `*pn += 1`" (was "unexpected '('"), and `(*pn) = 1;`, `(n) = 7;`, `((n)) = 7;` and, on a struct, `(*(&s)) -= 1;` ("write `*(&s) -= 1`") likewise — once, the next statement still checked, `--syntax-only` alike — on the x86_64, aarch64, cx and PE compilers and the ecb, ach, pi and cass natives. `(n + 1) = 7;` and a tuple literal keep "unexpected '('"; `(s).a = v;` keeps 6.7.14's D24 words. Rows: `frontend/paren_field_access.sh` P1 (the repro verbatim) – P11; mutations RED. Not closed here (filed, 6.7.16): a subscript store through a parenthesised base, `(pn)[0] = 1;`, keeps "unexpected '('" (`2026-10-18-subscript-store-through-parenthesised-base-is-unexpected-paren.md`). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 structs lane (unit S3), x86_64, on the lane's tree (`c778c981`)
and on its S2 tip (9498bfb3): identical. Frontend: every target alike.
**Placement:** 6.7.15 — repair 5 (structs lane, wave 2, unit S5; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D19 — No: one error that names the rule.
**Severity:** Low — a compile error on a shape the guide never lists as a statement; the message names only the token.
Not a security id (the developer's own source).
**Kind:** language (a decision: whether a parenthesised destination is a statement) — or, if it stays out, a diagnostic.
**Discovered:** 2026-10-17, landing D17 (a) (issues/archived/2026-10-15-compound-assignment-through-address-of-struct-keeps-word-op.md):
that issue's triage listed a refusal row `(*(&s)) -= 1`, which never reaches the compound-assignment check — the
statement parser refuses the `(` first. The lane's row is `*((&s)) -= 1` (the wrap inside the dereference) instead.

## Reproduction

```cyrius
fn main(): i64 { var n = 5; var pn: *i64 = &n; (*pn) += 1; return n; }
syscall(60, main());
```

```
error:<source>:1:48: unexpected '('
```

The same for `(*pn) = 1;`, `(n) = 7;` and, on a struct `s`, `(*(&s)) -= 1;`. Parentheses around a whole SOURCE are
transparent everywhere (guide § Parentheses, 6.7.6); a destination is not a source, and no statement form starts with
`(`.

## Root cause

`_PARSE_STMT_IMPL` (src/frontend/parse.cyr) dispatches on the statement's first token: an identifier, `*` (the
dereference store, `_deref_store`), a keyword; a `(` reaches no arm and is reported as unexpected.

## Options (the user's)

- (a) A parenthesised destination is the destination (`(*p) OP= v` as `*p OP= v`, `(n) = 7` as `n = 7`), as a wrapped
  source is: code that is refused today starts compiling.
- (b) It stays refused, with a message that names the rule ("an assignment's destination is not parenthesised —
  write `*p += 1`") instead of "unexpected '('".
