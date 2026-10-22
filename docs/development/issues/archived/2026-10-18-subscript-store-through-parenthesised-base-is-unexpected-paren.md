# A subscript store through a parenthesised base — `(pn)[0] = 1;`, `(*(&pn))[1] = 2;` — is still "unexpected '('" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ST-7, `ff6df9ff5` — the user's D22, 2026-10-19: "The words the parenthesised subscript read gets". `_stmt_paren_dst` sends a `[` after the wrap to the new `_stmt_paren_sub`, which refuses an assignment through `_psub_err`. The filed repro stays refused, rc 1, now with two errors at 4:5 and 5:5 in the read's words — "a subscript's base is a name, a *T field or a call returning *T - name the pointer first (var q: *T = ..; q[i])" (it was "unexpected '('" twice) — and line 6 parses with no further error, on the x86_64, aarch64, cx and PE compilers. `(pn)[0] += 1;`, two subscript steps, a loop body, a generic (once), top level and `--syntax-only` alike; `(pn)[0];` with no assignment keeps "unexpected '('". Rows: `tests/gates/frontend/paren_field_access.sh` PS1 (the filed repro verbatim) and PS0 – PS11; mutations RED 35 / RED 4. Outside the filed statements and filed beside it (placed IN 6.7.16, the s16 lane): a classic-for STEP with a parenthesised destination still says "expected '='" (`docs/development/issues/archived/2026-10-19-parenthesised-for-step-destination-is-expected-equals.md`; PS10 pins it). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S5) landing the user's D19
(issues/archived/2026-10-17-parenthesised-assignment-destination-is-unexpected-paren.md): a statement whose whole assignment
destination is parenthesised (`(*p) += 1;`, `(n) = 7;`) is now refused by name, and `(s).a = v;` is refused by name since
6.7.14's D24 (a); a SUBSCRIPT after the parentheses (`(pn)[0] = 1;`) is neither shape — the token after the `)` is `[`,
not an assignment or a `.` — and keeps "unexpected '('". Measured on the lane head before S5 and after it alike, x86_64
(frontend: every target alike). Pre-existing.
**Placement:** 6.7.16 — Break 2, repair 6 (structs lane, wave 1, unit S3; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D22 — The words the parenthesised subscript read gets.
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
