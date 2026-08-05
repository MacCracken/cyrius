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
| **Version** | **6.5.7** — the repair release: hisab's `alloc_reset` allocator-invalidation (High), agnosai's syscall-wrapper gaps, the `include`-resolution limit that forced agnos into a shell workaround, and the tool defects found alongside them. |
| **cycc** | x86 **1,141,696 B** · seed 29,024 B → cybs → cycc byte-identical |
| **Bootstrap / cross-OS** | **ecb** (macOS-arm64) · **ach** (Intel-Mac x86-macho) · **cass** (Windows PE) · **pi** (aarch64) — all `SELFHOST_OK` + VR-01 `LIBTEST_OK` on REAL hardware at 6.5.7 |
| **Gates** | `check.sh` **156 / 0** + **12** shell gate scripts (new: `syscall_wrapper_pass`, `include_dir_resolution` — both mutation-proven, five mutations each caught on its intended axis) · **32** vr01 tests per cross-OS host (new: `vr01_syscall_wrappers`, which turned the gate red on ecb AND ach and found **7** host-invisible defects) · release gate GREEN all 5 steps · bench 649/670/701 ms (same binary — spread exceeds the release delta) |
| **Corpus** | **254** `.tcyr` · **99** `lib/*.cyr` · api-surface **4783** · heap **100** regions / 0 overlaps |
| **Active minor** | **v6.5.x** — generated-code quality (opened at v6.5.0; **v6.4.x closed at v6.4.86**) |
| **Shipped this minor** | **.0** file-scoped `public`/`private` · **.1** arity-aware overload dispatch + 4 stdlib folds · **.2** the `ir_const_fold` jump-span miscompile (**IR=3 mismatches 35 → 8**), `xrmdir`, yukti 2.3.0's six agnos ABI defects · **.3** diagnostic lines after `include`, `install.sh` ETXTBSY strand, `version-bump.sh` same-version early exit · **.4** `vec_sort_by`/`vec_select_nth` (the agnosai filing), sigil 3.12.2 / yukti 2.3.2 / sandhi 1.9.8 / mabda 4.0.8 folds, the vacuous sign-efi gate, fold-version table rot · **.5** the `CYRIUS_IR=3` switch-dispatch miscompile (filed as LASE, actually **DCE**) + bayan 1.4.0 · **.6** `sys_exit_group` on all 3 syscall peer families + `async_await_readable_ms`; macOS-x86's untranslated 231 → silent SIGSYS; `proj-tcyr`'s 8-bit exit truncation (256 failures scored PASS); `cyrius fuzz` blind to scaffolded harnesses; sandhi 1.9.9 + vani 1.1.3 folds · **.7** hisab's `alloc_reset` allocator-invalidation; the aarch64 `fchownat` private-alias band (≥1000, both real candidates owned); `#@incdir` file-relative includes with the CVE-16 escape closed at byte-0 + relative-only; `sys_chdir` called-but-undefined; `signal_default` + the `x*` family; subfolder callout for test/bench/fuzz; missing-output-dir bare FAIL |
| **In-flight** | Nothing mid-arc. 6.5.7 is gate-GREEN and complete; the next slot is open. |
| **Next up** | W1 items **2, 3, 5, 6, 7, 8, 9** (item 1 closed at .7, item 4 at .4). Sharpest: item 6 (`distlib --all`/`--check`) goes EARLY, before this window's re-vendors; item 2 is the `i64::MIN` formatter class — all 7 sites, and `lib/sakshi.cyr` is a FOLD (patch upstream, never the fold). Then the IR substrate (Slot 3): 8 residual default-vs-IR=3 exit mismatches + the regalloc walls. |
| **Open queue** | **16** issues · **2** proposals · **289** archived (**8 resolved + archived this release**, each verified against live code rather than its own claim — the count was already reading 16 while 24 were open). **Two of the 16 remain UNVETTED** — filed by subagents during the 6.5.2 triage and never reviewed: `2026-07-29-fmt-int-buf-i64-min`, `2026-07-29-mutex-unlock-unconditional-futex-wake`. Treat their claims as unverified. (The third, `no-portable-xmkdir-in-io-cyr`, was vetted and **shipped** this release.) |
| **W1 status** | **WIDENED 5 → 13 patches (.4 → .16), maintainer decision 2026-08-03**; downstream shifts **+8** (IR substrate .17–.18, W2 .19–.21, closeout band .40+). Rationale: these patch fixes are the early moat the **agnosai port** is moving through. **4 of 13 spent** (.4 = item 4 `vec_sort_by`; .5 displaced by the cyrius-doom IR=3 bug; .6 = the agnosai/sandhi pair; **.7 = item 1, the syscall-wrapper pass, COMPLETE end-to-end** incl. sub-item (x) — yukti's `_yk_mkdir` bridge was already vendored at 2.3.2 — and the `vr01_`-named tcyr the item asked for, which is what surfaced the seven Darwin defects). Items 2, 3, 5, 6, 7, 8, 9 unstarted, .8–.16 to run them in. Sequencing: **item 6 (`distlib --all`/`--check`) goes EARLY, before this window's re-vendors**; items 8/9 are fold-ins. |
| **Owed to the maintainer** | Two answered open questions in [roadmap.md](roadmap.md): the **self_compile budget** and **v6.5.x committed item 5** (growth-tax audit) both belong to the later performance track and are to be reviewed **together** when it opens. |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
