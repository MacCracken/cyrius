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
| **Version** | **6.5.9** — two agnos-side filings (`CH_ENDOW` + `spawn_path` env arity; the growable arena) and W1 item 3, the three-state mutex — which turned out **cheaper than pinned**, not blocked. |
| **cycc** | x86 **1,141,784 B** · seed 29,024 B → cybs → cycc byte-identical |
| **Bootstrap / cross-OS** | **ecb** (macOS-arm64) · **ach** (Intel-Mac x86-macho) · **cass** (Windows PE) · **pi** (aarch64) — all `SELFHOST_OK` + VR-01 `LIBTEST_OK` on REAL hardware at 6.5.9 |
| **Gates** | `check.sh` **160 / 0** + **17** shell gate scripts (new: `sync_mutex_three_state` — mutation-proven across THREE axes because each regression class is visible to exactly one: hang / perf tripwire / structural) · cross-OS batched + self-reporting (34 of 258; `CYRIUS_CROSS_OS_FULL=1` for all 258) · release gate GREEN all 5 steps · bench 669/682 ms |
| **Corpus** | **260** `.tcyr` · **99** `lib/*.cyr` · api-surface **4817** · heap **100** regions / 0 overlaps |
| **Active minor** | **v6.5.x** — generated-code quality (opened at v6.5.0; **v6.4.x closed at v6.4.86**) |
| **Shipped this minor** | **.0** file-scoped `public`/`private` · **.1** arity-aware overload dispatch + 4 stdlib folds · **.2** the `ir_const_fold` jump-span miscompile (**IR=3 mismatches 35 → 8**), `xrmdir`, yukti 2.3.0's six agnos ABI defects · **.3** diagnostic lines after `include`, `install.sh` ETXTBSY strand, `version-bump.sh` same-version early exit · **.4** `vec_sort_by`/`vec_select_nth` (the agnosai filing), sigil 3.12.2 / yukti 2.3.2 / sandhi 1.9.8 / mabda 4.0.8 folds, the vacuous sign-efi gate, fold-version table rot · **.5** the `CYRIUS_IR=3` switch-dispatch miscompile (filed as LASE, actually **DCE**) + bayan 1.4.0 · **.6** `sys_exit_group` on all 3 syscall peer families + `async_await_readable_ms`; macOS-x86's untranslated 231 → silent SIGSYS; `proj-tcyr`'s 8-bit exit truncation (256 failures scored PASS); `cyrius fuzz` blind to scaffolded harnesses; sandhi 1.9.9 + vani 1.1.3 folds · **.7** hisab's `alloc_reset` allocator-invalidation; the aarch64 `fchownat` private-alias band (≥1000, both real candidates owned); `#@incdir` file-relative includes with the CVE-16 escape closed at byte-0 + relative-only; `sys_chdir` called-but-undefined; `signal_default` + the `x*` family; subfolder callout for test/bench/fuzz; missing-output-dir bare FAIL · **.8** szal's `thread_join` lost-wakeup deadlock (P1); `thread_create_detached` (210 MB VA leak → 0); the `i64::MIN` formatter class across 12 sites incl. 2 in the compiler + sakshi 2.4.8; agnos `#97 chan_op` minted (`#96` fork deliberately not); `coverage`'s four fail-open/truncation defects; the doc/vet/deny/audit fail-open family; `distlib --all/--check`; the cross-OS gate batched + honest; bayan 1.4.1 fold · **.9** agnos `CH_ENDOW` + `sys_spawn_path_env` (both blocking agnos bite 7); the three-state futex mutex (392→48 ns, and W1 item 3's stated prerequisite was wrong); the growable arena + exhaustion policy — an exhausted arena was a SIGSEGV layers away, and adopting arenas made a leak into a crash |
| **In-flight** | Nothing mid-arc. 6.5.9 is gate-GREEN and complete; the next slot is open. |
| **Next up** | W1 items **5, 7, 8, 9** (items 1, 2, 3, 4, 6 shipped). Then the IR substrate (Slot 3): 8 residual default-vs-IR=3 exit mismatches + the regalloc walls. |
| **Open queue** | **16** issues · **2** proposals · **293** archived (**3 resolved + archived this release**). No UNVETTED items remain — both 6.5.2-era subagent filings have now been vetted and shipped. |
| **W1 status** | **WIDENED 5 → 13 patches (.4 → .16)**. **6 of 13 spent** (.4 item 4; .5 the cyrius-doom IR=3 bug; .6 the agnosai/sandhi pair; .7 item 1; .8 items 2 + 6; **.9 = item 3, the three-state mutex**). ⭐ Item 3 shipped WITHOUT its roadmapped `atomic_swap` prerequisite, which vetting showed was never needed. Items 5, 7, 8, 9 remain, .10–.16 to run them in. |
| **Owed to the maintainer** | Two answered open questions in [roadmap.md](roadmap.md): the **self_compile budget** and **v6.5.x committed item 5** (growth-tax audit) both belong to the later performance track and are to be reviewed **together** when it opens. |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
