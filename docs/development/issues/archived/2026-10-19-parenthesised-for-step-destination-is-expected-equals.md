# A classic-for STEP whose destination is parenthesised — `(n) = 7`, `(*pn) += 1`, `(pn)[0] = 2`, `(s).a = 3` — is "expected '=', got <the next token>", not the statement's refusal — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-5, `4bb0d6cdb`, with SS-6 `6ee0305e8` (lint's parenthesised store, met) — no decision needed (wording: the statement's decisions reused — 6.7.14's D24 (a), 6.7.15's D19, 6.7.16's D22). `_for_step_replay` asks `_step_paren`, the statement's readers with the step's `)` as the end, as the filing sketched. The filed repro prints the statement's four refusals, once each — 7:24 "an assignment's destination is not parenthesised - write `n = 7`", 8:24 "... `*pn += 1`", 9:24 the parenthesised subscript's words, 10:27 "cannot assign to a field after parentheses - write the store without them (`s.a = v`)" — and no binary (it was four "expected '='" at column 25). SS-6: `cyrius lint` refuses `(s).a = 1;`, `(s).a += 1;` and the step `(s).a = 3`, as the build does. Rows: `paren_field_access.sh` FS1 (the repro verbatim) – FS11, N8, PS10 re-pinned, on the x86_64, aarch64, cx and PE compilers. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 structs lane (unit S3) landing the user's D22
(issues/archived/2026-10-18-subscript-store-through-parenthesised-base-is-unexpected-paren.md: the STATEMENT `(pn)[0] = 1;` now
prints the parenthesised subscript read's words). Measured on the lane head before S3 (f3331c48e) and after it alike,
x86_64 (frontend: every target alike). Pre-existing since each statement refusal landed (6.7.14's D24 (a), 6.7.15's
D19, 6.7.16's D22): none reached the for step.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 structs lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; s16 lane, wave 4, unit SS1) — never 7.x.
**Severity:** Low — a refusal (rc 1, no binary) whose message names the token after the `(` and not the rule; nothing
that compiles is affected. Not a security id (the developer's own source).
**Kind:** diagnostic (the for step's wording for shapes the statement refuses by name).

## Reproduction

```cyrius
struct P1 { a; }
fn main(): i64 {
    var n = 5;
    var pn: *i64 = &n;
    var s = P1 { 1 };
    var i = 0;
    for (i = 0; i < 1; (n) = 7) { i = i + 1; }
    for (i = 0; i < 1; (*pn) += 1) { i = i + 1; }
    for (i = 0; i < 1; (pn)[0] = 2) { i = i + 1; }
    for (i = 0; i < 1; (s).a = 3) { i = i + 1; }
    return n;
}
syscall(60, main());
```

```
$ build/cycc < fs.cyr > fs; echo $?
error:<source>:7:25: expected '=', got identifier 'n'
        for (i = 0; i < 1; (n) = 7) { i = i + 1; }
                            ^
error:<source>:8:25: expected '=', got '*'
        for (i = 0; i < 1; (*pn) += 1) { i = i + 1; }
                            ^
error:<source>:9:25: expected '=', got identifier 'pn'
        for (i = 0; i < 1; (pn)[0] = 2) { i = i + 1; }
                            ^
error:<source>:10:25: expected '=', got identifier 's'
        for (i = 0; i < 1; (s).a = 3) { i = i + 1; }
                            ^
1
```

The same four as STATEMENTS (`(n) = 7;`, `(*pn) += 1;`, `(pn)[0] = 2;`, `(s).a = 3;`) are refused by name, once at the
`(` / the `.`: "an assignment's destination is not parenthesised - write `n = 7`" (6.7.15's D19), "a subscript's base is
a name, a *T field or a call returning *T - name the pointer first (var q: *T = ..; q[i])" (6.7.16's D22), "cannot
assign to a field after parentheses - write the store without them (`s.a = v`)" (6.7.14's D24 (a)).

## Root cause

The classic-for step is replayed after the body by `_for_step_replay` (src/frontend/parse_ctrl.cyr), not by
PARSE_STMT, so `_stmt_paren_field` / `_stmt_paren_dst` (src/frontend/parse_expr.cyr), which carry the three statement
refusals, never see it. `_for_step_replay` takes the step's first token as the destination's NAME (`noff = PEEKV`,
cursor past it) — the `(` — and `_for_step_assign` then finds the token after it where it wants `=` / `OP=`.

## The fix (a sketch)

In `_for_step_replay`, a step whose first token is `(` asks the statement's three readers with the step's `)` as the
terminator (`_pf_wrap` + `_pf_chain_end` + `_pf_asg_at` for the field store, `_stmt_paren_dst`'s place test and its
subscript arm): the same words, once at the same token; PARSE_FOR restores the cursor after the step, so the refusal
needs no skip. Whether the step should say the statement's words is the shape the three decisions named for statements
only — likely a one-line confirmation.
