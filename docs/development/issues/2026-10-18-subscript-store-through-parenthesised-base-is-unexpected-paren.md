# A subscript store through a parenthesised base — `(pn)[0] = 1;`, `(*(&pn))[1] = 2;` — is still "unexpected '('" — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S5) landing the user's D19
(issues/2026-10-17-parenthesised-assignment-destination-is-unexpected-paren.md): a statement whose whole assignment
destination is parenthesised (`(*p) += 1;`, `(n) = 7;`) is now refused by name, and `(s).a = v;` is refused by name since
6.7.14's D24 (a); a SUBSCRIPT after the parentheses (`(pn)[0] = 1;`) is neither shape — the token after the `)` is `[`,
not an assignment or a `.` — and keeps "unexpected '('". Measured on the lane head before S5 and after it alike, x86_64
(frontend: every target alike). Pre-existing.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — a refusal with a message that names only the token; nothing that compiles is affected. Not a
security id (the developer's own source).
**Kind:** language (whether `(p)[i] = v` is a statement) — or, if it stays out, a diagnostic.

## Reproduction

```cyrius
fn main(): i64 {
    var buf[16];
    var pn: *i64 = &buf;
    (pn)[0] = 1;
    (*(&pn))[1] = 2;
    return pn[0] + pn[1];
}
syscall(60, main());
```

```
$ build/cycc < sub.cyr > sub; echo $?
error:<source>:4:5: unexpected '('
        (pn)[0] = 1;
        ^
error:<source>:5:5: unexpected '('
        (*(&pn))[1] = 2;
        ^
1
```

## Root cause

`_stmt_paren_field` (src/frontend/parse_expr.cyr) takes a statement opening `( .. ) .name` (D24 (a): a read / method
statement, a store refused by name) and, since 6.7.15, `_stmt_paren_dst` one whose token after the outermost `)` is an
assignment (D19). `( .. ) [ .. ] = v` reaches neither, so `_PARSE_STMT_IMPL` falls to ERR.

## Options (the user's)

- (a) Refuse it by name as `(s).a = v;` is ("cannot assign through parentheses - write the store without them") — the
  D19 hint cannot simply drop the parentheses here: `(*pn)[0]` unwrapped is `*pn[0]`, which is `*(pn[0])`.
- (b) Refuse it with the words a parenthesised subscript READ already gets: `return (pn)[0];` is "a subscript's base is
  a name, a *T field or a call returning *T - name the pointer first (var q: *T = ..; q[i])" (measured the same day) —
  the store would say what the read says.
