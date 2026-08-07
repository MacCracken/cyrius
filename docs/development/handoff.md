# Handoff — **v6.5.10 is out.** v6.5.x continues; nothing is mid-arc.

> **Written 2026-08-07.** Read this, then `CLAUDE.md`, then [`state.md`](state.md), then
> [`roadmap.md`](roadmap.md) for the slot sequence. **Refresh or delete this file when the
> next release ships** — a stale handoff is worse than none. (This one was found four
> releases behind at the .10 sweep, which is exactly what that sentence is for.)

---

## Where things stand

| | |
|---|---|
| Version | **6.5.10** — release gate GREEN, all 5 steps |
| cycc x86_64 | **1,141,792 B** — seed 29,024 B → cybs → cycc byte-identical |
| Gates | `check.sh` **162 / 0** + **41** shell gate scripts in `tests/` · bench 648/652 ms |
| Cross-OS | ecb · ach · cass · pi — all `SELFHOST_OK` + VR-01 `LIBTEST_OK` on real hardware |
| Corpus | **260** `.tcyr` · 99 `lib/*.cyr` · api-surface **4817** · heap 100 regions / 0 overlaps |
| Queue | **12** open issues · 2 proposals · 299 archived |
| Mid-arc work | **None.** 6.5.10 is complete; the next slot is open. |

## What .7 → .10 shipped

Five releases ran back-to-back as the repair side of W1, all consumer-driven.

- **.7** — the **syscall-wrapper pass** (W1 item 1, complete end-to-end): `sys_chdir`
  (called at `lib/regression.cyr:658`, defined nowhere), `signal_default`, the `x*` io
  family, and `sys_fchownat` via a **new ≥1000 private-alias band** on aarch64. Plus
  `#@incdir` file-relative includes, the `alloc_reset` allocator-invalidation (hisab), and
  the subfolder callout for test/bench/fuzz.
- **.8** — `thread_join`'s **lost-wakeup deadlock** (szal, P1); `thread_create_detached` +
  `thread_is_done` (210 MB VA leak → 0); the **`i64::MIN` formatter class across 12 sites**,
  not the 7 the roadmap named, two of them inside the compiler; `coverage`'s four defects;
  the `doc`/`vet`/`deny`/`audit` fail-open family; `distlib --all`/`--check`; the cross-OS
  gate batched and made self-reporting.
- **.9** — agnos `CH_ENDOW` + `sys_spawn_path_env`; the **three-state futex mutex**
  (392 → 48 ns); the **growable arena + exhaustion policy**.
- **.10** — `distlib`'s `.deps` sidecar under-reporting; `alloc_via`'s call plumbing
  (15.1 → 11 ns).

## ⚠ Read before trusting anything in the tree

**The UNVETTED backlog is now empty.** All three subagent-filed issues from the 6.5.2 triage
have been vetted: `fmt-int-buf-i64-min` and `no-portable-xmkdir-in-io-cyr` **shipped**, and
`mutex-unlock-unconditional-futex-wake` was vetted, found to be a *perf* gap rather than a
correctness bug, and shipped in .9. Nothing in the open queue is now unreviewed.

**⭐ A roadmap prerequisite can be wrong, and this one cost an item a pin.** W1 item 3 (the
mutex) was recorded as blocked on `atomic_swap` plus a value-returning CAS — "single
instructions on both arches", with real-pi asm-review risk. Neither was needed: a
**successful boolean `atomic_cas(m, 1, 0)` already proves the pre-value was exactly 1**,
which is the information `atomic_swap` would have returned. The item was *cheaper* than
pinned. **Premise-check the stated blocker, not just the pin.**

**Mutation testing changed the CODE, not just the gates, twice in .9–.10.** The arena
mutation "grow ignores an oversize request" passed — because `arena_alloc` returned the
post-grow pointer *without re-checking the bound*, so a too-small chunk would hand back a
pointer with less memory behind it than requested. A silent heap overflow, and the test
could not see it either (it asserted only `!= 0`). If a mutation passes, suspect the code
before you excuse the gate.

**A gate fixture in the wrong ORDER is silently vacuous, and it has now happened three
times.** `dir_walk` gives no ordering guarantee, so a coverage axis with one symbol in one
"last" file passed against the truncating build; and a decoy `stdlib` mention appended
*after* the real key was never reached, because the scan stops at its first match. Both
passed against deliberately broken builds. When a fixture depends on position, say so and
prove it.

**CI runs neither `check.sh` nor `build/cyrius_check`** — only `tests/heapmap.sh` and
`tests/io_rdwr_agnos.sh`. Everything else is local / release-gate only.

## Two things owed to the maintainer

Both recorded as answered open questions in [`roadmap.md`](roadmap.md); both belong to the
**later performance track** and are to be reviewed **together** when it opens.

1. **The self_compile budget.** roadmap_6's acceptance anchor has two clauses; the svara
   figure is carried, the budget clause was never stated. Baseline: **654 ms · 1,129,288 B**.
2. **v6.5.x committed item 5 — the self-compile growth-tax audit.**

⚠ **Do not size either from this box's bench numbers.** self_compile has read 648–701 ms
across a single release with no code change between runs — the run-to-run spread here is
**wider than the release-over-release delta**, so a single figure carries no signal. Any
budget needs a quieter machine or a many-run median first.

## Where the next slot is likely to start

**W1 is 7 of 13 spent** (`.4` `.5` `.6` `.7` `.8` `.9` `.10` — items 1, 2, 3, 4 and 6 are
done). Remaining W1 items: **5** (`dir_list`, both halves — taking only the cheap half is the
sliced-fix antipattern), **7**, **8**, **9**, across the remaining **6** patches `.11`–`.16`.

Then the IR substrate (Slot 3): **10 residual default-vs-IR=3 divergences** (measured 2026-08-07 over all 260 tcyr with unique output paths: **3 fail to COMPILE** under IR=3 — `large_input`, `large_source`, `preprocessor_past_cap` — and **7 differ at RUNTIME** — `const_chained_multiply_fold`, `field_name_shadows_global`, `float`, `math_inverse_trig`, `math_pack_integration`, `subword_signed_load`, `types`) and the
regalloc walls (`ir_lower_all` has zero callers; `IR_SENABLE(S,2)` never activated;
`ir_build_edges` gives `IR_SWITCH` a single fall-through edge).

**One filed item is deliberately parked and should not be re-litigated casually:**
`2026-08-05-cross-os-full-corpus-23-failures-on-ecb`. The cross-OS gate can now run the
**whole** 260-file corpus (`CYRIUS_CROSS_OS_FULL=1`, 75 s on ecb, affordable only because
the SSH loop is batched), and the first measurement found **235 pass / 23 fail**. Those 23
are pre-existing platform gaps, most downstream of the open macOS-threading issue — so full
corpus is **opt-in** rather than default, because defaulting it would wedge every release
behind a separate arc. Flip the default when that count reaches zero.

## Standing traps (the expensive ones)

- **cybs cannot lex `>>>`**, and mis-compiles fns with too many global/call references. The
  cleanest proof the cycc fixpoint does NOT cover the seed chain.
- **"0 of 260 changed" means the corpus has no coverage of the shape**, not that the change
  is safe.
- **A byte-identical rebuild after a real behaviour change is a TELL** — and an identical
  byte SIZE is not identical bytes (a one-line change once moved 872,790 bytes at a constant
  1,133,440 B). `cmp`, never `ls -l`.
- **`lib/` is NOT free of cycc byte-identity risk.** The real closure is **four** files —
  `alloc.cyr` + `vec.cyr` + `atomic.cyr` + `fnptr.cyr`. `lib/alloc.cyr` is also on the SEED
  path, so an arena or allocator edit carries the full fixpoint + seed-derive gate.
- **⭐ qemu-user reports a FALSE thread-VA leak.** `vr01_thread_detach.tcyr` fails there with
  ~1,665 residual pages per detached thread — not even the 513-page stack — because qemu maps
  its own per-thread state into the same address space and `/proc/self/statm` measures the
  HOST. Real pi reports exactly 0. Run it on pi before believing it.
- **⭐ Darwin diverges from Linux in more places than the dirfd.** `AT_SYMLINK_NOFOLLOW`
  is 0x20 (not 0x100), `AT_SYMLINK_FOLLOW` 0x40, `AT_REMOVEDIR` 0x80; and the macOS-x86
  `Stat` enum was a MIX of two structs for years because only `st_size` had ever been
  corrected. These reach Darwin untranslated, so a Linux value is simply an invalid flag —
  EINVAL, silently, forever.
- **⭐ An aarch64 private-alias arm must sit LAST in its ESYSXLAT chain.** `1054 → 54` emits
  `x8=54`, and the setsockopt entry compares against 54 — placed earlier, every `fchownat`
  is silently reissued as `setsockopt` (mutation-verified: returns `ENOPROTOOPT`).
- **A `.tcyr` can pass against the broken code.** `thread_join_single_load.tcyr` scores
  131/0 against the defect it guards, because it drives the raw futex ABI. The STRUCTURAL
  axis is what catches it. Check which axis actually discriminates.
- **The api-surface gate does NOT skip folded distlib bundles.** Verify **zero removals by
  set difference**, not by the summary line.
- **A per-file `.tcyr` loop that reuses one output path silently runs STALE binaries.**
- **The heap map is machine-read.** Prose on a map line is parsed as the size.
- **`var x[N]` local = N BYTES; a bare top-level `var x[N]` = N×8.**
- **Cyrius precedence is NOT C's** — `&`/`|`/`^` share the `+`/`-` tier. `>>` is LOGICAL,
  `>>>` is ARITHMETIC. **`#` starts a comment** — which is what lets `#@incdir` be inert on
  every compiler that does not look for it.
- **A raw agnos syscall number off-agnos is the whole hazard.** The FILE-level
  `#ifdef CYRIUS_TARGET_AGNOS` gate is the barrier. And **do not mint an agnos number before
  its kernel arm exists** — an unknown `num` falls through the dispatch chain and the caller
  reads the fall-through value as data, so a minted-but-unimplemented constant is strictly
  worse than an absent one. `#96 fork` is reserved and deliberately NOT minted.
- **`cyrius distlib` regenerates only the main bundle** — but `--all` now does every declared
  `[lib.X]` profile, and `--check` verifies them by BYTES without writing. Use it.
- **⚠ The CLI re-execs the manifest-pinned cyrius.** A repo pinning `cyrius = "6.4.69"` runs
  6.4.69, so testing a new CLI feature there exercises the pinned binary. `CYRIUS_RESOLVED=1`
  bypasses it. "I confirmed it on sigil" is a false claim without that.
- **`grep -c` prints `0` AND exits 1** on no-match, so `$(grep -c … || echo 0)` yields the
  two-line string `"0\n0"` and every comparison against it fails.

## Process

- The user handles **all** git. Never commit, push, or tag. Never use `gh` — `curl` the API.
- `release-gate.sh` GREEN before every `.NN`. `--quick` is steps 1–3, explicitly not
  release-ready.
- Run `cross-os-selfhost.sh` **one host at a time** (fixed /tmp paths clobber).
- **An audit's output is FIXES, not a backlog.** File only when the fix genuinely cannot pack
  into the patch — and NAME the reason.
- **Mutation-prove every gate**, and prove it against the RELEASE gate, not just its own exit.
- **Fix the SOURCE repo, not the fold.**
- **Premise-check at slot entry.** Three consecutive slots once turned out to be
  already-shipped work; in the .8 triage, 4 of 12 filings closed without any code change.
