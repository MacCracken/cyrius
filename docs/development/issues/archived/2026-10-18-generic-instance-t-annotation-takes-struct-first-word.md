# `var y: T = mkp();` (or `y = mkp();`, `p = mkp();` into a `p: *T`) inside a generic fn called with `T = i64` / `u8` keeps the struct's first word — D24 / D27 / D32 never judge a scalar instance's `T` — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GB-19, `d2742a654` — the user's D1 (2026-10-19, the shared stub decision of issues/archived/2026-10-18-generic-base-return-address-of-local-unjudged-at-i64.md): refused as a generic with no scalar instance — and the review fix GB-19r, `710b98b29`. The filing's root cause was wrong (the triage's finding): there is no u8 instance — `g(u)` binds i64 and runs the base, which `_rcv_tp_base` exempted; the scalar instances were judged. The stub scan now marks a struct result over 8 B stored in a name typed by T, so the filed repro (exit 77) is refused at 5:42 naming 'g', with the note "'g' stores a struct result over 8 bytes in 'y', typed by its type parameter" (4:26), on x86_64, aarch64, cx and PE; `g(5)`, `g<i64>(5)`, `g<i32>(5)` (the declaration's words before), `y = mkp();` into a local or a `y: T` parameter, `p = mkp();` into a `*T` / `**T`, a method, wrapped, `fncall0(&mkp)`, an operator, a callee declared below, a forwarder and `&g` the same; `g(q)` at T = Q copies (44), an 8-byte and a `Str` result keep their word. GB-19r: a store THROUGH the pointer, `*p = mkp();`, is not one of D1's lines and compiles as before. Rows: `struct_result_type_refused.sh` TG0 (the filed repro verbatim) – TG12, TG0n, TA1 – TA6d, TGX; `struct_receive_inference_checked.sh` R13 / SA20; `tests/tcyr/crossos/generic_struct_only_lines.tcyr`; mutations MTG1 – MTG7. Filed beside it: `*p = mkp();` through a `*i64` (and a generic's `p: *T` at a scalar T) keeps the first word (issues/archived/2026-10-20-dereference-store-of-struct-result-keeps-first-word.md, the user's D99, wave 4). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 receives lane (unit R3, after the D32 / D33 bites,
326c1b56a) with `build/cycc` built from that tree (x86_64); the lane before the unit (d5adfcd2a) gives the same exits.
**Placement:** 6.7.16 — Break 2, repair 6 (genbind lane, wave 3, unit GB5; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Medium — a silent wrong value (the struct's first word) where the guide says the line is judged per
instance and the same line outside a generic is refused by name.
**Discovered:** 2026-10-18, the receives lane, writing D32's rows (issues/2026-10-17-struct-result-assigned-to-pointer-
or-untyped-scalar-keeps-first-word.md): D32's `*T` test exempts a generic BASE's `*T` as `_rcv_ann_hit` exempts its
`T` (`_rcv_tp_base`, "each instance judges its own binding"), and probing the instances showed none of them judges.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn g<T>(x: T): i64 { var y: T = mkp(); return y; }
fn main(): i64 { var u: u8 = 5; return g(u); }
syscall(60, main());
```

```
rc 0, no diagnostic; exit 77 (333 mod 256, the struct's first word) — `T = u8`
```

The same with `g(5)` (`T = i64`, the base) exits 77; the assignment `var y: T = 0; y = mkp();` through `g<i64>(5)`
exits 77; `var p: *T = 0; p = mkp();` through `g(5)` compiles (exit 0). Outside a generic each line is refused by name
(`var y: u8 = mkp();` — "cannot initialise 'y: u8' from 'mkp', which returns the struct 'Q' - declare 'y: Q' or bind a
field", 6.7.11's D24; the assignment 6.7.14's D27; the `*i64` 6.7.15's D32). The guide (§ struct results) says
"inside a generic fn, `var x: T = mk(9);` is judged per instance (`T = P3` is the struct)".

## Root cause

`_rcv_ann_hit` / `_asa_ptr` (src/frontend/parse_decl.cyr, parse.cyr) exempt a type parameter annotation in the generic's
BASE parse (`_rcv_tp_base`: `_inst_name` 0, T the i64 base), leaving the judgement to each instance. For `T = i64` the
base IS the code that runs, so nothing judges it; a scalar instance (`g$u8`) is not judged either — measured, not
traced: likely the instance's straight-line body is replayed inline at the call (the replay skips the per-definition
checks), or the instance parse resolves `T` to the scalar without reaching `_rcv_ann_refuse`.

## The fix (a sketch)

Judge the annotation where the binding is known: in an instance (or the inline replay of one) whose `T` resolves to a
scalar, and in the base when the call that reaches it binds `T = i64`. `T = P3` (a struct) keeps its copy.
