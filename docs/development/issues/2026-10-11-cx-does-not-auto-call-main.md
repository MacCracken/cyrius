# cx never auto-calls `fn main`: a program that leaves `main` to the entry epilogue does nothing on cx — OPEN

**Status:** 🟡 **OPEN**. Found 2026-10-11 while fixing
[`2026-10-09-cx-folded-global-reevaluated-int-min-div.md`](2026-10-09-cx-folded-global-reevaluated-int-min-div.md)
(6.7.9, the critical lane's bite 18): that bite's cxvm differential over the `.tcyr` corpus moved the exit codes of
five `fn main` files that no target-side assert ever ran on cx. Reproduced on the lane tip and with every installed
`cycc_cx` / `cxvm` pair (6.6.2 – 6.7.9). Not fixed in that bite: it changes what cx programs compute (a `main` that
never ran starts running, asserts and all), so it is the user's call.
**Placement:** unpinned. For the user to place in the 6.x-line backlog.
**Discovered:** 2026-10-11 during 6.7.9 crit bite 18 (the cx folded-global fix).
**Severity:** Medium. Silent: the program builds, runs nothing of `main`, and exits with the last declaration-zone
global's value (often 0, so a test reads as passed). Only cx is affected.
**Affects:** the cx target, every installed version (6.6.2 – 6.7.9; the fork never had the auto-call).

## Summary

The x86, aarch64 (cross and native), Mach-O and PE drivers end the entry with v5.9.37's auto-call: after the
top-level program and the last-var load, `_find_fn_by_name(S, "main", 4)` and, when the fn has code, `ECALLTO` it,
so `fn main(): i64 { … }` with no top-level call runs and its return value is the exit code (`src/main.cyr`'s
comment above the lookup names the shapes). `src/main_cx.cyr`'s epilogue is only

```cyr
var lv = GLVAR(S);
if (lv >= 0) { EVLOAD(S, lv); }
EEXIT(S);
```

so on cx `main` never runs and the program exits with the last var.

## Reproduction

[`repros/2026-10-11-cx-does-not-auto-call-main.cyr`](repros/2026-10-11-cx-does-not-auto-call-main.cyr): x86 7,
qemu-aarch64 7, cx 3. `fn main(): i64 { return 7; }` alone: x86 7, cx 0.

In the tree, `tests/tcyr/crossos/{chan_try_send,mmap_anon_flag,multi_return,uid_identity}.tcyr` and
`tests/tcyr/math/float_nan_compare.tcyr` define `fn main` and never call it: native x86 prints their summaries
("15 passed, 0 failed" for multi_return); under cxvm they print nothing and exit with a global's value. That is why
`cx_multi_return.sh` and its siblings are shell gates with an explicit `syscall(60, main())`.

## Proposed fix

Port the block to `src/main_cx.cyr` after the last-var load, as `main_aarch64.cyr` has it (`_epi_km_pre` is always 0
on cx: `kernel;` / `shared;` are refused there). Check cx's DCE keeps `main` alive (v5.9.37's "exempt `main` from
DCE"; PE lacked both halves until 6.0.54). Then run the five files above under cxvm: running their `main` on cx for
the first time may surface cx bugs those files never exercised there. A row in a cx gate (`fn main` alone; a global
plus `fn main`; `main` called at top level AND left to the epilogue, which runs twice on every image target).
