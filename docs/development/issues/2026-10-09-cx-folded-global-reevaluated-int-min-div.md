# cx: a constant-folded global initializer is re-evaluated at run time, so `var Q = INT_MIN / -1;` kills cxvm with SIGFPE — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09. `tests/tcyr/crossos/const_fold_int_min_div.tcyr`, compiled by a
`src/main_cx.cyr` compiler and run under a `programs/cxvm.cyr` VM (both built by the merged 6.7.7 tip `cycc_merged`,
tree @ 06bd8981), **exits 136 (SIGFPE, core dumped)**. The same file exits 0 natively on x86_64, under qemu-aarch64
(the tree's `src/main_aarch64.cyr` cross compiler) and under wine (the `src/main_win.cyr` PE compiler; "13 passed, 0
failed"). The same cx compiler and VM built from the **6.7.6 tag's** `src/` and `programs/` also exit 136, so it
predates 6.7.7. The minimal repro is
[`repros/2026-10-09-cx-folded-global-reevaluated-int-min-div.cyr`](repros/2026-10-09-cx-folded-global-reevaluated-int-min-div.cyr):
cx 136, x86 7, qemu-aarch64 7.
**Placement:** 6.7.12 — Break 2, repair 3 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
Its global-initialisers lane owns the same `_CF_TRY` static-init path (the const-init issue placed there), and cxvm
is in that release's host list via the standard legs.
**Discovered:** a 6.7.7 lane's cxvm run of `tests/tcyr/crossos/` (out of scope; it predates 6.7.7); filed
2026-10-09.
**Severity:** Low. Only cx is affected, and the trigger is narrow: a folded top-level initializer whose run-time
re-evaluation traps, which on x86-hosted cxvm means `INT_MIN / -1` or `INT_MIN % -1`. For every other folded value
the run-time store writes the value the fold already produced, at the cost of startup work. The crossos release-gate
leg does not run cx, so nothing has flagged it.
**Affects:** the cx target from 6.6.20 (when the folder learned to take a -1 divisor and this test landed) through
6.7.6 and the merged 6.7.7 tip. The re-evaluation itself is older: the cx opt-out is v6.4.74-era.

## Summary

6.6.20 (RPD-06) taught the top-level constant folder (`_CF_TERM`) to fold `INT_MIN / -1` as the wrapping negation and
`INT_MIN % -1` as 0, so a declaration-zone `var Q = (0 - 0x7FFFFFFFFFFFFFFF - 1) / (0 - 1);` no longer kills the
compiler. On every image target a folded nonzero value takes the static-init path: it is baked into the data image
and no run-time code evaluates the expression. **cx opts out of that path.** It keeps the deferred run-time store,
which re-parses and **emits the original division**. cxvm executes it with its own `/` (an x86 `idiv`, since cxvm is
an x86 program on an x86 host), and `idiv` traps on `INT_MIN / -1`.

Arrays are not affected. `ARR` / `EARR` in the test, whose elements fold the same expressions, are baked into the
.cyx var data (`_gai_bake`) and run clean on cx. Only the scalar `QMIN` / `QHEX` globals trap.

## Reproduction

```sh
cat src/main_cx.cyr   | build/cycc > /tmp/cycc_cx && chmod +x /tmp/cycc_cx
cat programs/cxvm.cyr | build/cycc > /tmp/cxvm    && chmod +x /tmp/cxvm
/tmp/cycc_cx < tests/tcyr/crossos/const_fold_int_min_div.tcyr > /tmp/t.cyx
/tmp/cxvm < /tmp/t.cyx; echo $?        # 136 — "the monitored command dumped core" under timeout
```

Bisected by initializer (one global per file, under cxvm):

| initializer | cx exit |
|---|---|
| `var QMIN = (0 - 0x7FFFFFFFFFFFFFFF - 1) / (0 - 1);` | **136** |
| `var QHEX = 0x8000000000000000 / (0 - 1);` | **136** |
| `var QPOS = 10 / (0 - 1);` (`syscall(60, 0 - QPOS)`) | 10 (right) |
| `var ARR: i64[3] = { 1, INT_MIN % -1, INT_MIN / -1 };` | clean |
| `var EARR: i64[2] = { (0 - CF_MAX - 1) / (0 - 1), … };` | clean |

A run-time `INT_MIN / -1` inside a fn exits 136 on cx and on native x86 alike (x86 `idiv` semantics; aarch64 `sdiv`
gives INT_MIN). That is ordinary run-time division and is not this bug. This bug is that a value the compiler
already folded is computed again at run time on cx only.

## Root cause

`PARSE_GVAR_REG`, `src/frontend/parse_decl.cyr:4649`–`4657`:

```cyr
var fv = _CF_TRY(S, GTI(S), 5);
if (_cf_ok == 1) {
    cf_has = 1;
    cf_val = fv;
    if (_TARGET_CX != 1 && fv != 0) {
        sit_lit = 1;
        sit_val = fv;
    }
}
```

The comment above it (`:4628`–`4632`) gives the reason: "the cx bytecode backend has no file-image var area; its
gvars live in cxvm-allocated memory zeroed at cxvm startup. Skipping the runtime store would leave them zero." That
stopped being true twice:

- 6.6.6: `_gv_cx_prestore` (`parse_decl.cyr:4183`, called at `:5130`) stores every recorded constant global's
  folded value (`_vgsi_base`, recorded for cx at `:4765`–`4767`) before the replay.
- 6.6.16: `src/main_cx.cyr:537`–`544` writes a real var-data image (`vdat`, `_gai_bake`) that cxvm copies into the
  guest (`programs/cxvm.cyr:172`).

So cx writes the folded value first and then, with `sit_lit == 0`, `_gv_defer` (`:4774`) queues the original tokens
for the EMIT_GVAR_INITS replay. The replay evaluates the expression, and cxvm's `op == 19` (`programs/cxvm.cyr:323`,
`cx_reg_get(rb) / cx_reg_get(rc)`) traps.

## Proposed fix

Let cx take the static-init path for a folded nonzero scalar too, now that it has both an image and the prestore:

1. **Bake it:** in `src/main_cx.cyr`, write each `_vgsi_base` value into `vdat` at the global's var offset, beside
   `_gai_bake`, and drop the `_TARGET_CX != 1` guard so `sit_lit` / `sit_val` are set and no replay entry is queued.
   cx then matches the five image targets (no run-time evaluation of a folded initializer), and `_gv_cx_prestore`'s
   EMOVI + store for those globals becomes redundant. Keep it for the shadow / redeclaration cases it was written
   for, or retire it if the bake covers them; check the orderings its 6.6.6 comment names.
2. **Or the smaller fix:** keep the cx replay but have it store `cf_val` (EMOVI) instead of re-parsing the
   expression.

Either way, refresh the stale comment at `parse_decl.cyr:4628`. Add a cx row (a shell gate under cxvm, as
`tests/gates/codegen/cx_*.sh` do) for `var Q = INT_MIN / -1;` and `var R = INT_MIN % -1;` exiting cleanly. Optionally
also have the cx leg run `tests/tcyr/crossos/const_fold_int_min_div.tcyr`, which now compiles under cx with
`lib/assert.cyr`. cxvm's run-time `/` and `%` keep host semantics, the same as native x86, so they are not changed
here.
