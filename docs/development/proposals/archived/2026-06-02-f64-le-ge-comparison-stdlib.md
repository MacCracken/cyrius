# Stdlib f64 comparison helpers: `f64_le` and `f64_ge`

> **LANDED 2026-06-02 (staged for next cut).** `f64_le` / `f64_ge` added
> to `lib/math.cyr` (beside f64_min/f64_max), NaN-correct as proposed.
> Tests in `tests/tcyr/math.tcyr` (6 asserts, 51/51); api-surface snapshot
> updated (2844→2846). avatara can drop its `src/types.cyr` copies once
> this ships. check.sh 82/82.

**Filed:** 2026-06-02 during avatara 2.4.x modernization (cyrius 3.10.0 → 6.0.38 port + hardening sweep)
**Severity:** Stdlib gap — the f64 comparison builtins are incomplete. `f64_lt`, `f64_gt`, `f64_eq` are compiler builtins and `lib/math.cyr` provides `f64_abs`, `f64_clamp`, `f64_min`, `f64_max`, etc., but there is **no less-than-or-equal or greater-than-or-equal** helper anywhere in the toolchain. Every consumer doing f64 range checks rolls its own two-liner.
**Affects:** `lib/math.cyr` (proposed home, beside the existing f64 helpers). No compiler change required — these compose from existing builtins.
**Target slot:** Any v6.x quality-of-life stdlib patch. Small and additive. User direction.

## Summary

Add two functions to `lib/math.cyr`:

```cyrius
# f64 <= : true (1) if a <= b, else 0.
fn f64_le(a, b) { if (f64_lt(a, b) == 1) { return 1; } return f64_eq(a, b); }

# f64 >= : true (1) if a >= b, else 0.
fn f64_ge(a, b) { if (f64_gt(a, b) == 1) { return 1; } return f64_eq(a, b); }
```

(NaN-correct by construction: for any NaN operand `f64_lt`/`f64_gt`/`f64_eq` are all 0, so `f64_le`/`f64_ge` correctly return 0.)

## Why this is more than cosmetic

1. **The builtin set is asymmetric.** A language that ships `f64_lt` and `f64_gt` as builtins but no `f64_le`/`f64_ge` pushes the most common comparison — an inclusive range/threshold check (`0.0 <= x <= 1.0`) — onto every consumer. avatara's entire domain is f64 values in `[0.0, 1.0]`; inclusive bounds are the default need, strict bounds the exception.

2. **Every consumer reinvents it, slightly differently.** avatara defines them in `src/types.cyr`:
   ```cyrius
   fn f64_le(a, b) { if (f64_lt(a, b) == 1) { return 1; } if (f64_eq(a, b) == 1) { return 1; } return 0; }
   fn f64_ge(a, b) { if (f64_gt(a, b) == 1) { return 1; } if (f64_eq(a, b) == 1) { return 1; } return 0; }
   ```
   These are used across `error.cyr` (`require_unit_range`), `compose.cyr` (total-weight guard), and `registry.cyr` (`query_max_trait`, `filter_min_trait`). Any sibling project (bhava, hadara, …) doing bounded-f64 work needs the same and will copy-paste its own.

3. **Collision risk.** A locally-defined `f64_le` is exactly the kind of name that silently shadows ("last definition wins") if the stdlib later adds one under the same name — the same failure class avatara already hit when its `map_new` collided with `hashmap.cyr`'s `map_new`. Standardizing the names upstream now, before consumers proliferate copies, avoids a future shadowing surprise.

## avatara's call sites

[`avatara/src/types.cyr:13-14`](https://github.com/MacCracken/avatara/blob/main/src/types.cyr) defines the pair; consumers within avatara:

- `src/error.cyr` — `require_unit_range` (`f64_lt`/`f64_gt` today, but the inclusive intent is `0 <= v <= 1`)
- `src/compose.cyr` — `f64_le(total, 0.0)` zero-total guard
- `src/registry.cyr` — `query_max_trait`, `filter_min_trait` use `f64_le`/`f64_ge`

## Workaround until landed

avatara keeps its own `f64_le`/`f64_ge` in `src/types.cyr`. When the stdlib versions land, avatara deletes its two definitions (one-line diff) — gated on this proposal. This file marks the consumer-side names so future-claude doing the stdlib add knows what to grep for.
