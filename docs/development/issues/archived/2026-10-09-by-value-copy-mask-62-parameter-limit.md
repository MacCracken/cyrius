# `_pm_copies` answers 0 past parameter 61: a by-value struct at parameter 62+ is neither snapshotted nor treated as copied — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the critical lane's bite 16, l679-crit; CHANGELOG [6.7.9]) An ordinal past 61 lives in the fn's copies ROW (util.cyr `_bvhi_*`, a lazy byte-per-ordinal row beside the 62-bit mask; the kind row's byte is full): pass 1 (`_bvcp_note`, `_tup_bvcp`) and the definition (`_sptr_params_copy`) write it through `_bvcp_bit`, each replacing the record whole, and `_pm_copies` reads it. `r62(.., b, bump(&b))` reads 1 (was 11) on x86, aarch64, cx and PE; the address no longer escapes, so a self tail call beside it keeps its `jmp`. Rows in tests/tcyr/crossos/by_value_arg_evaluation_order.tcyr and fn_redefinition_last_wins.tcyr, mutation-proven (the two gates' ledgers).

**Status:** ✅ **RESOLVED in v6.7.9**. See the banner above and *Resolution* below. Reproduced on the 6.7.9 lane tip
@ 3ec68b33 before the fix: a 64-parameter fn with `s: Big` at ordinal 62 and `bump(&b)` after it exits 11 where 1
is right (ordinal 61: 1). As filed: 🟡 OPEN — reported 2026-10-09 by the 6.7.7 call-arguments lane from the code
(GFBVCP is a 62-bit mask); not reproduced with a 63-parameter fn.
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
**Discovered:** the 6.7.7 call-arguments lane (out of scope); filed 2026-10-09.
**Severity:** High (the 6.7.9 selection) — a silent wrong value, though it needs a fn with 63+ parameters (filed Low)
**Affects:** cycc ≤ 6.7.7

## Summary

The callee-copies mask `GFBVCP` has 62 bits, so `_pm_copies` cannot answer for a parameter ordinal past 61: the
6.7.7 by-value argument snapshot and `_sarg_escapes` both skip such a parameter. fns take any number of arguments
(CLAUDE.md), so the representation is the limit.

## Proposed fix

A per-parameter-row bit (the parameter table) instead of the fixed mask, with a 64-parameter row.

## Resolution (6.7.9)

The copies record keeps its 62-bit mask for ordinals 0..61 and gains a per-fn COPIES ROW for the rest
(`_fnt_bvhi`, util.cyr: per fn 0, or [capacity][one byte per ordinal], lazy at the max fn cap, so the brk layout
does not move). It is its own table, not a bit in the kind row (`_pm_row_*`): that row's byte is full (kinds
1..32 plus the SIMD code in bits 6-7), and pass 2 rebuilds it at every definition, where this record is never
written for a redefined fn. The row helpers are now one shape over a table (`_prow_get` / `_prow_at` /
`_prow_reset`), shared by both rows.

- `_bvcp_bit(fi, m, pc)` is the one writer: the mask bit below 62, the row byte from 62.
- Pass 1: `_prescan_params` clears the fn's row before the scan (the mask is replaced whole by its S64, the row
  is cleared to match); `_bvcp_note` takes the address-passed test from `_psid_addr` (the kind row past 61) and
  writes through `_bvcp_bit`, as does `_tup_bvcp`; an `async` or possible-`#naked` fn clears both
  (`_bvcp_none`).
- Pass 2: `_sptr_params_localize` names the fn the record is written for, -1 for a redefinition (nothing is
  written, as before for the mask); it clears that fn's row and `_sptr_params_copy` writes through `_bvcp_bit`.
- `_pm_copies` reads the row past 61. `_sarg_snap_ty` (the copy where the argument stands) and `_sarg_escapes`
  (an address the callee copies does not escape) follow.

Rows: tests/tcyr/crossos/by_value_arg_evaluation_order.tcyr — a struct at 61 (control), 62, 66 of 70, a tail
call, a callee defined after the call (pass 1), a by-value tuple (pass 1), a generic instance (pass 2 only), a
method's argument, an f64v2 at 62 (Win64 copies it in), an 8 B struct and a `*Big` at 62 (controls), a self tail
call 1,000,000 deep beside the address, and a top-level global; tests/tcyr/crossos/fn_redefinition_last_wins.tcyr
— the by-value / `*T` redefinition pair at 62 in both orders. On x86, CYRIUS_IR=3, CYRIUS_DCE=1, aarch64 (qemu),
cx and PE (wine). Before the fix: 8 rows read 11 on x86, aarch64 and cx, 9 on PE (the f64v2 too), the walk
crashed (x86, aarch64, PE: the address escaped, so every tail call in the fn lost its `jmp`), and
`rd_kp62_check` over-diverted (72). Mutations (scratch trees, the gates run there) are in the ledgers of
tests/gates/codegen/by_value_arg_copy.sh (M13-M16) and tests/gates/frontend/fn_redefinition_binds_last.sh (m-o).
The corpus differential (671 sources, default and CYRIUS_DCE=1, the pre-fix stage-1 compiler against the fixed
one) is byte-identical except the two .tcyr files that carry the new rows; their HEAD versions are identical too.
