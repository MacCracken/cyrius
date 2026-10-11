# A whole-struct store into a ZERO-size struct global writes 8 bytes over its neighbour — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the critical lane's bite 1, l679-crit; CHANGELOG [6.7.9]) A store into a zero-size global stores nothing: `_asg_store_slot` (parse.cyr) skips width 0, so the repro exits 77 on x86_64 (default, IR=1, IR=3, DCE=1), aarch64, cx and PE; gate `global_struct_store_width.sh` rows R0 + the tcyr's B0 rows (12 red before).

**Status:** ✅ **RESOLVED in v6.7.9** — see the banner above (filed OPEN: verified 2026-10-09 against the merged 6.7.7 compiler (l677-int @ 881895f6): the repro exits 0 where 77 is right (the 6.7.7 odd-size fix covers 3/5/6/7 B; width 0 still falls back to the 8-byte store); reproduced on 6.7.9 @ cda7fad9).
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
**Discovered:** the 6.7.7 odd-size-global lane (out of scope); filed 2026-10-09.
**Severity:** Low — zero-size structs are rare; silent corruption when they occur
**Affects:** cycc ≤ 6.7.7

## Reproduction

```
struct E { }
var G: E = E { };
var N1: i8 = 77;
fn run(): i64 { var l: E; G = l; return 0; }
var rr = run();
syscall(60, N1);
```
Exits 0 (want 77). `EVSTORE_W` width 0 falls back to the full store (`ESTOC` on x86).

## Proposed fix

Width 0 stores nothing — first proving no other global is registered with `_vars_base` width 0 for another reason.

## Resolution (6.7.9)

**The fix** — `_asg_store_slot` (src/frontend/parse.cyr), the one store every whole-global assignment
takes (the statement, the classic-for step, a multi-value target), stores nothing when the global's
width is 0; the narrowing warning is unchanged. One frontend condition, so every backend (x86 and its
PE / Mach-O forks, aarch64 and Mach-O arm64, cx) is covered; EVSTORE_W is untouched.

**The premise check — width 0 has no other source** (measured on 6.7.9 @ cda7fad9):
- a declaration from an expression (`var G: E = H;`, `= mk();`, either zone) is registered at an
  8-byte slot (`&N1 - &G` = 8), so the declaration replay's `_gv_store` never sees width 0;
- an array global is at least 8 bytes (`var A[0]`: `&N1 - &A` = 8);
- a `const` is registered at width 0 but refuses assignment ("a const has no storage");
- `_gv_clear` writes 0 only to an uncounted registration;
- a zero-size LOCAL owns an 8-byte slot (`&a - &m` = 8), so `m = l` on one is in bounds;
- a multi-value target (`x, G = two();`) refuses a struct by name.

**Rows** — `tests/tcyr/crossos/global_struct_store_width.tcyr` gains the B0 shape: every store form
(a local, a call, a method, a by-value parameter, a global, a wrapped source, a for step, a closure
capture; at top level; on a global declared after the first statement) leaves the seven bytes AT
GB0 untouched, plus the layout (I) and the declaration-zone control (J); 12 store rows red before the
fix on every leg. `tests/gates/codegen/global_struct_store_width.sh` row R0 runs the repro above,
verbatim (`repros/2026-10-09-zero-size-struct-global-store-overwrites-neighbour.cyr`), on x86_64,
aarch64 (qemu), cx (cxvm) and PE (wine): exit 0 before, 77 after. Mutation (the condition removed):
R0 red on all four legs and the 12 B0 rows red on x86 / IR=1 / IR=3 / DCE=1 / aarch64 / cx / PE.

**Not this issue** — a store through a pointer (`*p = l` with `p: *E`) is the 6.7.8 (C2-5) deref
store: an untyped WORD for every operand that is not a narrow scalar `*T`, whatever the pointee's size.
