# Memory-safety parity gaps + heap-registry rot — CVE-24/25/26/27, AR-03

**Discovered:** 2026-06-10 during the deep-dive review ([`docs/audit/2026-06-10-deep-dive-review.md`](../../../audit/2026-06-10-deep-dive-review.md))
**Severity:** Medium
**Affects:** cycc front-end + stdlib allocators + PE emitter + heap map 6.1.31

## Summary

Several write paths lack the loud-cap guard their siblings have, plus the
compiler's heap registry has drifted out of sync with the enforced caps.

## CVE-24 — locals registration has no cap (P2)

`fn_local_names` occupies `0x191000..0x191800` (`main.cyr:77-78`) = 256 i64 slots
before `local_depths` at `0x191800`. Registration writes
`S64(S+0x191000+li*8, noff)` and bumps via `SFLC(S, li+1)` (`parse_decl.cyr:968`;
more sites in parse.cyr/parse_ctrl.cyr); `GFLC/SFLC` (`util.cyr:126-127`) are
unguarded stores and no site checks `li<256`. A function with >256 locals
silently writes names into the scope-depth array and beyond — unlike the loud
fn(8192)/var(8192)/token caps.

**Fix:** hard-error (ERR_MSG + exit) when `GFLC` reaches 256 at the registration
sites or inside `SFLC`; document the 256 cap in the heap map.

## CVE-25 — `_sb_grow` discards the grow-OOM return code (P2)

`_sb_grow` calls `_sb_grow_a(...)` into `var rc` then unconditionally
`return 0;` (`str.cyr:469-470`), dropping the `-1` OOM signal. `str_builder_add`
(`:488`), `_add_cstr` (`:510`), `_putc` (`:524`), and the int variant (`:548`)
all `memcpy`/`store8` into `buf+len` immediately after — on allocator OOM the
buffer was not grown but `len+n` now exceeds cap → write past the old allocation
= silent heap corruption. The `_a` variants already propagate rc.

**Fix:** have `_sb_grow` return `_sb_grow_a`'s rc, and make the back-compat
builders abort (write + exit, like `vec_push`) on grow failure.

## CVE-26 — `alloc_agnos` alloc() lacks the size guard the other 3 backends have (P2)

`alloc_windows`/`alloc_macos`/`alloc.cyr` all reject `size<=0` and `size>ALLOC_MAX`
before bumping. `alloc_agnos.cyr:61-73` does neither: a negative size yields
negative `asz`, the overflow guard `_heap_ptr+asz>_heap_end` is false, so the
bump pointer moves **backward** and the next alloc overlaps already-handed-out
memory. AGNOS is an active userspace target.

**Fix:** port the two-line guard (`if(size<=0)return 0; if(size>ALLOC_MAX)return 0;`)
to `alloc_agnos.cyr:61`. Note `ALLOC_MAX` is also undefined in this file — add it.

## CVE-27 — PE import registries are fixed 32-slot/512-B with no bounds check (P2)

`_pe_imp_name_offs[256]` = 32 i64 slots and `_pe_imp_name_buf[512]`
(`pe/emit.cyr:127-128`); same sizes for the pending queue (`:259-260`).
`_pe_imp_add` (`:231`) and `_pe_pending_imp_add` (`:735`) write
`+_pe_imp_count*8`/`+_pe_imp_buf_pos` with **no cap test**. There are 34
`_pe_ensure_*` kernel32 helpers (verified) plus ExitProcess, shell32, dxgi, and
any user `#pe_import` — a Windows program touching most kernel32 wrappers already
exceeds 32 imports / ~512 B of long names.

**Fix:** add a hard-error cap check (same pattern as RECFIX) to both add fns, or
grow `offs` to ≥64 slots and the name buf to ≥1024 B. The auto-import floor is
already at the cap.

## AR-03 — heap-registry integrity rot (P2)

The heap map promises fixup cap `1048576` "raised v5.7.7" (`main.cyr:328-334`)
and sizes the region 16 MB, but RECFIX (`runtime.cyr:247`) + 4 x86 + 6 aarch64 +
1 PE emit sites enforce **262144**; only `parse_expr.cyr:360/1151` allow
1048576 — which limit fires depends on call path, and ~12 MB of region is
unreachable. fn-table labels say `4096/[32768]` but usage differs; there is an
undocumented region (`0x19E000`) with an off-by-one overlap; the cap-drift gate
covers 3 of 99 regions.

**Fix:** unify the fixup cap at 1048576 (one literal in RECFIX + 11 emit sites),
fix the map labels + `ERR_EXPECT` text, document `0x19E000` + cap `jtc<1023`, and
extend `_cap_drift_gate` to the fn/fixup/codebuf/output caps — the regions with
proven contention. Pairs with the growable-table migration in
[monomorphization-substrate-prereqs](2026-06-10-monomorphization-substrate-prereqs.md).

## Status

Filed 2026-06-10. **Four of five RESOLVED v6.1.38 (Phase F pack F3):** CVE-25
(`_sb_grow` OOM propagation + `_sb_die`), CVE-26 (`alloc_agnos` pre-lock size
guards + local `ALLOC_MAX`), CVE-27 (PE import-registry count+name-buffer
bounds; the "32-slot" premise was a wrong comment — global `var x[N]`=N i64
slots, so the arrays already held 256/4096), and AR-03 (fixup cap unified
262144→1048576 to match its 16 MiB region; `jump_target_tbl` off-by-one fixed
across all 4 accessors). Self-host byte-identical x86/aarch64/PE; ecb/ach/pi/cass
`SELFHOST_OK`; check.sh 89/89; adversarial-review-the-diff caught the jump fix
initially touching only 1 of 4 accessors. See CHANGELOG [6.1.38].

**CVE-24 RE-SCOPED + DEFERRED.** The audit premise here ("locals registration
has no cap → add a count guard") was wrong — `SFLC`/`local_cnt` counts
stack-frame *slots*, not variables, so a naive cap breaks sanctioned large stack
frames (`stack_var.tcyr::big_frame`'s 16 KB `__chkstk` frame). The real fix is a
redesign. Tracked in
[`2026-06-12-locals-table-slot-indexed-overflow.md`](2026-06-12-locals-table-slot-indexed-overflow.md).
