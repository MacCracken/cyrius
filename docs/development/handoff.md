# Handoff — **v6.5.20 is out.** v6.5.x continues; nothing is mid-arc.

> **Written 2026-08-12.** Read this, then `CLAUDE.md`, then [`state.md`](state.md), then
> [`roadmap.md`](roadmap.md) for the slot sequence. **Refresh or delete this file when the
> next release ships** — a stale handoff is worse than none. (The previous one sat at
> **6.5.10 for ten releases**, which is exactly what this sentence is for. It was found
> during the .20 handoff prep, not by a gate. There is no gate for handoff staleness.)

---

## Where things stand

| | |
|---|---|
| Version | **6.5.20** — release gate GREEN, all 5 steps |
| cycc x86_64 | **1,154,784 B** — seed 29,024 B → cybs → cycc byte-identical |
| Gates | `check.sh` **178 / 0** · **57** shell gate scripts, 0 orphans, 0 dangling |
| Cross-OS | ecb · ach · cass · pi — all `SELFHOST_OK` + `crossos` **46/46** on real hardware |
| Full corpus | ecb **270/0** · ach **270/0** · pi **270/0** · cass **263/7** (one HANG at the 90 s timeout) |
| Corpus | **270** `.tcyr` (46 in `crossos/`) · **100** `lib/*.cyr` |
| Bench | `self_compile` **688 ms** · quiet box, load 0.01 |
| Queue | **10** open issues · **3** proposals · **319** archived issues |
| Mid-arc work | **None.** 6.5.20 is complete; the next slot is open. |

⚠ **Push and tag are the maintainer's.** The tree is uncommitted at handoff time.

## What .19 → .20 shipped

Two releases, both consumer-repair, both dominated by defects found by **attacking a fix
rather than the filing it came from**.

- **.19** — five consumer filings closed (four agnosai, one majra): `doctest` / `publish` /
  `package` / `lsp` joining the `_auto_deps` gate; `duplicate fn` file:line attribution;
  `cyrius lint` blessing a file that does not parse; `fl_alloc`/`fl_free` thread-safety
  (five races, not the one filed); the bench framework measuring its own timer. Plus
  **CVE-39** (cycc SIGSEGV'd or HUNG on 40 of 103 truncated top-level constructs) and
  **CVE-40** (recursive descent had NO depth bound — `fn f() {` × 514 SIGSEGV'd cycc from
  ordinary untrusted stdin; crash depth scales linearly with `RLIMIT_STACK`, ~16 KB/level).
- **.20** — the `switch`/`match` **P1 silent miscompile**; `#derive` line numbering (design
  1); the multi-line-tail blocker; `#derive(Deserialize)` deleting its own struct *and*
  silently accepting malformed fields; the `FM_BUILD` fork gap; the `#`-stop regression;
  patra 1.13.0.

⚠ **The next CVE number is 41.** 39 and 40 are consumed and **neither appears in any
`docs/audit/` file yet** — reconcile the identifier accounting before the closeout security
re-scan.

## ⚠ Read before trusting anything in the tree

These are the specific ways this project has lied to itself recently. All were found the
hard way inside the last two releases.

1. **A gate FILE is not a gate RUN.** Twice in .19 and once at .20 handoff prep, a gate was
   written, committed, and registered **nowhere** — so the `find` count rose (which looks
   like progress) while the gate never executed. Derive the orphan set both ways, every
   release:
   ```sh
   comm -23 <(find tests/gates -name '*.sh' | sort) <(grep -ho 'tests/gates/[a-z-]*/[a-z0-9_]*\.sh' programs/checks/*.cyr scripts/check.sh | sort -u)
   ```
   …and `comm -13` for registered-but-missing.
2. **A test file can be UNTRACKED and still pass on every host.**
   `tests/tcyr/crossos/switch_case_exit_routes.tcyr` — the only cross-host gate for the .20
   switch fix — was untracked. `cross-os-selfhost.sh` builds its payload with `tar` over the
   **working tree**, so it rode to all four hosts and reported 46/46 while a CI checkout
   would have silently dropped it. Check `git status --porcelain | grep '^??'` before a tag.
3. **Assume every gate is vacuous until mutation-proven SEMANTICALLY.** This line has now
   caught **six** vacuous or blind gates, several reported as "mutation-proven" by their own
   authors. Textual mutations (rename a fn, delete a string) prove nothing. The .19
   bench-floor gate passed with `_bench_chunk_for` forced to `return 1` — literally the
   pre-fix defect it existed to catch.
4. **A host result only certifies the binary it ran.** At .19 an earlier four-host green
   covered a compiler that later work superseded; the hosts had to be re-run. Re-run
   cross-OS after the *last* compiler change, not the first.
5. **`check.sh` wraps its verdict in ANSI**, so `grep "FAIL:"` matches nothing and looks
   exactly like success. Strip ANSI first.
6. **Never redirect a compiler with `2>&1`** — stderr merges INTO the binary and you get a
   corrupt file that still "runs" and exits 0.
7. **`cp` onto a running binary** fails "Text file busy" and SILENTLY leaves the old one.
   Use `cp X.tmp && mv -f X.tmp X`.
8. **Reuse of one `/tmp` output path across a corpus loop** produced ~195 "text file busy"
   errors, and a failed redirect re-runs the *previous* binary and scores a false pass. Use
   a unique path per file.
9. **Reap background load.** Leaked spin loops flipped the release gate's `alloc_via` 14 ns
   perf tripwire RED twice, and it was written off as "environmental" both times before
   anyone found the cause (`cyrius test` orphaning children to PID 1 with no timeout — fixed
   at .19). Verify with `ps -eo pid,ppid,args`.
10. **A filing's stated cause is routinely wrong.** At .17 *none* of four filings pointed at
    the right place. At .20 the switch filing named two suspects (`load32(te)==0` sentinel,
    `S64` into a 4-byte table) and **both were innocent** — the real cause was the v5.6.27
    regalloc NOP-harvest compactor, which never knew jump tables existed. It also claimed a
    five-backend blast radius when the table path is x86-family only. **Verify the filing's
    diagnosis before designing against it**; here that check turned a "needs its own release"
    item into a one-file fix.

## Five decisions owed to the maintainer

Surfaced by the 2026-08-11 re-triage, still open. A sixth — **`break` semantics** — was
**SETTLED 2026-08-12** ("break should leave — expected"; C semantics confirmed, recorded in
the guide, vidya and CHANGELOG; do not re-open).

1. **Slot 9 design.** The committed "unbox the scalar case" was implemented at .15 and
   **reverted** — a per-call-site global box made a retaining loop report a failed file open
   as SUCCESS. Both storage relocations are now disproven (frame slot too short, static too
   shared). Survivors are escape analysis or a scope-tied arena. **The slot cannot be scoped
   until this is picked.**
2. **Cross-OS default flip.** Three of four hosts are at **270/0** on the full corpus. Flip
   `CYRIUS_CROSS_OS_FULL=1` to default for ecb/ach/pi and hold the selector for cass, or hold
   all four behind cass's 7? (The cass 7 = a capacity pair — `large_input`, `large_source`,
   the same shape that fails under `CYRIUS_IR=3` — plus a five-test TLS cluster.)
3. **Reactive budget.** 16 of 20 releases this minor were reactive (~80 %) against W3+W4's
   remaining 9 slots.
4. **`.21` packing.** Pull `output_buf` reclaim forward so both queued heap-layout changes
   share **one** two-step bootstrap instead of two?
5. **Per-item `private`.** Still compiles with no diagnostic and privatises the whole file
   including `main`. Nine releases live.

## Where the next slot starts

`roadmap.md` carries the ordered sequence. As re-pinned 2026-08-11, with .20 now done:

| Slot | Band | Item |
|---|---|---|
| 0b | **.21** | Heap layout: `input_buf` raise + `output_buf` reclaim — **one** two-step bootstrap for both |
| 1b | .22 | DX/diagnostics finish-out (Slot 1 b–e) + 4 orphaned fold-ins — oldest homeless commitment, 16 releases past its window, residual is GROWING (7→8 sites) |
| 3 | .23–.24 | IR substrate — perf anchor, unblocks 5/6 |
| 5 / 6 | .25–.28 | Regalloc → SIMD residency |
| 7 | .29–.33 | W3 reactive |
| 8 | .34–.35 | Coroutines (stiva is the acceptance record) |
| 9 | .36–.37 | Sum-type unboxing — ⚖️ **BLOCKED on decision 1** |
| 10/11/12 | .38–.43+ | W4 → macOS concurrency → closeout |

Runway: 21 releases spent, close ≈ **.43–.48** — inside the 45–99 norm for a large minor.

## Loose ends worth knowing about

- **`## [6.5.13]` has an EMPTY CHANGELOG body.** CHANGELOG is the source of truth, and that
  blank entry is the direct cause of two docs carrying a shipped item as open for six
  releases. Backfill it (it shipped the cx indirect-call opcode 105 / `ECALLIND`).
- **`docs/development/issues/archived/README.md` indexes 40 of 319.** Either backfill 6.5.x
  forward or drop the all-files promise.
- **The `vr01_` prefix is dead** but survives as *instructions* in the roadmap ("the `vr01_`
  file is the deliverable"). A test written that way today lands OUTSIDE the gated set. The
  selector is the **directory**: `tests/tcyr/crossos/`.
- **Diagnostics on non-Linux/Windows targets**: `FM_BUILD` now runs in all seven forks (.20).
  Before that, five forks never built the file map and every diagnostic on ecb/ach/pi printed
  the raw expanded-buffer line with no `<source>:` prefix, skewed by **+1 bare / +4 with one
  include / +6 with two**. If a diagnostic looks off on a Mac, check this first.
- **cass has stale artifacts in `C:\cyrius-tests`** from earlier slots. Worth a sweep — an
  orphaned `_lt.exe` holding a file lock has blocked a cross-OS leg's `rmdir` before.

## Process (the parts that get skipped)

- **Release gate** — `sh scripts/release-gate.sh` GREEN before every `.NN`. Five steps:
  fixpoint · **seed-derive** · check.sh · **cross-OS on real hardware** · bench.
- **Seed-derive is mandatory for ANY `src/` change and is NOT covered by the cycc fixpoint.**
  cybs is far more limited than `build/cycc` and fails **silently** on things build/cycc
  compiles fine. `gen1` differing in size from `build/cycc` is NORMAL.
- **Bench every release**, on a quiet box, BEFORE `version-bump.sh`. Record `self_compile` +
  cycc size in the CHANGELOG.
- **Do NOT pre-write `VERSION`** — run `sh scripts/version-bump.sh <new>` and let it write.
  Writing it by hand makes `NEW == OLD` and silently skips the CLAUDE.md / install.sh /
  CHANGELOG / roadmap rewrites.
- **After any `lib/` edit**, run `sh scripts/install.sh --refresh-only` or a later
  `cyrius deps` copies the stale snapshot back OVER the edit.
- **Cross-OS: ONE HOST AT A TIME.** Fixed `/tmp` and remote paths clobber under concurrency —
  two concurrent runs produced a false RED (`rc=255`, `Connection reset by peer`) at .19 that
  looked exactly like a compiler failure.
- **An audit's output is FIXES, not a backlog.** File only when the fix genuinely cannot pack
  — heap/brk layout change, a maintainer design call, cross-repo coordination, or a full gate
  cycle the release cannot absorb — and NAME the reason. **A filed repro is the spec.**
