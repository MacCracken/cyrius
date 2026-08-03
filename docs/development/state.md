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
| **Version** | **6.5.6** — the agnosai/sandhi pair, both filed and fixed on 2026-08-03: `sys_exit_group` (a threaded program's idiomatic epilogue hung — `sys_exit` is exit(2)) and `async_await_readable_ms` (a cooperative server could not be woken to stop), plus three defects found while fixing them and the sandhi 1.9.9 / vani 1.1.3 folds. |
| **cycc** | x86 **1,133,440 B** · seed 29,024 B → cybs → cycc byte-identical |
| **Bootstrap / cross-OS** | **ecb** (macOS-arm64) · **ach** (Intel-Mac x86-macho) · **cass** (Windows PE) · **pi** (aarch64) — all `SELFHOST_OK` + VR-01 `LIBTEST_OK` on REAL hardware at 6.5.6 |
| **Gates** | `check.sh` **153 / 0** + **10** shell gate scripts (new: `exit_group_wrapper`, `async_await_readable_ms`, `scaffold_verb_discovery` — all mutation-proven) · release gate GREEN all 5 steps · bench 643/648 ms |
| **Corpus** | **254** `.tcyr` · **99** `lib/*.cyr` · api-surface **4783** · heap **100** regions / 0 overlaps |
| **Active minor** | **v6.5.x** — generated-code quality (opened at v6.5.0; **v6.4.x closed at v6.4.86**) |
| **Shipped this minor** | **.0** file-scoped `public`/`private` · **.1** arity-aware overload dispatch + 4 stdlib folds · **.2** the `ir_const_fold` jump-span miscompile (**IR=3 mismatches 35 → 8**), `xrmdir`, yukti 2.3.0's six agnos ABI defects · **.3** diagnostic lines after `include`, `install.sh` ETXTBSY strand, `version-bump.sh` same-version early exit · **.4** `vec_sort_by`/`vec_select_nth` (the agnosai filing), sigil 3.12.2 / yukti 2.3.2 / sandhi 1.9.8 / mabda 4.0.8 folds, the vacuous sign-efi gate, fold-version table rot · **.5** the `CYRIUS_IR=3` switch-dispatch miscompile (filed as LASE, actually **DCE**) + bayan 1.4.0 · **.6** `sys_exit_group` on all 3 syscall peer families + `async_await_readable_ms`; macOS-x86's untranslated 231 → silent SIGSYS; `proj-tcyr`'s 8-bit exit truncation (256 failures scored PASS); `cyrius fuzz` blind to scaffolded harnesses; sandhi 1.9.9 + vani 1.1.3 folds |
| **In-flight** | Nothing mid-arc. 6.5.6 is gate-GREEN and complete; the next slot is open. |
| **Next up** | W1's named queue is largely **unstarted** — see the window-status note in [roadmap.md](roadmap.md). Sharpest item: `sys_chdir` is *called* at `lib/regression.cyr:658` and **defined nowhere**, so that `cyrius deps`-shipped stdlib file cannot compile for any consumer reaching `regression_exec_in_dir3`. Then the IR substrate (Slot 3): 8 residual default-vs-IR=3 exit mismatches + the regalloc walls. |
| **Open queue** | **16** issues · **2** proposals · **281** archived (the two 2026-08-03 filings resolved + archived this release). **Three of the 16 are UNVETTED** — filed by subagents during the 6.5.2 triage and never reviewed by a human or by me: `2026-07-29-fmt-int-buf-i64-min`, `2026-07-29-no-portable-xmkdir-in-io-cyr`, `2026-07-29-mutex-unlock-unconditional-futex-wake`. Treat their claims as unverified. |
| **W1 status** | **3 of 5 patches spent** (.4 = item 4; .5 displaced by the cyrius-doom IR=3 bug; .6 = the agnosai/sandhi pair). Items 1, 2, 3, 5, 6, 7, 8, 9 unstarted with .7–.8 left — **oversubscribed; widen or move the remainder to W2 is a maintainer call.** |
| **Owed to the maintainer** | Two answered open questions in [roadmap.md](roadmap.md): the **self_compile budget** and **v6.5.x committed item 5** (growth-tax audit) both belong to the later performance track and are to be reviewed **together** when it opens. |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
