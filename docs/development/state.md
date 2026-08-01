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
| **Version** | **6.5.5** — the `CYRIUS_IR=3` switch miscompile cyrius-doom filed (an `IR_RAW_EMIT` marker stops shielding at the next recorded node; it was DCE, not LASE), plus the bayan 1.4.0 fold. |
| **cycc** | x86 **1,133,440 B** · seed 29,024 B → cybs → cycc byte-identical |
| **Bootstrap / cross-OS** | **ecb** (macOS-arm64) · **ach** (Intel-Mac x86-macho) · **cass** (Windows PE) · **pi** (aarch64) — all `SELFHOST_OK` + VR-01 `LIBTEST_OK` on REAL hardware at 6.5.5 |
| **Gates** | `check.sh` **150 / 0** + **10** shell gate scripts (new: `ir3_switch_dce`) · release gate GREEN all 5 steps · bench 644 ms |
| **Corpus** | **254** `.tcyr` · **99** `lib/*.cyr` · api-surface **4777** · heap **100** regions / 0 overlaps |
| **Active minor** | **v6.5.x** — generated-code quality (opened at v6.5.0; **v6.4.x closed at v6.4.86**, closeout cut at .85 with .86 the sandhi fold) |
| **Shipped this minor** | **.0** file-scoped `public`/`private` (fns + global vars, hard error, private excluded from `.dynstr`) · **.1** arity-aware overload dispatch + 4 stdlib folds · **.2** the `ir_const_fold` jump-span miscompile (**IR=3 mismatches 35 → 8**), `xrmdir`, yukti 2.3.0's six agnos ABI defects · **.3** diagnostic lines after `include`, `install.sh` ETXTBSY strand, `version-bump.sh` same-version early exit · **.4** `vec_sort_by`/`vec_select_nth` (the agnosai filing; lib/ had NO comparator-driven ordering at all), sigil 3.12.2 / yukti 2.3.2 / sandhi 1.9.8 / mabda 4.0.8 folds, the vacuous sign-efi gate + its stale-binary dispatch, fold-version table rot · **.5** the `CYRIUS_IR=3` switch-dispatch miscompile (filed as LASE, actually **DCE**: an `IR_RAW_EMIT` marker only shields raw bytes until the next RECORDED node, so `ESWITCH_DISPATCH_PRE`'s raw `sub`/`cmp` rcx reads were invisible and DCE killed the `MOV_CA` feeding them) + bayan 1.4.0 |
| **In-flight** | Nothing mid-arc. 6.5.5 is gate-GREEN and complete; the next slot is open. |
| **Next up** | Per [roadmap.md](roadmap.md)'s slot sequence. The IR substrate's *correctness* blocker died at 6.5.2, so the perf/regalloc work is unblocked — what remains there is the **8 residual default-vs-IR=3 exit mismatches** (now bisectable, since 6.5.2 also fixed the `_read_env` aliasing that had made every IR knob silently inert) and the regalloc walls (`ir_lower_all` has zero callers, `IR_SENABLE(S,2)` is never activated, `IR_SWITCH` gets one fall-through edge). |
| **Open queue** | **16** issues · **2** proposals · 279 archived issues. **Three of the 16 are UNVETTED** — filed by subagents during the 6.5.2 triage and never reviewed by a human or by me: `2026-07-29-fmt-int-buf-i64-min`, `2026-07-29-no-portable-xmkdir-in-io-cyr`, `2026-07-29-mutex-unlock-unconditional-futex-wake`. Treat their claims as unverified. Two NEW filings this release: `2026-07-30-net-cyr-x86-only-socket-syscall-numbers` (sandhi/bote; rides with roadmap W1) and `2026-07-30-cx-backend-has-no-indirect-call` (cyrius; cx has no indirect-call op at all, so `alloc_via` already returns 0 there and vec is non-functional on cx). |
| **Owed to the maintainer** | Two answered open questions in [roadmap.md](roadmap.md): the **self_compile budget** and **v6.5.x committed item 5** (growth-tax audit) both now belong to the later performance track and are to be reviewed **together** when it opens. |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
