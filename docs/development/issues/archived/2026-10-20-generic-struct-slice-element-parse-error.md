# A generic struct instance as a slice element (`[Box<i64>]`, `slice<Box<i64>>`, `[*Box<i64>]`) is a parse error — "expected ']', got '<'" — where `[Pt]` / `[*Pt]` declare — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FF-48, `4ae0873f3`, and the review fix FF-48r, `f33107668` — the user's D89 (2026-10-20): declare it, as `[Pt]` does. `_tn_slice_gen` / `_tn_slice_gptr` (src/frontend/parse_types.cyr) read the instance as `var b: Box<i64>` reads it, its width the instance's size. The filed repro compiles and exits 7 (it was "3:26: expected ']', got '<'" + three more); `[Box<Zork>]` is one "unknown type 'Zork' as a type argument", `[Box<i64, i64>]` D5's line once; `>>` / `>>>` closes and a generic's `[Two<T>]` per instance work. FF-48r: a subscript read of an element no slice helper serves (24 B `[Box<Pt>]`, 12 B `[W<i32>]`, 24 B `[P3]`) is refused by name — "cannot subscript 'e': a slice subscript reads a 1-, 2-, 4-, 8- or 16-byte element - this one is 24 bytes: read at slice_ptr(&s) + i * sizeof(T)" — where it was a false "requires include lib/slice.cyr". Rows: tests/tcyr/crossos/slice_generic_element.tcyr (15 / 15 on x86_64 plain / IR=1 / IR=3 / DCE=1, qemu-aarch64, cxvm, wine); generic_type_arg_unknown_refused.sh NS0 (the filed repro verbatim) – NS4, NSX; slice_position_refused.sh R14a – R14f, R14s; mutants RED. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — met 2026-10-20 by the 6.7.16 gensig lane (unit GS4) while applying the user's D7 to a slice
element (issues/archived/2026-10-18-non-generic-type-arguments-unrefused-in-remaining-positions.md: `[Pt<i64>]`, a NON-generic
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
