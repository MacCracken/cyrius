# `1 - 2 + 3` == 5 — the `_cfo` rewind class, third occurrence, this time in the PEXPR tier — RESOLVED

> **✅ RESOLVED in v6.4.80** (`src/frontend/parse_expr.cyr`; CHANGELOG [6.4.80]).

**Discovered:** 2026-07-26 by an adversarial verifier during the v6.4.x closeout doc sweep, while
empirically re-checking an unrelated vidya claim about operator precedence. Found by *running the
compiler*, not by reading it.
**Severity:** **Critical** — silent wrong values in ordinary constant arithmetic, no diagnostic.
**Affects:** cycc up to and including **6.4.79**.

## Summary

Constant expressions in the PEXPR tier (`+ - & | ^`) silently discarded their left operand whenever a
literal subtraction produced a **negative intermediate**:

| expression | 6.4.79 | correct |
|---|---|---|
| `1 - 2 + 3` | **5** | 2 |
| `2 - 5 + 10` | **15** | 7 |
| `0 - 1 + 3` | **4** | 2 |
| `3 + 1 - 5 + 2` | **7** | 1 |
| `1 - 2 ^ 3` | **1** | −4 |
| `1 - 2 & 3` | **2** | 3 |
| `1 - 2 \| 3` | **3** | −1 |

The emitted code is exactly the expression with the leading `a -` deleted: `1 - 2 + 3` computes
`2 + 3`. Non-negative intermediates were always correct (`5 - 3 + 1` == 3), which is precisely why it
hid.

**Measured blast radius:** on a systematic 3-term sweep over `{0,1,2,3,5,10} {+,-,&,|,^} {1,2,3,5,7}
{+,-,&,|,^} {1,3,10}`, **40 of 400 expressions (10 %)** produced a wrong folded value at 6.4.79.

## Root cause — the same mechanism, for the third time

A fallback branch cleared `_cfo = 0` **before** calling `PARSE_TERM`, which calls `PARSE_FACTOR`,
which **re-arms** `_cfo = 1` for a bare NUM and sets `_cfp = GCP(S)` — now pointing *past* the left
operand's emitted code. The next operator saw a live fold and `SCP(S, _cfp)` rewound the code pointer
over the left operand, emitting only the folded tail.

The trigger is the `cfr >= 0` test in the subtract fold: a negative intermediate fails it and takes
the runtime fallback — and the fallback was the buggy one.

**This class has now bitten three times, and each fix was scoped to the operator that was reported
rather than to the mechanism:**

| when | symptom | scope of the fix |
|---|---|---|
| 2026-06-11 (cyrius-doom) | `A * B * 4` → 800 | the EIMUL path |
| **v6.4.74** | `100 >>> 1 + 1` == 2 | 17 sites, `PARSE_TERM` tier (`/ % << >> >>>`) |
| **v6.4.80** (this) | `1 - 2 + 3` == 5 | 16 sites, `PEXPR` tier (`+ - & \| ^`) |

v6.4.74 is mine, and it shipped incomplete: I swept the tier the repro landed in and did not check
whether the same `_cfo = 0; …PARSE_TERM…` shape existed one tier up. It did, 16 times. That is a
"a bug ships complete" failure, and the direct cause of this issue existing.

## Fix

Move `_cfo = 0` to **after** the emit sequence at all 16 PEXPR-tier fallback sites — identical to the
.74 remedy. Verified afterwards that **zero** `_cfo = 0; EPUSHR/ESPILL…PARSE_TERM` occurrences remain
anywhere in `parse_expr.cyr`, so the mechanism is now swept end-to-end rather than per-operator.

## Verification

- All 7 reported cases correct.
- **520-expression fold-vs-runtime differential** (folded gvar initializer vs the same expression
  computed at runtime through a variable): **0 mismatches**.
- Self-host fixpoint byte-identical; seed-derive (`seed → cybs → cycc`) OK; check.sh 149/0.
- **251/251 tcyr byte-identical to 6.4.79** — which is itself the finding: *the corpus contained no
  expression of the failing shape at all*. That is why 10 % of constant arithmetic could be wrong
  while every gate stayed green, and it is why the regression test below was mandatory.

## Gate

`tests/tcyr/const_chained_multiply_fold.tcyr` (the file already guarding the 2026-06-11 multiply
instance — the right home, since it is one mechanism) extended 8 → **33 assertions**, covering the
mechanism across every PEXPR-tier operator plus the gvar-initializer folder.

**Mutation-proven per operator**, which took three rounds and is worth recording:
- The obvious cases (`1 - 2 & 3`) fire the **SUB** fallback, not the AND one — reverting the 5 AND
  sites left the suite **green**. Needed a left operand that folds to 0: `0 & 1 & 1`.
- OR/XOR needed a **zero right-hand operand** (`1 | 0 ^ 1`); the AND-shaped cases did not reach them.
- ADD is only reachable via **i64 overflow** (`crv` from a literal is never negative, so `_cfv + crv`
  must wrap): `9223372036854775807 + 1 + 1`.

Final: mutating each of the 5 operator paths independently now fails 2–7 assertions each
(AND 3, OR 2, XOR 2, SUB 7, ADD 2). Before that work, 8 of the 16 sites had no coverage.

## Lesson worth carrying

When a fix moves a statement to cure a state-machine ordering bug, **grep for the shape, not the
operator**. All three occurrences were `_cfo = 0;` placed before a call that re-arms `_cfo`; a single
`grep -c "_cfo = 0; E.*PARSE_TERM"` at v6.4.74 would have found these 16 sites eight releases earlier.
