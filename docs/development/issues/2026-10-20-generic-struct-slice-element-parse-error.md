# A generic struct instance as a slice element (`[Box<i64>]`, `slice<Box<i64>>`, `[*Box<i64>]`) is a parse error — "expected ']', got '<'" — where `[Pt]` / `[*Pt]` declare — OPEN

**Status:** 🟡 **OPEN** — met 2026-10-20 by the 6.7.16 gensig lane (unit GS4) while applying the user's D7 to a slice
element (issues/2026-10-18-non-generic-type-arguments-unrefused-in-remaining-positions.md: `[Pt<i64>]`, a NON-generic
struct given arguments, is now D6's line at the name). Measured on the lane's base (1e3aad696) and head, x86_64:
identical. Not that filing's surface (a generic struct's own list is no D6 / D7 shape), and whether the shape should
declare is the user's call, so it is filed, not fixed.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 gensig lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; f16 lane, wave 4, unit FG3) — never 7.x.
**Decision (user, 2026-10-20, the found issues' round):** D89 — Declare it, as `[Pt]` does.
**Severity:** Low — refused (no miscompile), but by a parse error that names no type, and `slice<..>` cascades.
**Kind:** language (a generic instance in a slice element position: declare it as `[Pt]` declares, or refuse it by
name — the user's call).

## Reproduction

```cyrius
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn s(): i64 { var e: [Box<i64>] = 0; var f: slice<Box<i64>> = 0; var g: [*Box<i64>] = 0; return 7; }
fn main(): i64 { return s(); }
```

```
error:<source>:3:26: expected ']', got '<'
```

Each alone: `var e: [Box<i64>] = 0;` "3:26: expected ']', got '<'"; `var f: slice<Box<i64>> = 0;` "3:31: expected '=',
got '<'" and "3:35: undefined variable 'i64'"; `var g: [*Box<i64>] = 0;` "3:27: expected ']', got '<'". Controls:
`[Pt]`, `[*Pt]`, `slice<*i32>` declare (exit 7).

## Root cause

The slice element readers (`_tn_slice_w` for `[T]` / `slice<T>`, `_tn_slice_ptr_el` for `[*T]`, called from
PARSE_VAR, src/frontend/parse_decl.cyr) read ONE name token and leave the cursor after it; a generic struct's `<..>`
is not read (6.7.16's D7 steps a non-generic one's after refusing it), so the caller meets the `<`.

## Fix direction

Either read the instance (`_gen_ann_sid`, its size as the element width, as `var b: Box<i64>` sizes it) or refuse it
by name ("a generic struct instance cannot be a slice element yet") with the list stepped. Rows: the three spellings
above; `[Box<Pt>]`; a generic body's `[Box<T>]`.
