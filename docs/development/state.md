# Cyrius — Current State

> Refreshed every release. This file is **state** (volatile) — a SNAPSHOT of where the
> project is right now, bumped via `version-bump.sh`. It deliberately holds **no
> per-release narrative** (canonical in [`CHANGELOG.md`](../../CHANGELOG.md)) and **no
> backlog** (the full pin sequence + length map is in [`roadmap.md`](roadmap.md); parked /
> v7+ items in [`roadmap-future.md`](roadmap-future.md)). CLAUDE.md holds the durable
> preferences / process / procedures.

## Current state

| | |
|---|---|
| **Version** | **6.5.8** — the repair release: szal's `thread_join` deadlock (P1), the `i64::MIN` formatter class (12 sites, not the 7 roadmapped), thread detach/leak, agnos `#97 chan_op`, and a tool sweep (coverage, the fail-open verb family, `distlib --all/--check`, the cross-OS gate). |
| **cycc** | x86 **1,141,696 B** · seed 29,024 B → cybs → cycc byte-identical |
| **Bootstrap / cross-OS** | **ecb** (macOS-arm64) · **ach** (Intel-Mac x86-macho) · **cass** (Windows PE) · **pi** (aarch64) — all `SELFHOST_OK` + VR-01 `LIBTEST_OK` on REAL hardware at 6.5.8 |
| **Gates** | `check.sh` **159 / 0** + **16** shell gate scripts (new: `thread_join_single_load`, `coverage_corpus_and_failopen`, `distlib_all_profiles`, + verb-hygiene axes — all mutation-proven) · cross-OS now BATCHED (one ssh/host) and prints its own coverage (34 of 258; `CYRIUS_CROSS_OS_FULL=1` for all 258, 75 s on ecb) · release gate GREEN all 5 steps · bench 672/678 ms |
| **Corpus** | **258** `.tcyr` · **99** `lib/*.cyr` · api-surface **4809** · heap **100** regions / 0 overlaps |
| **Active minor** | **v6.5.x** — generated-code quality (opened at v6.5.0; **v6.4.x closed at v6.4.86**) |
| **Shipped this minor** | **.0** file-scoped `public`/`private` · **.1** arity-aware overload dispatch + 4 stdlib folds · **.2** the `ir_const_fold` jump-span miscompile (**IR=3 mismatches 35 → 8**), `xrmdir`, yukti 2.3.0's six agnos ABI defects · **.3** diagnostic lines after `include`, `install.sh` ETXTBSY strand, `version-bump.sh` same-version early exit · **.4** `vec_sort_by`/`vec_select_nth` (the agnosai filing), sigil 3.12.2 / yukti 2.3.2 / sandhi 1.9.8 / mabda 4.0.8 folds, the vacuous sign-efi gate, fold-version table rot · **.5** the `CYRIUS_IR=3` switch-dispatch miscompile (filed as LASE, actually **DCE**) + bayan 1.4.0 · **.6** `sys_exit_group` on all 3 syscall peer families + `async_await_readable_ms`; macOS-x86's untranslated 231 → silent SIGSYS; `proj-tcyr`'s 8-bit exit truncation (256 failures scored PASS); `cyrius fuzz` blind to scaffolded harnesses; sandhi 1.9.9 + vani 1.1.3 folds · **.7** hisab's `alloc_reset` allocator-invalidation; the aarch64 `fchownat` private-alias band (≥1000, both real candidates owned); `#@incdir` file-relative includes with the CVE-16 escape closed at byte-0 + relative-only; `sys_chdir` called-but-undefined; `signal_default` + the `x*` family; subfolder callout for test/bench/fuzz; missing-output-dir bare FAIL · **.8** szal's `thread_join` lost-wakeup deadlock (P1); `thread_create_detached` (210 MB VA leak → 0); the `i64::MIN` formatter class across 12 sites incl. 2 in the compiler + sakshi 2.4.8; agnos `#97 chan_op` minted (`#96` fork deliberately not); `coverage`'s four fail-open/truncation defects; the doc/vet/deny/audit fail-open family; `distlib --all/--check`; the cross-OS gate batched + honest; bayan 1.4.1 fold |
| **In-flight** | Nothing mid-arc. 6.5.8 is gate-GREEN and complete; the next slot is open. |
| **Next up** | W1 items **3, 5, 7, 8, 9** (items 1, 2, 4, 6 shipped). The mutex three-state rewrite (item 3) needs `atomic_swap` + a value-returning CAS in `lib/atomic.cyr` — neither exists. Then the IR substrate (Slot 3): 8 residual default-vs-IR=3 exit mismatches + the regalloc walls. |
| **Open queue** | **18** issues · **2** proposals · **290** archived (the vr01-glob issue resolved + archived; **1 NEW filed** — the first measurement of the cross-OS blind region, 23 of 258 failing on ecb, with the list). **Two remain UNVETTED**: `2026-07-29-fmt-int-buf-i64-min` was vetted and **SHIPPED** this release; `2026-07-29-mutex-unlock-unconditional-futex-wake` was vetted and is a PERF gap, not a correctness bug — its roadmapped three-state prerequisite is wrong and it is cheaper than pinned. |
| **W1 status** | **WIDENED 5 → 13 patches (.4 → .16), maintainer decision 2026-08-03**; downstream shifts **+8**. **5 of 13 spent** (.4 = item 4 `vec_sort_by`; .5 displaced by the cyrius-doom IR=3 bug; .6 = the agnosai/sandhi pair; .7 = item 1 the syscall-wrapper pass, complete end-to-end; **.8 = items 2 (`i64::MIN`, and it was 12 sites not 7) + 6 (`distlib --all/--check`)**). Items 3, 5, 7, 8, 9 remain, .9–.16 to run them in. ⚠ Item 3's stated prerequisite is WRONG — vetting found the mutex defect is a perf gap, not a correctness bug, and materially cheaper than pinned; re-scope before starting. |
| **Owed to the maintainer** | Two answered open questions in [roadmap.md](roadmap.md): the **self_compile budget** and **v6.5.x committed item 5** (growth-tax audit) both belong to the later performance track and are to be reviewed **together** when it opens. |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
