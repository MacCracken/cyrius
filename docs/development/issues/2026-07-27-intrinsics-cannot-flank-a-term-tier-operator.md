# Intrinsic calls cannot flank a TERM-tier operator — `a * f64_from(2)` is a syntax error

**Status:** 🟡 **OPEN** — live, reproduced 2026-07-27 against cycc **6.4.82**. Pre-existing and
long-standing (the dispatch shape carries v5.10.17 / v6.4.5 / v6.4.6 / v6.4.9 annotations), **not** a
regression from .81 or .82.
**Severity:** **Medium** — valid cyrius is rejected at parse time, but it is a *loud* syntax error
with a one-character workaround, not silent wrong code.
**Placement:** v6.5.x, alongside the parser/IR work. **Not 7.x** (this is a parser defect).
**Found by:** the v6.4.82 closeout vidya sweep — an agent verifying a documented claim by *running the
compiler* rather than re-reading the doc. Same provenance as the v6.4.80 `_cfo` find.

## Why this is filed rather than fixed in v6.4.82

Per the rule in `CLAUDE.md` "Execution integrity", filing needs a named reason. This one:

**The fix is a restructure of `PARSE_TERM`'s head, which is the exact function that produced the
`_cfo` rewind class four times** (2026-06-11 cyrius-doom, v6.4.74, v6.4.80, v6.4.81). It is not a
bounded edit — it needs the intrinsic arms to stop early-returning AND `PARSE_FACTOR` to learn a
token set it has never known, then a full differential + seed-derive + cross-OS ×4 cycle to trust it.
That is a release's worth of verification, not a bite that packs into an already-gated closeout tag.
It also has a working workaround, and it is not a regression, so shipping .82 does not make anything
worse.

## Reproduction (verified, cycc 6.4.82)

```
fn main(): i64 { var a = 3; var c = a * f64_from(2); return 0; }
→ error:<source>:1:41: unexpected f64_from

fn main(): i64 { var a = 3; var c = f64_from(2) * a; return 0; }
→ error:<source>:1:49: expected ';', got '*'
```

Both sides fail. Works fine:

```
var c = a + f64_from(2);      # PEXPR tier — OK
var c = a * (f64_from(2));    # parenthesised — OK
var c = a * load64(&a);       # load* is NOT in the affected set — OK
```

**Fails for:** `*` `/` `%` `<<` `>>` `>>>` (the TERM tier).
**Works for:** `+` `-` `&` `|` `^` and all comparisons (the PEXPR tier — note cyrius puts the bitwise
ops on the `+`/`-` tier, so they are unaffected).

**Affected tokens** (probed individually): every `f64_*`, `f32_*`, `f64v_*`, `f32v_*`, `iv_*`, plus
`bitget`/`bitset`/`bitclr`, `store8/16/32/64`, `u128`, `ret2`/`rethi`.
**Not affected:** `load8/16/32/64`, `syscall`, `sizeof`, and ordinary fn calls.

**Not float-specific and not annotation-dependent** — `var a = 3; var c = a * f64_from(2);` fails
identically with no `: f64` anywhere.

## Mechanism

`src/frontend/parse_expr.cyr`, `fn PARSE_TERM` (~:2380). The extended builtins are dispatched at the
**head** of the function, each arm ending in an early `return`:

```
fn PARSE_TERM(S): i64 {
    _cfo = 0;
    var ptyp = PEEKT(S);
    if (ptyp >= 93)  { if (ptyp <= 99)  { return PARSE_SIMD_EXT(S, ptyp); } }
    ...
```

So:

- **As a LEFT operand** the parse `return`s before ever reaching `PARSE_TERM`'s `*` / `/` loop, and
  the pending `*` is then unexpected at the statement level.
- **As a RIGHT operand** that loop calls `PARSE_FACTOR` (one tier *down*, ~:274), which has never
  known these tokens.

This is the same *shape* family as the `_cfo` occurrences: a TERM-tier site whose control flow leaves
the tier early. It is worth noting that the four `_cfo` bugs and this one all live within ~200 lines
of each other.

## Fix sketch (for whoever takes it)

Two halves, both required:

1. Stop the intrinsic arms early-returning: capture the intrinsic's result and fall through into
   `PARSE_TERM`'s existing operator loop, so it can act as a left operand.
2. Teach `PARSE_FACTOR` the same token set (or route it back up), so it can act as a right operand.

⚠ **`PARSE_TERM` sets `_cfo = 0` on entry.** Any restructure must keep the const-fold flag discipline
exactly right — re-read the v6.4.74 / .80 / .81 CHANGELOG entries first. The failure mode there is
*silent wrong code*, which is far worse than the loud syntax error this issue is about.

## Acceptance criteria

1. `a * f64_from(2)`, `f64_from(2) * a`, and the same for `/ % << >> >>>` all compile and evaluate
   correctly, for the full affected token set above.
2. A tcyr gate covering both operand positions across the tier, **mutation-proven**.
3. **251/251 tcyr byte-identical differential** where behaviour is unchanged — this is a parser
   restructure, so a codegen-neutrality proof is mandatory, not optional.
4. Self-host fixpoint + seed-derive + cross-OS ×4 green.
5. Re-check the `_cfo` shape across every tier afterwards (`grep` the shape, not the operator) — a
   fifth occurrence introduced by this restructure is the obvious risk.

## Documentation

Recorded in vidya as a **compiler gap with a temporary workaround**, explicitly *not* as a language
rule — per `feedback_dont_encode_codegen_bugs_as_language_rules`. If you find a doc telling users to
restructure their code around this, that doc is the bug report.
