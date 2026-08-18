# Cyrius Development Roadmap — v6.5.x (active minor)

**Scope** — the **current active minor only** (v6.5.x). This is the slot-pinning working
artifact: the committed slot sequence, the reactive windows, and a code-grounded size for
each arc. The whole-cycle framing plus v6.6.x/v6.7.x/v6.8.x live in
[roadmap_6.md](roadmap_6.md); the unpinned watching list is
[roadmap-future.md](roadmap-future.md); per-release history is
[CHANGELOG.md](../../CHANGELOG.md) and [completed-phases.md](completed-phases.md).

> **Reading order**: this file (active-minor slot sequence) → [roadmap_6.md](roadmap_6.md)
> (v6.6.x+ and cycle framing) → [roadmap-future.md](roadmap-future.md) (unpinned / speculative).

## See also

- [roadmap_6.md](roadmap_6.md) — the **v6.x cycle** beyond this minor: v6.6.x
  language-ergonomics (const-eval, the bounds-check mode, trait-bounded generics),
  v6.7.x/v6.8.x RISC-V rv64, and the cycle-level budgeting reference points.
- [roadmap-future.md](roadmap-future.md) — unpinned / speculative watching list with explicit
  unpin conditions (128-bit div-mod, Phase 3-full varargs, effect tracking, HKTs/GATs).
- [cycle-discipline.md](cycle-discipline.md) — durable operating principles **and the runnable
  closeout checklist + per-closeout ledger** (the doc you open, run, and log against).
- [state.md](state.md) — volatile current state (version, cycc size, in-flight slot). Refreshed
  every release by `version-bump.sh`.
- [completed-phases.md](completed-phases.md) — historical per-release / per-minor narrative.
  **Closed-minor narrative belongs there, not here.**
- [`CHANGELOG.md`](../../CHANGELOG.md) — per-patch source of truth. When this file and the
  CHANGELOG disagree, the CHANGELOG wins and this file is the bug.

---

## Where we are

**Current head: v6.5.27** (2026-08-17) — cycc **1,154,816 B** · check.sh **178 passed / 0
failed** · self_compile **685 ms** · **270** `.tcyr` (**46** in `crossos/`) · **100**
`lib/*.cyr` · **97** `programs/**/*.cyr` · **57** shell gate scripts under
`tests/gates/<bucket>/` (48 registered by exact path in `programs/checks/*.cyr`, 10 driven
from `scripts/check.sh`, `heapmap.sh` in both — **all 57 live, 0 orphans**) · heap map
**100 regions / 0 overlaps** · **12 open issues + 3 open proposals** (316 archived issues /
27 archived proposals).

> ⚠ **Every number in the paragraph above was re-derived 2026-08-11, not incremented.**
> Commands: `stat -c%s build/cycc` · `find tests/gates -name '*.sh' | wc -l` ·
> `find tests/tcyr -name '*.tcyr' | wc -l` · `ls lib/*.cyr | wc -l` ·
> `ls docs/development/issues/*.md | grep -vc README` ·
> `find docs/development/issues/archived -name '*.md' ! -name README.md | wc -l`.
> Gate figures are quoted from the v6.5.19 CHANGELOG entry that recorded the run.
>
> ⛔ **This block had rotted nine releases while looking fresh, and the mechanism is worth
> keeping.** `version-bump.sh` rewrites the `Current head: vX.Y.Z` string — which is exactly
> what `_doc_stamp_currency_gate` keys on — and touches **nothing else in the paragraph**. So
> at 6.5.19 the version stamp was correct and all eight metrics beside it were still at their
> **6.5.10** values (cycc 1,141,792 · check.sh 162 · 260 `.tcyr` · 41 gates in `tests/*.sh` ·
> 99 `lib` · 12 issues + 2 proposals / 299 archived). **The gate that exists to prevent doc rot
> passes on the one line that is fresh.** Treat the stamp as evidence about the stamp only.
>
> *(The prior ⚠ block here flagged four issues as SHIPPED-but-unarchived and set a "16 open"
> ceiling. That sweep has since run — all four are in `archived/` — so the block and its
> denominator are deleted rather than carried. Any claim elsewhere in this file resting on
> "16 open" needs re-deriving against the live 12.)*

`scripts/release-gate.sh` **GREEN on all four hosts** at 6.5.19 — **ecb** (macOS-arm64),
**ach** (Intel-Mac x86-Mach-O), **cass** (Windows/PE), **pi** (aarch64), real hardware,
sequential, each `SELFHOST_OK` + `crossos` 45/45.

> ⭐ **Full-corpus cross-OS, re-measured on real hardware 2026-08-11 (one host at a time):**
> **ecb 269/0 · ach 269/0 · pi 269/0 · cass 262/7** (one HANG at the 90 s timeout). Three of
> four gated hosts are at **ZERO full-corpus residuals**; the cass 7 are a capacity pair
> (`large_input`, `large_source` — the same shape that fails under `CYRIUS_IR=3`) plus a
> five-test TLS cluster. This retires the "portable core of 4 failing on every non-x86-Linux
> host" framing entirely and makes the `CYRIUS_CROSS_OS_FULL=1` **default-flip a live
> maintainer decision** — see `issues/2026-08-05-cross-os-full-corpus-23-failures-on-ecb.md`,
> retitled and rescoped to match the measurement.

> `_doc_stamp_currency_gate` (check.sh, since v6.4.81) keys on the `Current head:` anchor that
> opens this paragraph and checks that `VERSION` appears within 240 bytes of it. It **fails
> loudly if the anchor disappears** rather than passing on a missing one — keep the string,
> keep it unique, and keep the version next to it.

**v6.4.x CLOSED at v6.4.86.** The closeout band ran **.80 → .85**; `.85` is the
closeout-complete cut (the entry that states "v6.4.x is CLOSED"); `.86` is the post-closeout
sandhi 1.9.3 → 1.9.5 fold. Anything that says the minor closed at `.82` is wrong — `.82` was
the closeout *proper*, and `.83`/`.84` were both displaced by live bugs the closeout itself
found (an intrinsic could not flank a TERM-tier operator; `chan_try_send` plus a pre-existing
macOS channel `SIGSYS`). That displacement pattern is the reason Slot 12 below is a band and
not a single release.

### Shipped in v6.5.x — one line per release

- **v6.5.0** — **file-scoped `public`/`private` visibility**, the minor's opener: the per-fn
  origin-file-id substrate + the `#@file` preprocessor RESUME-marker repair (the map was
  silently wrong — `alloc.cyr`/`atomic.cyr` shared an id, `lex.cyr` split across two),
  `private`/`public` for **fns AND global vars**, hard-error enforcement through 13 resolution
  paths via one `_vis_check` (+ `_vis_check_var` inside `FINDVAR`), `private` excluded from
  `.dynstr` (STRSZ 24 → 14) with all three export walks unified on `_fn_exported`, api-surface
  made visibility-derived, `lib/regex.cyr` adopted (41 private / 11 public), and
  release-gate step 3 fixed to grade check.sh by `$?` rather than stdout. cycc 1,112,464 →
  1,124,968 B (+12,504, triaged growth tax).
- **v6.5.1** — **arity-aware overload-suffix dispatch, fixed compiler-side**: `_OV_ARITY_OK` +
  `_CALL_ARGC_PEEK`, the `PARSE_RETURN` tail-path divert (so `var r = f(s)` and `return f(s)`
  stop running *different functions*), wrong-arity warning → hard error; the
  `io_rdwr_agnos` gate moved CI-only → check.sh; folds bayan 1.3.0 / sakshi 2.4.7 /
  yantra 1.0.2 / sandhi 1.9.7 with 63 in-repo call-site migrations. Two stdlibs had renamed
  their own functions to escape the defect — one of those renames was a breaking public API
  change. cycc flat at 1,124,968 B.
- **v6.5.2** — **the `CYRIUS_IR=3` substrate, unblocked**: `ir_const_fold` erased the jump
  that followed a folded constant (`EJCC`/`EJMP0` were the only two x86 emitters recording
  their IR node *after* emitting bytes, so the NOP-fill span ran 5–6 bytes long and deleted
  the jump); `_read_env`'s single shared 256 B buffer made **every** IR diagnostic knob
  silently inert, which is why the filed bisection table showed five pass combinations sharing
  one hash — all five were the same no-op run. Plus the `_int` overload route gated on an
  explicit `: cstring` param, integer-literal-to-cstring now a hard error (`println(42)`
  previously compiled with no diagnostic and SIGSEGV'd), the `PARSE_RETURN` tail path **again**,
  `xrmdir` in `lib/io.cyr`, new gates `tests/gates/ir-opt/ir3_fold_jump_span.sh` +
  `tests/gates/platform/folds_agnos_parity.sh`, and yukti 2.2.10 → 2.3.0 (six agnos ABI defects, including
  `sys_mount` fabricating `Ok()` for a filesystem that was never mounted). Corpus
  default-vs-IR=3 exit mismatches **35 → 8**. Bench 638 ms, retiring the 6.5.1 perf flag.
  cycc **1,129,288 B**.
- **v6.5.3** — **diagnostics report the SOURCE line again**: an error in the main source used
  to report `actual_line - (includes before it)`. The marker now carries a base
  (`#@file "NAME" BASE`, packed into the high 32 bits of the map entry's line-count word) and
  the `source_marked` one-shot — a second, hand-rolled emitter that had been silently
  overwriting the correct marker, which is why an earlier correct attempt at this fix was
  reverted as "disproved" — is deleted. Also: include-once skips no longer leave the base
  stale, nested includes stop reporting expanded lines, and `FM_FILEID` masks the packed word
  (unmasked it collapses every line to one file id — silent `private` mis-scoping that
  *allows* access). Toolchain: `install.sh` aborted its install loop on the first ETXTBSY
  `cp` and `cycc` is first in `bins`, so **all 17 later binaries were left stale** (the
  `cyrius --version` drift a consumer reported); `version-bump.sh`'s same-version path exited
  before its own force-rebuild. cycc 1,129,272 → 1,129,288 B.
- **v6.5.4** — **`vec_sort_by` / `vec_select_nth`**, the stdlib's first ordering primitive
  (the agnosai filing; **no fn in any of the 99 `lib/` modules took a comparator**). Named
  `vec_sort_by` rather than bare `vec_sort` because `itihas/src/util.cyr:57` already defines
  the latter and last-definition-wins would break it. Folded sigil 3.12.2 / yukti 2.3.2 /
  sandhi 1.9.8 / mabda 4.0.8. Fixed the sign-efi gate, which was **vacuous** against the
  exact defect sigil 3.12.2 fixes *and* was grading the installed helper instead of the repo
  build. Re-derived every folded-dep version table from live `lib/` headers — 3 of 4 had
  rotted again, and `yantra` was missing from both.
- **v6.5.5** — **the `CYRIUS_IR=3` switch-dispatch miscompile** filed by cyrius-doom. Filed
  as LASE; it is **DCE**. `CYRIUS_LASE_OFF=1` is not LASE-specific — `ir_apply_lase` is the
  only NOP-filler and applies marks from three passes. Root cause: an `IR_RAW_EMIT` marker
  only shields raw bytes until the **next recorded node**, and `ESWITCH_DISPATCH_PRE`
  recorded four nodes between its marker and its raw `sub`/`cmp`, hiding their rcx reads from
  DCE. Closes `switch_dispatch` (18 → 0); **7 of the 8 residual IR=3 mismatches remain**.
  Also folded bayan 1.4.0. cycc flat at 1,133,440 B.
- **v6.5.6** — **the agnosai/sandhi pair, both filed and fixed the same day** (W1 reserve).
  `sys_exit_group` on **all three** syscall peer families — `sys_exit` is exit(2) and ends
  only the calling thread, so every threaded program's idiomatic epilogue hung, and `cyrius
  init` shipped that epilogue in **seven** templates. `async_await_readable_ms` — the old
  helper parked on a hardcoded `-1` and returned a constant `0`, so a cooperative server
  could neither be woken nor told which way its wait ended. Three defects found while fixing
  those and shipped with them rather than filed: macOS-x86's **untranslated 231 → silent
  SIGSYS** (the unrouted-syscall warning is arm64-only), `proj-tcyr`'s 8-bit exit truncation
  (exactly 256 / 512 / 768 failing assertions scored **PASS**), and `cyrius fuzz` being blind
  to the harness `cyrius init` had just written — the third member of a family whose first
  two fixes (v6.4.72 test, v6.4.78 bench) had both shipped **ungated**. Folded sandhi 1.9.9
  (the stop facility — the other half of the same filing) + vani 1.1.3. Three new gates, all
  mutation-proven. cycc flat at 1,133,440 B.
- **v6.5.7** — **the syscall-wrapper pass (W1 item 1), complete end-to-end**, plus the
  `include`-resolution limit and the tool defects found alongside. `sys_chdir` (called at
  `lib/regression.cyr:658`, defined nowhere), `signal_default`, and the `x*` family
  (`xmkdir`, `xmkdir_p`, `_xdir_exists`, `xsymlink`, `xreadlink`, `xlink`). ⭐ **The
  ≥1000 private-alias band**: both candidate numbers for aarch64 `fchownat` are owned (native
  54 by the x86-compat setsockopt shim, x86 260 by the aarch64 peer's own `SYS_WAIT4`), so
  source numbers ≥1000 are now cyrius-private aliases ESYSXLAT renumbers — `SYS_FCHOWNAT =
  1054`, `SYS_CHDIR = 1049`. `#@incdir` gives file-relative `include` resolution, in-band on
  line 1 (a `#` comment, so older cycc / cybs / the cx+JS forks skip it untaught), **CWD-first
  and hardened** — relative and `..`-free, read only at byte 0, both mutation-proven, because
  honouring an absolute directory would have rebuilt the primitive CVE-16 removed. Also
  `alloc_reset()` leaving the memoized default allocator pointing into the arena it resets,
  and `cyrius test`/`bench`/`fuzz` ignoring a subfolder callout.
  ⭐ **`tests/tcyr/vr01_syscall_wrappers.tcyr` — ONE new test actually RUNNING on hardware —
  turned the gate RED on ecb and again on ach and found SEVEN defects**, two of them
  pre-existing rot unrelated to this item (`xrmdir` never worked on macOS-arm64 since the day
  it shipped at 6.5.2; the macOS-x86 `Stat` enum mixed two different structs). Five of the
  seven were **half-fixes that stopped at the first symptom** — `AT_FDCWD` without its flags,
  `STAT_SIZE` without its siblings, `unlink` without `rmdir`, three of four link syscalls
  mapped. cycc 1,133,440 → **1,141,696 B** (+8,208, six independent additions, no bisect).
- **v6.5.8** — **the repair release**: twelve triaged filings, four of which premise-checked
  as already-fixed or not-ours and were **closed rather than worked**. `thread_join`
  lost-wakeup deadlock (it read the tid word twice per iteration under a comment asserting the
  two were "in lockstep"; ~1 join in 150k, permanent and silent, SIGKILL the only recovery) ·
  `thread_create_detached` + `thread_is_done` (100 unjoined threads leaked 210,124,800 B of
  VA → 0) · **the `i64::MIN` formatter class — 12 sites, not the 7 this roadmap named**,
  including **two inside the compiler itself** (`PRNUM`, `_emit_decimal`) that were never
  listed · agnos `#97 chan_op` minted (`#96 fork` deliberately NOT — an unknown `num` falls
  through agnos's dispatch and the caller reads the fall-through value as data). Tools:
  `cyrius coverage`'s four defects (a fixed 1 MiB corpus whose failure is **anti-correlated
  with the signal**, so it punished the projects testing most) · the `doc`/`vet`/`deny`/
  `audit`/`coverage` **fail-open family** · `distlib --all`/`--check` (W1 item 6) · the
  cross-OS gate batched to one SSH connection per POSIX host and made to **print its own
  coverage**. Folded sakshi 2.4.8 + bayan 1.4.1. check.sh 156 → **159 / 0**; cycc flat at
  1,141,696 B.
- **v6.5.9** — **agnos `CH_ENDOW` + `sys_spawn_path_env`, the three-state mutex, and the
  growable arena.** `CH_ENDOW = 0x05` landed in agnos 1.56.40 *after* 6.5.8 minted the band,
  so the caps mask already advertised it while the peer had no name for it; it returns an
  **fd, not 0** — the one op in the band that does. `sys_spawn_path_env` finally reaches all
  four arguments of `#43`, which has accepted an env blob in `a3`/`a4` since agnos 1.44.19.
  **The three-state mutex (W1 item 3): 392 → 48 ns** uncontended — and ⭐ **it needed no new
  primitive, contradicting this roadmap's own pin**, because a *successful* boolean
  `atomic_cas(m, 1, 0)` already proves the pre-value was exactly 1. The **growable arena +
  exhaustion policy** (`ARENA_FULL_NULL`/`GROW`/`SPILL`/`ABORT`, NULL still the default so no
  existing arena moves): a `Str` of 0 is indistinguishable from a valid `Str`, so arena
  exhaustion surfaced as a SIGSEGV several layers away — and ⭐ the *regression direction* is
  what made it serious, since threading a route onto an arena to stop a leak turned that leak
  into a crash. `lib/alloc.cyr` is inside cycc's include closure, so it carried the full
  fixpoint + seed-derive. check.sh **160 / 0**; cycc **1,141,784 B**.
- **v6.5.10** — **two filings, both measured before they were filed.** `distlib`'s `.deps`
  sidecar under-reported because it was built ONLY by scanning bundled sources for literal
  `include "lib/X.cyr"` lines — it captured what a module *includes*, never what it
  *references*; setu emitted 8 leaves against a declared 12. ⭐ **A wrong sidecar switches OFF
  cyrius's own consumer check**: `cyrius deps` validates a consumer's `[deps] stdlib` against
  it, so an under-declaring consumer built `OK` silently. Now the declaration **unioned** with
  the scan — base bundle only, because unioning the whole declaration into a narrow profile
  would over-report. And `alloc_via` was two-thirds call plumbing: **15.1 → 11 ns** by reading
  the vtable inline and deleting the `_arena_alloc` trampoline (`_bump_alloc`/`_bump_reset`
  stay — they adapt arity, so removing them would corrupt the call). check.sh **162 / 0**;
  cycc **1,141,792 B** (+8 = the longer version string).

> ### ⛔ `.11`–`.19` were missing from this list entirely until 2026-08-11
>
> This section ran `.0` → `.10` and stopped, while **nine further releases shipped** — nearly
> half the minor, including a **P0 codegen miscompile**, two **security folds**, and the whole
> macOS/Intel-Mac corpus closure. A reader of the active-minor roadmap could not see that any
> of it happened, and `state.md`'s "Shipped this minor" row *did* carry them, so the two docs
> disagreed and this file was the wrong one. Backfilled below, one line each, from the
> CHANGELOG headings (`grep -n '^## \[6\.5\.' CHANGELOG.md` → 20 entries, `.0`–`.19`, no gaps).

- **v6.5.11** — **the test suite moved into subfolders and `vr01_` became the `crossos/`
  DIRECTORY**, with three silent-green readers closed first (CI had been scoring a fake PASS
  because cycc on **empty stdin** exits 0 and emits a runnable binary, so an unmatched glob
  passed). `MAP_ANONYMOUS` was Linux's 32 on Darwin, so `mmap_anon()` returned 0 for every
  caller. **macOS threading now RUNS the worker** via a serial fallback — the wrong constant
  had been the accidental safety net for the missing backend, and fixing it turned the no-op
  into SIGSYS. `dir_list`/`is_dir` per-call 4 KB → stack (**W1 item 5**, and it went wider than
  filed: `is_dir` was the dominant cost and the filing never named it).
- **v6.5.12** — **sigil 3.12.4: an RSA verify BYPASS** (888 of 400,000 forged signatures
  accepted upstream), written this release because the banking existed for a cyrius quirk *we*
  fixed at 6.3.15 and never propagated. `CYRIUS_STACK_ARRAYS=0` silently re-opened it — our own
  flag revoking their fix — and now warns. `lib sync` dropped package **directories** at exit 0;
  cx emitted a **self-restarting** `.cyx` at exit 0 for an undefined call; tree walks followed
  symlinks (**41 passed for a corpus of ONE**); `bench_string` had been SIGSEGVing since 6.3.15
  behind the non-blocking bench step.
- **v6.5.13** — **cx indirect call: `.cyx` opcode 105 (`callind`), PERMANENT** — three defects
  that had to land together (`ELOAD_FN_ADDR` a return-0 stub, `main_cx.cyr` never setting
  `_fixup_base`, `ECALLIND` a hard error) — plus agnos `#98 ptrscan`. ⚠ **This release's
  CHANGELOG entry has an EMPTY BODY** (heading at `CHANGELOG.md:960`, next heading two lines
  later). The work is real and verifiable in live code (`src/backend/cx/emit.cyr:424`, `:488`;
  `lib/syscalls_x86_64_agnos.cyr:148`), but the canonical history for it is blank — which is
  precisely why two roadmap documents went on carrying the cx gap as *open* for six releases:
  there was no CHANGELOG line to reconcile against. **CHANGELOG is the source of truth; a
  release with no body is a recording failure, and should be backfilled.**
- **v6.5.14** — **the tail-call frame-escape P0**: `return f(p)` freed the frame that `p`
  pointed into, and the v5.8.16 guard was **syntactic** so it missed every aliased form. Plus
  sigil **3.12.6** (the whole PSS workspace localised — PSS verify carried the same
  authentication bypass 3.12.3 fixed for v1.5, and this compiler defect is why three releases
  could not close it) and `distlib`'s bundle self-check, which compiled to `/dev/null` and had
  therefore **never run**.
- **v6.5.15** — **the macOS-arm64 constant + syscall gap closure (ecb full corpus 11 → 6)**:
  ten constant **VALUES** the aarch64-Linux peer leaked onto Darwin — `ESYSXLAT` renumbers
  NUMBERS, never VALUES, and Linux `SIGCHLD` 17 **is** Darwin's `SIGSTOP`. Plus the macho
  ESYSXLAT gap set, where Darwin's `pipe` returns both fds **in registers** so a renumber alone
  was insufficient. ⛔ **`Result` unboxing (Slot 9) was implemented and REVERTED here** — see
  Slot 9 below; it passed every gate and still reported a failed file open as success.
- **v6.5.16** — macOS `uname`/`sysinfo` per-arch routes; sakshi 2.4.10; two issues filed from
  measurement (macho route-table drift; `getuid`/`geteuid` broken on both Mach-O targets,
  invisible because `is_root()` hardcoded 0 on macOS).
- **v6.5.17** — hisab's capturing-closure SIGSEGV; a syntax error in an **uncalled** fn;
  `distlib` rejecting correct bundles; sankoch 2.7.7.
- **v6.5.18** — **`platform/fdlopen` closed: the last full-corpus failure on both Macs** (full
  corpus **267/0** on Linux, ecb AND ach). `#naked` had been consumed-and-IGNORED by
  `main_aarch64_macho.cyr` and `main_win.cyr` since v6.2.27. Plus `cyrius fmt` **corrupting
  string literals** — it was rewriting 1,239 lines of this repo's own `src/main.cyr` — and the
  sigil 3.12.7 fold. ⭐ Both new gates were vacuous on arrival and both were caught.
- **v6.5.19** — **five consumer filings closed** (four agnosai, one majra), four of them
  diagnostics/tooling telling the user something untrue, the fifth silent heap corruption under
  threads. Plus **CVE-39** (cycc SIGSEGV'd or HUNG on 40 of 103 truncated top-level constructs)
  and **CVE-40** (recursive descent had NO depth bound — `fn f() {` × 514 SIGSEGV'd cycc from
  ordinary untrusted stdin; PROVEN stack exhaustion, ~16 KB per nesting level). Two issues
  filed, both pinned to `.20`. cycc **+12,800 B**, self_compile **685 ms** (+6 %), triaged as
  **growth tax, not bisected**.

### What "IR=3 self-hosts" actually means — state it precisely

**Re-measured at 6.5.10** (2026-08-07), not quoted: `cat src/main.cyr | CYRIUS_IR=3
build/cycc` produces a **1,199,136 B** compiler — **+57,344 B / +5.02 %** over the default
build (1,141,792 B, which is itself byte-identical to `build/cycc`), differing from byte 42.
Pipe `src/main.cyr` through *that* IR=3-built compiler and its output is **1,141,792 B,
byte-identical to `build/cycc`**. (At 6.5.2 the same measurement read 1,182,520 B / +53,248 B
/ +4.7 % against a 1,129,288 B default — so the overhead has grown slightly in both absolute
and relative terms across eight releases; re-measure it, don't quote this paragraph.)

So the true and load-bearing claim is: **CYRIUS_IR=3 builds a compiler that reproduces
`build/cycc` byte-identically** — a semantics-preserving statement about the IR=3-built
compiler's *output*, not about its own bytes. That is what `tests/gates/ir-opt/ir3_fold_jump_span.sh`
asserts and what it passes. Read it the loose way and you conclude IR=3 is byte-neutral, when
it currently makes the compiler **5 % larger** — which is a live data point for a minor whose
whole theme is generated-code quality, and one of the things Slot 3 has to explain.

---

> **PLACEMENT RULE (hard):** every technical / codegen / runtime / platform item lives in the
> **6.x line** or the **potential backlog** below — **NOTHING codegen-related is EVER pushed to
> 7.x**. 7.x is **language book + legal-for-public-release ONLY**. An item without a committed
> slot goes in the potential backlog (still 6.x-cycle work), never a far-future version. The
> far-future label is how real work stops being scheduled: DWARF and incremental compilation
> were both mis-parked there and corrected at the v6.4.82 closeout, and roadmap_6.md's closing
> paragraph parked LSP/formatter/linter evolution + agnos-v2.0 alignment at 7.x — **both
> corrected in roadmap_6.md on 2026-08-07 and re-homed to the 6.x line** (linter → this file's
> W2 fold-in; agnos alignment → the reactive windows). Four violations, all in that one file,
> all found by a sweep rather than by the rule catching them.

---

## Carried over from v6.4.x — re-verified at 6.5.10 (2026-08-07)

Every status below was checked against live code, a live run, or `CHANGELOG.md` — never
against a roadmap or issue file's own assertion. **Items the sweep proved already shipped are
in the "explicitly not carried" list at the end of this section, so nobody re-files them.**
Rows that shipped during 6.5.3–.10 are struck through in the "Lands in" column and carry the
release that closed them; every remaining row was re-grepped against the live tree on
2026-08-07 and its line references corrected.

| Carried item | Verified status | Lands in |
|---|---|:-:|
| **DX diagnostics residual** — fail-fast inline `SYS_EXIT` parser sites + `_sync_skip` coalescing | **7 sites, not 25.** Classified all 11 `syscall(SYS_WRITE, 2, "error:", 6)` sites in `src/frontend/parse*.cyr`: 7 reach `SYS_EXIT` (`parse.cyr:809`, `:1355`; `parse_decl.cyr:324`, `:462`; `parse_expr.cyr:587`, `:695`; `parse_types.cyr:772`), 4 already `_had_error`-recover. The 18 lexer sites are pre-parse and fatal by design. Probe: 3 undefined vars in 3 statements → 1 error, exit 1. `_sync_skip` still coalesces 3 dense syntax errors into 1 report. | **Slot 1** |
| ✅ **Wrong LINE for the main source once any `include` is present** — **SHIPPED v6.5.3** | Was: reported line = actual line − (number of `include` directives preceding the token). Fixed by giving the `#@file` marker a base (`#@file "NAME" BASE`, packed into the high 32 bits of the map entry's line-count word) and deleting the second hand-rolled emitter that had been silently overwriting the correct marker — which is why an earlier correct attempt at this fix was reverted as "disproved". Re-probed 2026-08-07 at 6.5.10: 1 include + error on line 3 → `<source>:3:13`, correct. Issue archived (`2026-07-28-main-source-diagnostic-line-wrong-after-an-include`). | ~~Slot 1~~ |
| **NEW (found by this sweep)** — inverted sign test makes `assigning non-pointer to typed pointer` fire on every width/float-annotated local and **never** on a real typed-pointer local | `src/frontend/parse.cyr:1336-1337` gates on `lt > 0`, but in the local SLTYPE scheme **positive** means narrow width or a float tag (`F64_TYID`/`F32_TYID`) and **negative** (`0 - sid`) is the pointer-like case. Siblings use the other convention (`parse.cyr:1363` tests `vt < 0`; `parse_decl.cyr:2194` tests `pscale > 0`). Probes: `var x: i32 = 5; x = 6;` → bogus warning; `var x: f64 …; x += y;` → bogus warning; struct-typed local → **no** warning, i.e. the case the check exists for is unreachable. | **Slot 1** |
| **`ERR_MSG` hardcoded-length audit** — the never-done half of the v6.4.57 follow-on | v6.4.57 fixed the one filed site (`parse_fn.cyr:3732`, now 92 bytes == 92 passed, verified byte-exact). The archived issue's closing suggestion — audit every other `ERR_MSG`/`WARN` literal against its passed length — was never run. Same over-read class. | **Slot 1** (bite) |
| **Source-level version constant** (`CYRIUS_PKG_VERSION`) | `grep -rn PKG_VERSION src cbt lib scripts` → **0**. Nothing in the CHANGELOG. `src/version_str.cyr` is the *compiler's* own `--version` string, not a consumer-reachable constant. `proposals/2026-06-25-source-level-version-constant.md` is still open, pinned to "the next 6.4.x arc's closeout / an absorber band" — **that host minor closed at .86 without it**, so the pin lapsed. | **W1** (fold-in) |
| **Bare-metal deliverable #4 — forbidden-module check** | **Never built, and now invisible.** `grep -rn forbidden src/ cbt/` → one unrelated comment; `grep -rn 'host_only\|kernel_ok' src lib cbt` → 0. roadmap.md claimed the visibility arc would fold it in; v6.5.0 shipped complete with no mention of it. Its issue was bulk-renamed into `issues/archived/` on 2026-07-10 (commit `79bae42f`, an 8-file rename) **with no resolution banner** — archived unfixed. roadmap_6.md still lists it as bare-metal deliverable #4 *and* as an arc acceptance criterion. | **W2** (fold-in) — see open question 2 |
| **v6.4.15 closeout residuals D1/D2** — dead IR helpers + the speculative decoder CFG API | R2 (PE prologue) shipped v6.4.26. D1 still dead: `ir_lower_all`, `_ir_lower_node`, `ir_emit2`, `IR_BB_ID`, `IR_EDGE_FROM` are definition-only. **TRAP the file does not carry:** `ir_dce`/`ir_dead_store` are dead only as *thin uncapped wrappers* — `ir_dce_capped`/`ir_dead_store_capped` are **LIVE**, called from `src/main.cyr:2067`/`:2069`. A name-based delete sweep would take live passes with it. D2 still dead: `CLASSIFY_CF` (`decode.cyr:238`) / `CF_TARGET` (`:279`). | **Slot 3** (opening bite) |
| **`_cur_fn_ret_stash` disp↔local-index adjustment duplicated 19×** | **NOT a defect and there is no issue file** — state.md lists it as a "filed follow-on" that was never filed, and the *bug* shipped at v6.4.31. What is live is duplication: `grep -c '_cur_fn_ret_stash > 0) { disp' src/backend/x86/emit.cyr` → **19** copies of the same guard. Reframe as a one-helper (`_disp_adj`) consolidation, provable byte-identical. | **Slot 5** (bite) |
| **macOS-arm64 threading backend** | Still open at 6.5.10. No `lib/thread_macos.cyr`; `grep -rn 'bsdthread\|__ulock' lib/` → comments only. **WIDER THAN FILED:** `lib/sync_macos.cyr:2` is a 2-state `atomic_cas` **spinlock** and its own header at `:9` records that a blocking lock is a separate follow-on — macOS concurrency is **two** gaps and the filing names one. **Neither 6.5.8's thread work nor 6.5.9's three-state mutex touched it** — the mutex CHANGELOG states outright that "the macOS / Windows / agnos branches are untouched", so the Linux/macOS gap is now WIDER (48 ns futex vs a spinlock), not narrower. VR-01 guards at `vr01_thread_spawn.tcyr:31/:46` and `vr01_sync_mutex.tcyr:41/:44` keep it from rotting silently, and `2026-08-05-cross-os-full-corpus-23-failures-on-ecb` records that most of ecb's 23 full-corpus failures are downstream of this. | **Slot 11** |
| ⚠ **Release gate's cross-OS leg runs only the `vr01_` glob** — **HALF SHIPPED v6.5.8** | The **honesty half shipped**: `cross-os-selfhost.sh:326-334` now prints `corpus: N of M tcyr selected by glob 'vr01_*' (M−N NOT run on $HOST …)` on every run, and connections are batched one-per-POSIX-host instead of one-per-test. The **coverage half did not**: `scripts/release-gate.sh:110` still runs `cross-os-selfhost.sh "$H" "vr01_"` inside `for H in ecb ach cass pi` at `:108`, so at 6.5.10 that is **36** `vr01_` of **260** `.tcyr` ⇒ **224 unrun** on all four gated hosts. `CYRIUS_CROSS_OS_FULL=1` runs the whole corpus (`:321`) but is opt-in, deliberately, until ecb's 23 full-corpus failures reach zero. The issue was archived at the print half. | see W1 item 7 — the **pi full-corpus** leg is still owed, tracked by `2026-08-05-cross-os-full-corpus-23-failures-on-ecb` |
| ✅ **`cyrius distlib` has no all-profiles mode** — **SHIPPED v6.5.8** | `--all` enumerates `[lib.<name>]` from the manifest so the list cannot drift; `--check` compares **bytes**, not version strings — which is exactly what let sankoch 2.7.6's nine sub-bundles look fresh while still carrying the buggy encoder. ⛔ Both flags had previously been **swallowed by the arg loop** and silently ran the base-bundle-only path, exiting 0 — the command the issue told people to reach for already "succeeded" while doing the wrong thing. Dogfooded on all 9 bayan bundles in one command. v6.5.10 then fixed the `.deps` sidecar the same command emits. Issue file still open and awaiting archive. | ~~W1~~ |
| ✅ **Missing syscall wrappers — one pass** — **SHIPPED v6.5.7, all ten sub-items** | `sys_chdir`, `signal_default`, `fchownat`, and the whole `x*` family (`xmkdir`, `xmkdir_p`, `_xdir_exists`, `xsymlink`, `xreadlink`, `xlink`). aarch64 `fchownat` reached via the **new ≥1000 private-alias band** (`SYS_FCHOWNAT = 1054`) after both candidate numbers proved owned. Sub-item (x) needed nothing — yukti's `_yk_mkdir` bridge landed upstream at 2.3.1, vendored at 2.3.2. The `vr01_`-named tcyr the item asked for was the load-bearing line: it turned the gate red on ecb and ach and surfaced **seven** host-invisible defects. | ~~W1~~ |
| **IR substrate walls + the 10 residual IR=3 divergences** | Wall 3 (correctness) CLOSED at 6.5.2. Walls 1+2 live: `ir_lower_all` (`src/common/ir.cyr:361`) has **zero callers** (only other mention is the how-to comment at `:37`); `IR_SENABLE(S,2)` is **never activated** — and only **2 of 7 forks** call `IR_SENABLE` at all (`main.cyr:1511`, `main_win.cyr:715`, both mode 1), so the record-only/re-emit path is unreachable on aarch64, both Mach-O forks, and cx; **23** `_IR_REC0(S, IR_RAW_EMIT)` sites on the x86 path (21 `x86/emit.cyr` + `parse.cyr:1101` + `parse_expr.cyr:1968`), 13 aarch64, 7 cx; `ir_build_edges` (`ir.cyr:1388-1455`) special-cases `IR_JMP`/`IR_JMP_BACK`/`IR_JCC` only, so **`IR_SWITCH` gets exactly one fall-through edge** despite being a listed terminator at `ir.cyr:1157`. | **Slot 3** |
| **SIMD register residency** | `EMIT_F64V_LOOP` (`src/backend/x86/float.cyr:152`) is still memory → xmm → op → memory, `rsi += 2`, **no AVX branch**; there is no value-form f64v arithmetic emitter at all (only `EMIT_F64V_{LOOP,UNARY,DOT,SCALE,AXPY,FMADD}`, all memory-loop). `lib/simd.cyr`'s **value-form** wrappers still round-trip through it — **25** sites (`grep -c "(&r, &a, &b" lib/simd.cyr`): f64v2 `:519 :526 :533 :540 :548`, f64v4 `:592 :599 :606 :613 :620`, f32v4 `:667 :674 :681 :688`, plus the int-vec one-liners from `:709`. The **33 `_ptr`-form** round-trips (`:63` `:77` `:152` `:166`, … — all inside `f64v2_add_ptr`/`_mul_ptr`/`f64v4_add_ptr`/`_mul_ptr`) **stay memory-loop by design**, per roadmap_6.md item 3: *the memory-loop kernels stay for the `_ptr`/bulk forms*. Editing those is the wrong set and measures no consumer win. f32/f32v8 **did** widen to ymm during 6.4.x; f64v4 did not. | **Slot 6** |
| **Stackless coroutines / mid-body suspend across `await`** | Untouched through 6.5.10. `await` lowers to a `future_force` call (`parse_expr.cyr:1701`) and `future_force` (`lib/async.cyr:1014`) is a straight `fncall0..N` on the stored fn pointer — deferred-then-forced, run-to-completion, **no CPS transform and no force-once memoization**. Pin live at `roadmap-future.md` ("▲ PINNED v6.5.x", user 2026-07-26). ⚠ 6.5.6's `async_await_readable_ms` is a *timeout* variant on the same run-to-completion runtime — it does not touch this. | **Slot 8** |
| **Async single-waiter-per-fd multiplex** | `_async_wait_events` (`lib/async.cyr:254-273`) stores the task pointer **into the epoll `data` slot** and then calls `EPOLL_CTL_ADD` unconditionally — the data slot *is* the waiter identity, so two tasks parking one fd hit `EEXIST` and one starves. Currently double-tracked (roadmap-future watching row **and** this file's potential backlog). | **Slot 8** (bite — resolve the double-tracking there) |

### v6.5.0 arc residuals — the visibility arc shipped, three sub-commitments did not

The feature is genuinely complete and in use; the row is retired from the slot sequence. But
the arc's own published phase list made three promises that did not land, and closing the row
without naming them would be a silent subset:

1. **Feed DCE** — phase (4) was "flip to hard-error **+ feed DCE** (file-private with no
   in-file caller is *definitively* dead) + prove the win". The hard-error flip and the
   export-table half shipped; the DCE feed did not:
   `grep -rn '_vis_check\|_fn_exported\|_fnt_vis\|fileid' src/ | grep -i 'dce\|live\['` → **0
   hits**. `_fn_exported` gates `.dynsym` count/emit and GNU hash only; nothing consults
   visibility when computing reachability. This is the only part of the arc with a measurable
   size/perf payoff, which makes it a natural fit for a performance-quality minor. → **Slot 3**
   (bite, adjacent to the D1 dead-code sweep; the `_fnt_fileid` + visibility-bit substrate is
   already shipped and gate-proven).
2. **Per-item `private` in an otherwise-public file** — design point 3 in both the proposal and
   the old roadmap promises "unless an item is individually declared private". Not implemented:
   `_TL_VIS` (`src/frontend/parse.cyr:222-234`) handles token 153 by calling
   `_PRIV_MARK(FM_FILEID(...))`, a **FILE-level flip**, with an in-source comment explaining
   that a running per-item flag was deliberately rejected because it would leak into later
   includes. Consequence, compiled through `build/cycc`: `private fn h(): i64 { return 7; }
   fn main(): i64 { return h(); }` exits 0 with **no diagnostic** and the whole file — including
   `main` — is now private. The promised syntax parses and does something much broader than the
   author asked. → **open question 3** (implement the bit, or make it a diagnostic and strike
   the clause from both documents; leaving it silently mis-parsing is the one outcome to avoid).
3. **Adoption** — phase (3) "per-file adoption where it pays" is 1 file of 99
   (`grep -rln '^private$' lib/ src/ cbt/ programs/ tests/` → `lib/regex.cyr` +
   `tests/gates/frontend/visibility_private.sh` only). → rides the reactive windows a file at a time; not a slot.

### Explicitly NOT carried — proved shipped, do not re-file

- The three v6.4.57 scalar-float follow-ons: **param arithmetic + compound-assign** (probe:
  `inc(4.0)` on `fn inc(x: f64): f64 { return x + f64_from(1); }` exits 5; f64 and f32 `x += y`
  both exit 7), **`ERR_MSG` return-type over-read** (the one site; the *audit* is carried above),
  and the **f64/int compare-mix warning with literal-0 suppression** (probes: `x > 0` silent,
  `x > 5` warns, `x > y` warns — the filed acceptance verbatim). All three shipped two days
  after filing and all three issue files are archived with RESOLVED headers; the old tail-table
  row carried them as live `(P2)/(P3)` for 29 more releases and a full closeout.
- **SIMD + cx arc finish-out** (.53/.54/.58), **Intel-Mac revival** (.59, with `ach` now a
  first-class gate host), **`2026-07-02-ir3-fixpoint-cascade-overelimination`** (RESOLVED at
  6.5.2 and archived — *and its filed diagnosis was wrong*: there was no cascade,
  `ir_const_fold` alone miscompiled), **undefined-fn reachable-call hard error** (probe:
  `error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to
  downgrade)`, rc=1), **`[features]`/optional deps** (v6.3.1), **bare-metal #5/#6** (v6.3.3) and
  **#7** (v6.3.4), **`defer`** (v3.8.0 — residual is only that it is fn-scoped, not
  block-scoped), **per-block scoping + shadowing** (v3.7.4 era — residual is only that
  same-scope redecl is a deliberate hard error).
- **aarch64 native 256-bit `EMIT_F32V8_*`** (`src/backend/aarch64/emit.cyr:2882-2884` (re-derived 2026-08-11; long cited as `:2691-2693`), three
  `return 0`) are **intentional and unreachable** — aarch64 has no 256-bit register and
  `lib/simd.cyr` routes f32v8 through 2×128 NEON. Not an item. The only open question is
  whether the closeout dead-code pass deletes them or documents them; recorded in the backlog
  so it stops being re-litigated every closeout.

---

> ## ⛔ STANDING TERMINOLOGY CORRECTION — `vr01_` is dead; the selector is a DIRECTORY
>
> The `vr01_` **filename prefix** was retired at **v6.5.11** in favour of the
> `tests/tcyr/crossos/` **directory**, and the release-gate selector changed with it:
> `scripts/release-gate.sh:115` now runs `cross-os-selfhost.sh "$H" "crossos"`. This file still
> says `vr01_` in **13** places, including a `release-gate.sh:110` line reference that is now
> `:115` **with a different argument**, and a coverage figure of "36 of 260" that is now
> **45 of 269**.
>
> ⚠ **Why this is load-bearing and not cosmetic:** several of those references are shaped as
> *instructions* — "one `vr01_`-named `.tcyr` so…", "the `vr01_` file is the deliverable". A
> test added under that naming today lands **OUTSIDE the set the gate runs**, which is exactly
> the silent-green failure the reorg existed to close. **Read every `vr01_` below as "a
> `.tcyr` in `tests/tcyr/crossos/`", and write new ones there.** Historical narrative retains
> the old name deliberately.

## The slot sequence

**The ORDER is the committed part.** Release numbers are **indicative bands** — they shift as
repair tails land, and the reactive windows are anchored to *arc boundaries*, not to absolute
numbers. Sizes are `.NN` releases, each bundling several bites. **Arcs are 1–2 releases with
phases landing as commits inside them** — not one release per phase. Minors flex long; 6.4.x
ran 86 releases and 6.5.x is expected in the same class.

> ## 🔁🔁 RE-PINNED 2026-08-14 (at v6.5.21) — **THIS BLOCK SUPERSEDES THE TABLE BELOW**
>
> Re-derived after a full premise-check of all 14 open issues + 2 open proposals against
> LIVE code at 6.5.21. **Not one came back already-shipped** — the queue is entirely live,
> which is itself the finding: there is no dead weight to archive, so the sequence below is
> the real remaining cost of 6.5.x.
>
> **Measured spend, `.0`–`.21` (22 releases):** opener 3 · diagnostics 1 · **reactive /
> consumer repair 16** · pinned bugs 1 · folds+proposals 1 · **codegen spine (Slots 3/5/6):
> ZERO**. `.17`–`.18` were the pinned IR-substrate band and both went to consumer repairs.
> With **124 consumer repos** carrying a `cyrius.cyml` (45 pinned to 6.5.x) the ~73 %
> reactive rate is the LOAD, not a budgeting error — and it rises as ports land. Maintainer
> direction 2026-08-14: *"get moving on what has been roadmapped to clean up some of the
> backlog before more port over"*, and **6.5.x grows to whatever wraps up the workload**.
> Consequence: the spine is SCHEDULED FIRST, and reactive capacity INTERLEAVES rather than
> holding a slot — a burst must not silently eat a spine release the way it ate `.17`/`.18`.
>
> ⛔ **NOTHING LEAVES 6.5.x.** Later minors have their own focus. This is a resequencing, not
> a deferral. (`proposals/2026-07-05-const-eval-comptime` is the one exception and is NOT an
> exit: it was already pinned to v6.6.x with its rung chosen 2026-07-07 — option 1 `const fn`,
> `#phf` fallback — so leaving it there is honouring the pin, not moving 6.5.x work out.)
>
> ### ⟳ RE-TRIAGE 2026-08-18, at 6.5.27 — recontextualised, nothing removed
>
> Per maintainer direction: **no 6.6.x or later 6.x item is removed**; this pass only
> re-pins against what actually shipped and folds in what has been filed since.
>
> **What moved and why.** Bands A–D shipped. `.26` and `.27` then shipped work that was
> **not** the band pinned to them — the PE relocation ceiling, stiva Half A, and the macOS
> kqueue reactor — so every un-started band slips **+2 releases**. Those two releases are now
> recorded as **D2/D3** rather than left invisible, because a roadmap that hides what a
> release actually did is how band E came to be "budgeted 2 and spent 0, twice".
>
> **New band T at `.28`** — three consumer-filed tooling/DX items with no prior placement.
> Placed FIRST: all cheap, none touch codegen, and `fmt --check` is a hard CI failure for
> consumers *today* (reproduced live: exit 1, zero bytes of output).
>
> **Band H recontextualised, not deleted** — its Half A shipped and its stated justification
> ("bound to band E") is disproved in code. Half B remains, needing re-confirmation.
> **Band G** is items 1–2 only (item 3 shipped at `.24`).
>
> **✅ EVERY BAND AND FILING WAS PREMISE-CHECKED AGAINST LIVE CODE, then adversarially
> verified.** Not one status was carried over on a doc's own say-so. What that turned up:
>
> * **Band E's residual is 4, not 7** — three named tests now pass under IR=3, and the
>   remaining four bisect to **3 root causes**, one per optimizer pass. The band opens
>   substantially smaller than pinned.
> * **Band F is not greenfield** — a linear-scan regalloc is already shipped and default-on;
>   the cross-BB defect is **one line** (computed live intervals are thrown away).
> * **Band G item 2 is already LIVE**, gated to generics — a gate-widening question, not a
>   build. And item 3 has a residual: `f64v4_fmadd` was never widened.
> * **Band J is 0 % done and `.27`'s kqueue work did NOT shrink it** (orthogonal), *and* its
>   stated acceptance criterion is already green — one of its four assertions is a tautology.
> * **Two of the three new filings have refuted headlines.** So did this roadmap's own first
>   draft of band T: a first pass "reproduced" the `fmt --check` claim with a file that
>   genuinely differed from canonical form, which is reproducing *a* failure, not *the claim*.
>
> ⚠ Four counts in the previous revision were stale (`_IR_REC0` 48→**54**, simd sites
> 25→**29**, `_disp_adj` 19→**57**, macOS guards 4→**7**) and several line cites had drifted.
> **Re-derive before opening any band** — a number you did not just derive is stale.
>
> | # | band | slot | why here |
> |---|---|---|---|
> | **A** | `.22` | ✅ **SHIPPED** — Heap layout + sigil 3.12.9 | `input_buf` raise + retired `output_buf` band reclaim share **ONE** two-step bootstrap. Maintainer 2026-08-14: keeping the release clean means any heap breakage has exactly one candidate cause. **Consumer-blocking NOW** — sigil, drishti (+355 KB) and mabda (+211 KB) bundles are all over the 1 MB cap. sigil **3.12.9** rides along because it provably cannot touch the compiler (not in cycc's closure): a security fold closing the RSA sign path banking (the Bellcore verify-after-sign guard compared both operands in ONE shared lane — the v1.5 bypass shape), +9.53 MiB `.bss` reclaimed, api-surface **+2**. Retires `distlib`'s load-bearing cap workaround. |
> | **B** | `.23` | ✅ **SHIPPED** — Parser diagnostic residual + the IR=3 bleed (IR=3 divergences 11 → 4; fail-fast parser sites 7 → 1) | ⭐ **OPENS WITH TWO IR=3 BITES THAT MUST NOT WAIT FOR `.26`.** (1) **`crossos/multi_return` is IR=3-broken by 6.5.21's own headline feature** — `IR=1` exit 0, `IR=2` exit 0, **`IR=3` exit 2**, so it is the OPTIMIZER pass erasing the `movq xmm0↔rax` unbox, not the recorder. Exactly the class v6.5.2 already fixed once, and `tests/gates/ir-opt/ir3_fold_jump_span.sh` is the mutation-proven template. Leaving it until `.26` means the minor's newest feature stays IR=3-broken for a dozen releases. (2) **Raise the `ir_bb_new` block cap** (`ir.cyr:274`, `if (bi >= 32768)`) — one constant that removes **3 of the 11** divergences outright. ⚠ **THE FILE'S "UNVERIFIED, DO NOT ASSUME" NOTE IS NOW SETTLED**: those 3 are NOT miscompiles, they print `error: IR block table full`. Then: ⚠ **THE DX FILE HAS ITS DEPENDENCY BACKWARDS — R2 BEFORE R1.** `util.cyr:1152-1165` records that converting the fail-fast sites without the `_sync_skip` statement-start-keyword arm regresses the v6.5.19 lint P1 and manufactures `unexpected else` on valid `lib/fs.cyr`. ⚠ The residual **GREW 7 → 8**: `.19`'s `_ends_guard` added one. Owed decision at slot open: does a CAPACITY limit belong in the same class as `undefined variable`, or is it fail-fast by design? Answer it or a ninth appears next sweep. |
> | **C** | `.24` | ✅ **SHIPPED** — small-fix cluster | **DONE:** typed-pointer warning guard (and its wider **inverted-sign** half — Slot 1 (d) — `lt > 0` meant *narrow or float*, so it fired on every width/float local and NEVER on a real typed pointer; the GLOBAL arm's `vt < 0` had been right all along) · f32 tier helpers as **ganita 1.1.0** (23 fns, all three tiers, api-surface 4843 → 4866) · `source-diag` line shift — the foreclosed `#@file` remedy replaced by a new **`#@srcline`** position marker carrying NO count, so cbt cannot drift and `[build].modules` files of unknown length work · bare-metal forbidden-module check via a **`#host_only`** annotation, ending ~2 months unbuilt · ⭐ **f64v4 ymm widening pulled forward from band G (item 3) and SHIPPED** — 15.9 → ~7.9 ns; it needed NO IR substrate, so band G is now items 1-2 only. ⚠ **NOT shipped: the `agnosai` misleading-stdlib-error filing** — could not be reproduced in three attempts (`_dep_pull_leaves` never reached), so there is no verified fix; it needs a real git-dep-with-sidecar shape (bote / agnosai) and the issue says do not archive it on the implementer's word. |
> | **D** | `.25` | ✅ **SHIPPED** — Windows/PE stdlib parity | Take the `CYRIUS_CROSS_OS_FULL=1` decision (measured cost of flipping ecb/ach/pi: **+547 s** per gate) and close the cass residual: `SYS_IOCTL` / `sys_access`→`0xF019` / `sys_getpid`→`0xF01C` / `sys_socketpair`, each with its `crossos` companion per the wrapper rule, plus the one undiagnosed `tls_native_freestanding` HANG. **ecb/ach/pi are already 271/0**; this is Windows-peer stdlib rot the gate exists to catch. |
> | **D2** | `.26` | ✅ **SHIPPED — UNPINNED, and it displaced band E's first release** | The PE **base-relocation ceiling**: a FIXED 8192-slot window meant **no full-stdlib Windows program could be built at all**; now lazily allocated (`_PE_RELOC_CAP` 65536) — an in-place raise was impossible (`0x1DC000+0x10000` **is** `0x1EC000`, zero slack). Cap MEASURED (8192 full, 16384 fits). ⛔ Two heap-map lies fell out of it, both invisible to the heapmap gate: `enum_const_val` documented `[8192]` BYTES while really 8192 SLOTS (65,536 B) — a 57 KB understatement HIDING a 49 KB overlap — and `0x1DA000 "DCE bitmap"` a PHANTOM with zero code accesses. Plus **stiva coroutines Half A**. |
> | **D3** | `.27` | ✅ **SHIPPED — UNPINNED** | **macOS gets a REAL reactor: kqueue.** `sys_kqueue`/`sys_kevent` routed through BOTH macho backends (private-alias band 1362→362, 1363→363); `lib/async_macos.cyr` is a kqueue multi-waiter. Verified **23/23 on ach AND ecb**. The async reactor test now runs on FOUR hosts (crossos 48 → 49). Plus sankoch 2.7.8 (pin-only fold). ⚠ `.26` had shipped the reactor fix "Linux only" **with four hosts idle** — pi is aarch64 LINUX and epoll works there; it was never run, not blocked. |
> | **T** | `.28` | ⭐ **Consumer-filed repair cluster — RE-SCOPED 2026-08-18: the queue grew 11 → 17 while `.27` was cutting** | ⭐ **LEADS WITH THE ONE HIGH:** **decimal float literals past ~9 significant digits parsed to a DIFFERENT NUMBER** — `3.1415926535` → `0.95822`, `3.141592653589793` → `0.061575` (off by 51×), with no error, no warning, clean lint, and plausible-looking output. Found porting ranga's Oklab matrices, i.e. exactly where 10-17 significant digits is normal. **Root cause: TWO overflows in one line** — the token packed `(denom << 32) | (numer & 0xFFFFFFFF)`, so the mask truncated `numer` AND `denom << 32` overflowed the i64 outright past 9 fractional digits. ✅ **FIXED**: full-i64 numer/denom via a lazily-allocated side table (`FLIT_ADD`), all THREE `EMIT_FLOAT_LIT` backends re-pointed. ⚠ A "cap the digit count" fix would have been smaller and still LOST precision silently — the same defect class, quieter; `crossos/float_literal_precision.tcyr` asserts the `100.123456789` case specifically to kill that shortcut. **Remaining band-T queue, by severity:** `_auto_deps` reads only the first **4095 bytes** of `cyrius.cyml` so a later `[deps]` is invisible (Medium, misleading diagnostic) · a `[deps].stdlib` entry reached TRANSITIVELY never gets its top-level `include` prepended (Medium, hard build failure on a shipping consumer) · `_distlib_named_deps` scans the manifest UNANCHORED, so a `[deps.X]` written in COMMENT PROSE deletes X from the sidecar (Medium, silent packaging corruption) · `fl_calloc` re-zeroes already-zero mmap'd pages a byte at a time, **369× slower than the allocation** (Medium perf, no correctness impact) · `cyrius fuzz` blind to out-of-bounds READS (Medium-High tooling; every premise verified, the best-formed of the filings) · `distlib` named-profile sidecar (Low; title + symptom-2 + hypothesis all refuted by measurement — re-title before scheduling) · assignment ignores the callee's declared return type so `t = str_new(…)` warns (Low, diagnostic only) · `fmt --check` (⛔ headline REFUTED — wrapped calls are NOT rejected; the real defect is that it exits 1 with ZERO bytes, so any difference is a silent CI failure). |
> | **E** | `.29`–`.31` | **⭐ Slot 3 — IR substrate productionization. THE SPINE OPENS.** | ⛔ **RE-MEASURED LIVE AT 6.5.27 (273-file corpus, exit code AND stdout): the residual is 4, NOT 7.** Three of the named seven — `float`, `math_inverse_trig`, `math_pack_integration` — now pass under `CYRIUS_IR=3` with 0 failed assertions, and the capacity trio is confirmed gone (`IR block table full` appears in ZERO of 273 IR=3 compiles after band B's raise). ⭐ **The 4 remaining divergences bisect to 3 ROOT CAUSES, isolated by pass with the live knobs**: **LASE apply** owns `subword_signed_load` + `types` (both sub-i64 width semantics — near-certainly ONE defect, so 2 tests / 1 fix); **`ir_const_fold`** owns `const_chained_multiply_fold`; **DCE** owns `field_name_shadows_global` (SIGSEGV). ⚠ `CYRIUS_LASE_OFF` is a COARSE knob — `ir_apply_lase` is the shared NOP-fill applier for DCE+DSE too, so LASE_OFF masks the DCE bug; isolate with fold+DCE+DSE off. ✅ Wall 3 still CLOSED (IR=3-built cycc 1,235,368 B, +57,344 B, `cmp`-identical output). ✅ `ir_lower_all` mode-2 still ZERO callers. ⚠ **`_IR_REC0(IR_RAW_EMIT)` is 54, not 48** — `parse_expr.cyr` has **7**, not 1 (the six missed are f64 intrinsic branches, exactly the raw-emit shape DCE cannot see through). ⛔ **NEW, not previously in the roadmap: `ir_add_edge` SILENTLY drops every edge past 8192** (`ir.cyr:341` returns 0 = success) while `ir_build_edges` increments its count unconditionally — a fabricated edge count on any large fn. ⛔ **The substrate exists ONLY in `src/main.cyr`**: `main_win.cyr` is analysis-only and the other 5 forks have no `IR_SENABLE` at all — which materially changes what "productionization" means. |
> | **F** | `.32`–`.33` | **Slot 5 — cross-BB regalloc + vector register class** | ⛔ **"Hard-gated on E" is only HALF true — a live regalloc ALREADY EXISTS.** A Poletto-Sarkar linear-scan picker is shipped and DEFAULT-ON for every fn, so this band is not greenfield. ⭐ **The cross-BB defect is live and localised to ONE line**: the picker computes real live intervals (`ra_first`/`ra_last`) then THROWS THEM AWAY — every interval's end is force-set to the fn end, so the expire step never fires and assignment is greedy-forever. Reproduction run. **Vector register class genuinely absent** (the byte matcher only recognises REX.W mov to/from `[rbp+disp32]`). ⚠ `_disp_adj` consolidation is undone and the scope is **57 sites tree-wide, not 19** — of which **44** are helper-replaceable. |
> | **G** | `.34`–`.35` | **Slot 6 — SIMD register residency** | ✅ **Item 3 SHIPPED at `.24`** (confirmed live). **Item 1** (register-resident value-form f64v arithmetic) genuinely unbuilt — all 15 emitters in `float.cyr` are memory→register→op→memory loops, *including* the ymm one. ⛔ **Item 2 is the biggest correction: the wrapper inliner is NOT unbuilt — it is LIVE and FIRES TODAY**, gated to generics only. The row treated it as work behind the IR substrate; it is a GATE-WIDENING question, not a build. ⚠ The "25 sites" grep is stale — live is **29**, and it grew *because* item 3 shipped (each widened wrapper added a round-trip form). ⚠ **Item 3 has a residual: `f64v4_fmadd` was NOT widened** — still the 128-bit SSE loop with no `simd_has_avx2()` gate. |
> | **H** | `.36` | ⚠ **RE-CONTEXTUALIZED — Half A SHIPPED at `.26`/`.27`; what remains is NOT what this band said** | ⛔ **The pin's stated justification was FALSE and is now disproved in code**: "bound to band E's substrate so the poll runtime is not built twice" — band E lives entirely in `ir.cyr` and only runs under `CYRIUS_IR` (5 of 7 forks never enable it), and `lib/async.cyr` is **not included by cycc at all**, so "built twice" had no referent. ⭐ **The real blocker was a lost-wakeup BUG, not a missing language feature**: `_async_wait_events` put the TASK POINTER in the epoll data slot so an fd held exactly ONE waiter, and `EPOLL_CTL_ADD`'s `-EEXIST` was UNCHECKED. Fixed lib-only. **Both stiva features are unblocked** — two waiters on one fd, and two waiters on one fd wanting OPPOSITE directions (the `exec -it` TTY shape) — verified on Linux, aarch64, Intel-Mac and arm64-Mac. **Remaining here = Half B only** (a compiler-level CPS transform), which on this evidence is **unjustified for the two filed features** and should be re-confirmed as wanted before any release is spent on it. ⚖️ Maintainer call. |
> | **I** | `.37` | **Slot 9 — sum-type variant unboxing** | Defect reproduces **byte-identical at 6.5.27** (`per call = 16`) — the filed repro was re-run live. The `.15` unboxing attempt is **fully reverted**, no remnant. ✅ Pair-return substrate confirmed shipped at `.21` and **WIDER than the issue credits**. ⚠ The 9a prerequisite numbers confirmed exactly (**106 unannotated, 0 cyrius-owned**) — but note a naive `^fn ` scan UNDERCOUNTS badly, since yukti alone declares 321 `pub fn`. ⚖️ **Still scopable as ONE release, but ONLY after the maintainer picks a design** — escape analysis and scope-tied arena are both genuinely unbuilt, neither has any compiler substrate today. |
> | **J** | `.38` | **Slot 11 — macOS-arm64 concurrency** · last in the minor | ⛔ **0 % DONE — and `.27`'s kqueue work did NOT shrink it.** Verified ORTHOGONAL: `lib/async_macos.cyr` has zero occurrences of `thread_create`/`thread_join`/`mutex_lock`; it is a single-threaded cooperative loop. The kqueue work is *prep-knowledge*, not deliverable progress. Both named halves unimplemented: every `bsdthread`/`__ulock` hit in `lib/` is a COMMENT. `lib/sync_macos.cyr` is still the 33-line 2-state `atomic_cas` **spinlock** (`while (atomic_cas(m,0,1) == 0) { }`, no backoff, no kernel wait). ⛔ **The stated ACCEPTANCE CRITERION is already green and no longer discriminates** — re-derive it: the real un-guard list is **SEVEN** macOS guards across four crossos tests, not four, and one of them (`sync_mutex_contended.tcyr:71`) is a **TAUTOLOGY** (`assert_eq(_cm_counter, _cm_counter, ...)`). ⚠ `thread_detach.tcyr:133`'s guard is STALE and removable TODAY with no band-J work. ⚠ Inherits the ecb caveat: unsigned arm64 binaries are SIGKILLed by AMFI, which reads exactly like a miscompile. |
> | **K** | `.39`+ | **Closeout band** | Per cycle-discipline.md's runnable checklist; record the run in the ledger. |
>
> **▣ Reactive capacity: INTERLEAVED, not slotted.** At the measured rate a `.NN` of repair
> lands roughly every 3rd release. It is deliberately NOT given band numbers — naming bands
> is what let `.17`/`.18` be consumed while the table still claimed the spine was progressing.
> **A reactive release inserts and pushes the spine right; it never replaces a spine slot.**
> `embed-data-files` (its `CYRIUS_PKG_VERSION` prerequisite discharged at `.21`) is the named
> fold-in candidate; `ranga`/ganita f32 tiers 2–3 are the second.
>
> ---
>
> ## 🔁 RE-PINNED 2026-08-11 (at v6.5.19) — superseded by the block above, kept for lineage
>
> The table below was written against a project that stopped at `.10`. Nine releases then
> shipped and consumed every band from `.11` onward. The re-triage re-pinned the whole
> remaining sequence from `.20`; **the committed ORDER is preserved**, with three deliberate
> changes, each with a reason:
>
> | change | why |
> |---|---|
> | **New Slot 0 at `.20`** — the switch-case P1 + derive line-numbering | Two items were already pinned to `.20` by the `.19` closeout. The switch-case bug is a **silent miscompile of ordinary valid cyrius**, which outranks everything else in the minor. |
> | **New Slot 0b at `.21`** — ONE heap-layout release | Two independent heap-LAYOUT changes are queued (`input_buf` raise; `output_buf` band reclaim). Each carries a two-step bootstrap. **Doing both in one two-step bootstrap is materially cheaper than two**, so the `output_buf` reclamation is pulled *forward* out of the Slot 12 closeout band to join it. ⚖️ This is a packing decision the maintainer may want to confirm — it is the same work in a cheaper order, not a re-scope. |
> | **New Slot 1b at `.22`** — the diagnostics finish-out | Slot 1's (b)–(e) have been homeless since `.3` — **sixteen releases** past their stated landing window — and the fail-fast residual is still **GROWING** (7 → 8 sites; `.19` added `_ends_guard`). Arc finish-outs go soonest. It absorbs the four orphaned fold-ins that W1/W2 never spent. |
>
> Everything after `.22` is the original committed order — Slot 3 → 5 → 6 → 8 → 9 → 11 →
> closeout — with re-pinned bands. **Nothing codegen is parked to 7.x** (audited 2026-08-11:
> no violation found in any of the three roadmap files; 7.x holds LEGAL-01 and the
> stdlib-reference authoring only).

| # | Indicative | Slot | Contains (phases = internal commits) | Absorbs |
|:-:|:-:|---|---|---|
| **0** | **`.20`** ⭐ **NEXT** | **The two pinned bugs** (1) — switch-case P1 **first**, derive line-numbering second | **Bite 1 — `switch`: a case body can only be left safely by `return`.** SILENT miscompile: with `default:` present, `p(2)` returns **exit 0 when 2 is expected**, and `p(1)`/`p(3)` **SIGSEGV**; on cx, `break` in a case **HANGS**. Re-verified on HEAD `build/cycc` 2026-08-11. ⛔ **The filing's "per-backend (x86/aarch64/macho/PE/cx)" reason is wrong** — `parse.cyr:453-454` forces `use_table = 0` on aarch64 and cx, so the table path is **x86-family only**, and both defective halves (table patch + gap-fill arithmetic; the break chain) are in the **shared frontend**. It is a **one-file fix**. Needs a jump-table + break-chain protocol and a corpus fixture with **non-`return` case bodies** — `codegen/switch_dispatch.tcyr` has 77 `case` lines and **zero**, which is why 270 tcyr and four hosts are green. **Bite 2 — `#derive` line-numbering.** ⛔ **REBUILD, not rebase**: the design-1 implementation recorded as "built and verified" is **not on disk anywhere**, so every verification is a re-run. Ship with its remedy (copy the tail, stop at the first `#`, never copy the newline) — without it the change **silently loses code**. ⭐ Both need the same four-host gate, so run **ONE** cross-OS cycle covering both. **Rides free:** the D1/D2 dead-code removal (byte-identical-safe, zero call sites re-verified today) and the doc/queue hygiene this re-triage landed. | `2026-08-11-switch-case-body-only-exits-safely-via-return`, `2026-08-11-derive-generated-code-inflates-line-numbering`, `2026-07-07-v6415-closeout-residuals` (D1/D2 half) |
| **0b** | **`.21`** | **The heap-layout release** (1) — **ONE two-step bootstrap for BOTH** | Raise cycc's **1 MB stdin `input_buf`** (sigil's dist bundle is **1,079,160 B** as of 2026-08-11 — it has grown another 92 B since filing and is **30,584 B over**), *and* reclaim the retired **`output_buf` band** (`0x4D9D000`, 16 MB, documented RESERVED in all five `src/main*.cyr` forks, **nothing has written it since v6.4.52**). ⭐ **The entire reason this is a slot and not two scattered items**: both are heap-LAYOUT changes, each carrying a two-step bootstrap, and pairing them halves that cost. ⚠ Raising `input_buf` relocates `tok_names`, nested in the same megabyte — the pool end must stay ≤ `0x100000`. ⚠ `tok_types` used to live at `0x4D9D000` and has since moved to `0x2D7C000`; check for stale references to the old address before reclaiming. ⚠ `distlib`'s self-check routes through a generated include entry and that workaround is **load-bearing** until this lands. | `2026-08-08-stdin-input-buf-1mb-cap-reached-by-sigil-bundle`; the `output_buf` item carried forward out of Slot 12 |
| **1b** | **`.22`** | **DX / diagnostics finish-out** (1) — the oldest homeless commitment | **Slot 1 (b)–(e), finally homed.** (b) the fail-fast parser `SYS_EXIT` sites — now **8, not 7**: `.19` added `_ends_guard` (`parse.cyr:369`), so the set is **still growing** while the residual sits unpinned. ⚖️ Decide explicitly whether a *capacity* limit belongs in the same residual class as `undefined variable`, rather than letting the next sweep discover a ninth. (c) `_sync_skip` still resyncs on `;`/`}`/EOF only, no statement-start-keyword arm. (d) the inverted-sign typed-pointer warning, `lt > 0` — **now at `parse.cyr:1405`/`:1413`**, drifted from the `:1336-1337` this file cited. (e) the `ERR_MSG` hardcoded-length audit sweep. **Absorbs the four orphaned fold-ins W1/W2 never spent**: `CYRIUS_PKG_VERSION` (W1 item 8 — **two lapsed pins**, 0 hits in live code), the `folds_agnos_parity` SKIP list (W1 item 9), the **two cyrlint gates** (verified unshipped by *running* `cyrius lint`: a bare-local over-slot write and a wrong-LEN `SYS_WRITE` both report **0 warnings**), and the **bare-metal forbidden-module check** (restored from `archived/`, where it sat **unfixed with no resolution banner**). | `2026-07-12-dx-multi-error-reporting`, `2026-06-28-bare-metal-forbidden-module-check-unbuilt`, `proposals/2026-06-25-source-level-version-constant` |
| **1** | **.3** ⚠ **PARTIAL — (b)–(e) now homed at `.22`, Slot 1b** | **Diagnostics finish-out** | ✅ (a) the include-line delta — **shipped v6.5.3**. ⛔ **(b)–(e) DID NOT SHIP and have no new slot.** Re-verified live 2026-08-07: (b) the 7 fail-fast `SYS_EXIT` parser sites are all still there (`parse.cyr:809`, `:1355`; `parse_decl.cyr:324`, `:462`; `parse_expr.cyr:587`, `:695`; `parse_types.cyr:772`); (c) `_sync_skip` (`src/common/util.cyr:1188`) still resyncs on `;` / `}` / EOF only, with no statement-start-keyword arm; (d) the inverted-sign typed-pointer warning is still `lt > 0` at `parse.cyr:1336-1337`; (e) the `ERR_MSG` hardcoded-length audit sweep has no CHANGELOG entry anywhere in the 6.5.x band. **This is the sliced-fix shape the discipline forbids — one release took the easy quarter and the rest went unpinned.** They need a home: fold into W1's remaining `.11`–`.16` or open Slot 1b. | `2026-07-12-dx-multi-error-reporting` (still open). `2026-07-28-main-source-diagnostic-line-wrong-after-an-include` archived at .3. |
| **2** | **.4–.16** ✅ **CONSUMED** | **▣ W1 — reactive window #1** (**13**) · **ALL 13 SPENT** | Known drain queue + reserve held for the **agnosai port**. See the window block below. | ✅ closed: `2026-07-29-no-portable-xmkdir-in-io-cyr` (.7), `2026-07-26-no-lchown-wrapper…` (.7), `2026-07-28-agnosai-no-nlogn-sort-in-stdlib` (.4), `2026-07-14-release-gate-cross-os-runs-only-vr01-glob` (.8, print half), `2026-07-29-fmt-int-buf-i64-min` (.8), `2026-07-29-mutex-unlock-unconditional-futex-wake` (.9), `2026-07-26-distlib-has-no-all-profiles-mode` (.8). ⏳ ~~still owed: `2026-07-26-agora-fs-dir-list-per-call-alloc`~~ — **✅ SHIPPED `.11`+`.12` and ARCHIVED; struck 2026-08-11.** The one genuinely owed survivor, `proposals/2026-06-25-source-level-version-constant`, is **re-homed to Slot 1b (`.22`)** — it has now lapsed **two** soft pins (the 6.4.x closeout, then this window) precisely because it was tracked in a slot-table row nobody re-derived. |
| **3** | **`.23`–`.24`** *(was .17–.18, consumed)* | **IR substrate productionization** (2) — **the perf anchor** | Opening bite: D1/D2 dead-code removal + record the new `note: N unreachable fns` floor. Then Wall 2 (local-access opcode model; `IR_SWITCH` + unresolved-edge CFG completion). Then Wall 1 (`ir_lower_all` mode-2 activation, proven byte-identical on `differential.sh`). Then a `CYRIUS_IR=3` axis added to `differential.sh` and the 10 residual divergences closed with it. Plus the visibility→DCE feed. | `2026-07-02-ir-regalloc-rewrite-needs-reemit` (Walls 1+2), `2026-07-07-v6415-closeout-residuals` (D1/D2) |
| **4** | **.19** ✅ **CONSUMED** | **▣ W2 — reactive window #2** (budgeted 3, spent 1; `.20`–`.21` reassigned to Slots 0/0b) | At the substrate/regalloc seam. Mostly reserve. Named fold-ins: bare-metal forbidden-module check; the two cyrlint gates; visibility adoption files. | — |
| **5** | **`.25`–`.26`** *(was .22–.23)* | **Cross-BB regalloc with a vector register class** (2) | The vector class is planned in **from the start, not retrofitted** — standing decision from roadmap_6.md. Copy-propagation and cross-BB DSE land as bites inside (both proven inert-if-sound / miscompiling-if-not on the raw substrate at v6.3.28). Plus the `_cur_fn_ret_stash` 19-site `_disp_adj` consolidation. | (downstream half of `…ir-regalloc-rewrite-needs-reemit`) |
| **6** | **`.27`–`.28`** *(was .24–.25)* | **SIMD register residency** (2) — the substrate's payoff · ⭐ **the minor's acceptance anchor** | Register-resident value-form f64v arithmetic; wrapper inlining so `f64v_add(&r, a, b, 2)` stops round-tripping through memory; f64v4 widened to `vmulpd`/`vaddpd` **ymm** under `simd_has_avx2()`. Scope = fix-list items 1–3 only. | `2026-07-06-simd-f64v-memory-operand-no-register-residency` |
| **7** | **`.29`–`.33`** *(was .26–.30)* | **▣ W3 — reactive window #3** (5) | The burst-risk window. See the window block below. | (reserve; `sock_accept`#57 VFS-fd bridge is the named candidate) |
| **8** | **`.34`–`.35`** *(was .31–.32)* | **Stackless coroutines / mid-body suspend-resume across `await`** (2) | CPS transform + poll-runtime rework + force-once memoization as bites. Folds in the async **single-waiter-per-fd multiplex** (the same `_async_wait_events` rewrite) and the shipped async arc's "gap 6". Acceptance = stiva's `exec -it` TTY relay + a true multiplexed streaming server. | `2026-07-25-stiva-stackless-coroutines-interactive-exec` — **stays OPEN as the acceptance record until this slot ships; do not archive it in a rot sweep** |
| **9** | **`.36`–`.37`** ⚖️ **BLOCKED — maintainer design decision** | **Sum-type variant unboxing** (2) — *retitle at pin time* | Filed as "`sock_send` allocates"; it is the compiler's variant **lowering**. ⛔ **THIS SLOT'S COMMITTED DESIGN WAS IMPLEMENTED AT v6.5.15 AND REVERTED — the roadmap had no record of it until 2026-08-11.** ~~Fix option 1 only: unbox the scalar case (tag + i64 payload in a register pair, no allocation).~~ Per `CHANGELOG.md` [6.5.15]: it *"passed **every** gate (`delta=0`, check.sh 165/0, self-host, seed-derive, 264/264), then refuted by an adversarial verifier and reverted. A per-call-site global box made Results from one site share a slot, so a retaining loop reported **a failed file open as success**. Both storage relocations are now disproven — frame slot too short, static too shared — which settles that the fix needs escape analysis or a scope-tied arena, not relocation."* ⚖️ **The surviving designs — escape analysis, or a scope-tied arena with reclaim — are a different SIZE CLASS from "unbox into a register pair", so this slot cannot be scoped until the maintainer chooses.** ⚠ The issue's own later "9b: a hidden retptr into the CALLER's frame" is the same relocation the revert disproved — superseded, not a third option. ⚠ The **9a prerequisite is entirely upstream**: every unannotated `Ok`/`Err` producer in `lib/` is in a **folded** module (sigil, yukti, vani, mabda, bayan), **zero** in cyrius-owned files — a five-repo coordinated fix-at-source, not a cyrius patch. **Full ecosystem ABI cross-walk at arc-open, one coordinated filing, not drip.** | `2026-07-28-sock-send-result-allocates-per-call` |
| **10** | **`.38`–`.41`** *(was .35–.38)* | **▣ W4 — reactive window #4** (4) | Feeds the closeout — a drained queue going in, so the closeout's re-triage doesn't displace releases. | (reserve) |
| **11** | **`.42`** *(was .39)* | **macOS-arm64 concurrency** (1) — last in the minor | ⛔ **PREMISE HALF-FALSE — corrected 2026-08-11.** This row's supporting text asserted *"No `lib/thread_macos.cyr`"*; **the file exists** (8,614 B, added v6.5.11) as a documented single-threaded **SERIAL fallback**, so the worker actually runs. The other half holds exactly as written: `grep -rn 'bsdthread\|__ulock' lib/` → **9 hits, ALL comments, zero call sites**, and `sync_macos.cyr:2` is still "A 2-state atomic_cas SPINLOCK". ⭐ **The last argument for pulling this slot earlier is also gone**: the linked issue claimed "most of the 23 full-corpus ecb failures are downstream of this", and a real full-corpus run on ecb at 6.5.19 returns **269/0**. Nothing is downstream; no consumer is blocked; it stays last. Remaining work, narrowed: `lib/thread_macos.cyr` driving `bsdthread_create` + `bsdthread_register` (mirroring the `thread_win.cyr` split) for `thread_create`/`thread_join`, **and** `__ulock_wait`/`__ulock_wake` replacing `sync_macos.cyr`'s spinlock for the mutex + channel wait/wake. Acceptance = un-guard the four VR-01 assertions and get the full worker/counter/channel checks green on **real ecb** — not a hello-world smoke. | `2026-07-03-macos-threading-workers-dont-run` |
| **12** | **`.43`+** *(was .40+)* | **Closeout band** | Not a single release. `release-gate.sh` mechanical gates, then the judgment passes (heap map, dead code, refactor, code review, cleanup), then security re-scan + downstream check, then doc sync + backlog re-triage. Run it per [cycle-discipline.md](cycle-discipline.md)'s runnable checklist and **record the run in the ledger**. ⛔ **MOVED OUT 2026-08-11 → Slot 0b (`.21`).** ~~Carried in by name: reclaim the retired `output_buf` band.~~ It is paired there with the `input_buf` raise so the two heap-LAYOUT changes share **ONE** two-step bootstrap instead of paying for two. Retained here for context: `0x4D9D000 output_buf [16777216]` is documented in the heap map of all five `src/main*.cyr` forks but **nothing has written it since v6.4.52**, when output became a 1 GiB off-heap `alloc(1073741824)`. The 6.5.10 doc sweep corrected the *description* only and deliberately left the band RESERVED so the overlap audit stayed unchanged — reclaiming 16 MB of address space is a heap-LAYOUT change, which is closeout item 4's job ("any region no code writes to → candidate for removal") and carries the two-step bootstrap — **which is exactly why it now rides `.21` with the other layout change rather than waiting for closeout.** ⚠ `tok_types` used to live at this address and has since moved to `0x2D7C000`; check for stale references to the old address before reclaiming. | — |

**Totals, re-derived 2026-08-11 at `.19`**: **20 spent** (4 pinned-arc + 16 reactive). Ahead:
**3** repair/finish-out releases (`.20`–`.22`) + **11** of pinned codegen arc (Slots 3, 5, 6, 8,
9, 11) + **9** of remaining reactive window (W3 5 + W4 4) = **23**, landing the closeout band at
**`.43`**. With the 6.4.x precedent that every codegen arc grows a repair tail (`.80`/`.81`/
`.83`/`.84` were all displaced by closeout-found bugs), the honest close is **`.43`–`.48`** —
comfortably inside the 45–99 norm, i.e. **~23–29 releases of runway remain**. The remaining
headroom is those repair tails and whatever the user pivots to. **Only the user pivots focus.**

> ⚖️ **MAINTAINER BUDGET CALL — the reactive rate is ~80 %, not the ~65 % this plan budgets.**
> 16 of the 20 releases shipped so far were reactive. W3 + W4 budget **9** more against **11**
> of pinned arc; on the observed rate that is optimistic, and the failure mode is the one this
> minor already lived through — windows silently absorbing the arc's bands until the arc has no
> numbers left. Either widen the windows (and accept a later close), or hold the line and let
> reactive filings displace releases explicitly rather than silently. **Surfaced, not decided.**

**Burn-down at 6.5.19 (2026-08-11, re-derived)**: **20 of ~37 spent** — `.0`–`.2` (the opener
arcs, before the sequence was pinned), `.3` (Slot 1, **partial**), and `.4`–`.19` as **sixteen
consecutive reactive / consumer-repair releases**.

> ### ⛔ BOTH reactive windows are fully consumed at `.19`, and the codegen spine is at ZERO
>
> W1 was budgeted at **13** (`.4`–`.16`) and W2 at **3** (`.19`–`.21`) — **16 reactive releases
> of budget**. `.4` through `.19` is **exactly 16 releases of reactive spend**. Meanwhile every
> pinned codegen slot (3, 5, 6, 8, 9, 11 — eleven releases) remains **untouched**, verified
> against live code rather than against this file's own claims.
>
> That is the single most important fact about this minor's shape, and the old burn-down
> ("11 of ~37 spent", stamped 6.5.10) hid it. **The reactive rate is ~80 %** — 16 of the 20
> releases shipped. W3 (5) + W4 (4) budget 9 more, which on the observed rate is optimistic;
> whether to widen them is a **maintainer budget call**, surfaced below, not an agent's.
>
> Consequence for the bands: the old table pinned Slot 3 to `.17`–`.18` and W2 to `.19`–`.21`,
> **all of which shipped as other work**. The ORDER was and remains the committed part (this
> section's own preamble says so); the NUMBERS below are re-pinned from `.20`.

### Why the sequence is ordered this way

- **Diagnostics first (Slot 1).** 6.5.0 shipped file-scoped `private`, so **every visibility
  error is cross-file by construction**, and both live private diagnostics
  (`parse_fn.cyr:1127`, `parse_types.cyr:772`) print through `_err_head` — which means the
  first thing a consumer adopting the new feature meets is a wrong line number. The bug is
  wrong on essentially every real program. Batching (a)–(e) means **one** negative-corpus run
  across ecb/ach/cass/pi, **one** `CYCC_FUZZ_ITERS=300 sh tests/gates/diagnostics/cycc_parser_fuzz.sh`, and one
  seed-derive (the preprocessor is in cybs's path). Five of the seven `SYS_EXIT` sites are the
  same `undefined variable` diagnostic, and the recovering pattern is already established
  in-tree — the four error sites added by the 6.5.x arcs (`parse_fn.cyr:1043`, `:1127`,
  `:1604`, `parse_types.cyr:688`) were all written that way with comments explaining why.
- **W1 before the IR arc (Slot 2).** Landing it **before** the substrate arc means it cannot
  perturb the `CYRIUS_IR=3` differential baseline; landing it after adds noise to every
  default-vs-IR=3 comparison.
  **Several of its bites are NOT byte-identity-free, and the window must treat them that way.**
  cycc's *transitive* lib closure from `src/main.cyr` is **seven** files (re-derived
  2026-08-07) — `alloc`, `alloc_agnos`, `alloc_macos`, `alloc_windows`, `atomic`, `fnptr`,
  `vec` — because `lib/alloc.cyr:44` includes `lib/atomic.cyr` (and `:113/:117/:123` the
  platform allocators, `:573` `fnptr.cyr`). A one-level grep of `src/` reports only four, and
  two of those four are `slice` and `syscalls_macos`, which appear in `src/` **only inside
  comments** (`parse_expr.cyr:516`, `backend/macho/emit.cyr:18`) and are not compiled into
  cycc at all. So: the `vec_sort_by` bite touched `lib/vec.cyr`, the three-state-mutex bite
  `lib/atomic.cyr`, and the v6.5.9 growable arena and v6.5.10 `alloc_via` rework both
  `lib/alloc.cyr` — all inside the closure. **All four carried the explicit self-host fixpoint
  AND seed-derive and all four passed** (`.9`'s CHANGELOG states it outright: "cybs compiles
  it and `gen2 == build/cycc`"), so the discipline held — record it as a positive result, not
  as a rule nobody has tested. New top-level fns in a cycc-included file remain precisely the
  shape that trips cybs's global/call-reference ceiling, which only seed-derive catches. This
  is the v6.4.1 lesson restated: *a lib fix is NOT automatically byte-identical when cycc
  includes it.*
- **IR substrate is Slot 3, not Slot 1.** Its blocking premise ("CYRIUS_IR=3 miscompiles real
  programs") died at 6.5.2 for a mundane reason, so it is now *unblocked work* rather than a
  blocked prerequisite — and everything downstream (regalloc, vector class, residency,
  copy-prop/DSE, the coroutine poll-runtime) unblocks the moment it lands. It goes as early as
  the queue allows, but not ahead of the byte-identity-free drain.
- **Regalloc + vector class as one arc (Slot 5).** roadmap_6.md's standing decision: *"the
  vector class is what lets SIMD values live in registers; planned in from the start, not
  retrofit."* Splitting the scalar and vector halves into separate rows is exactly what invites
  the retrofit. Copy-prop and cross-BB DSE are bites inside, not thin releases — and note the
  names `ir_copyprop_recon`/`ir_extdse_recon` that roadmap_6.md promises to "revive" **do not
  exist** (`grep` → 0 hits): both passes must be built, not revived.
- **Residency is the minor's acceptance anchor (Slot 6).** This is why the theme was reframed
  from self-compile growth tax to *generated-code quality*: consumer numeric code sits 10–38×
  behind its Rust baseline, and hand-SIMD gains ~5 % where LLVM gains 2–4×. The svara
  `process_block 1024` figure (186 µs vs Rust 4.84 µs at filing) is the number the minor is
  judged on.
- **Coroutines after the substrate (Slot 8).** Bound by design: the poll-runtime rework plus
  force-once memoization sit on the substrate Slot 3 builds. Running it earlier means building
  that substrate twice.
- **Sum-type unboxing late (Slot 9).** It is ABI-breaking across the ecosystem —
  `lib/result.cyr`'s own helpers and `lib/tagged.cyr` read the box directly with
  `load64(res)`/`load64(res+8)`, and downstream consumers do too — so it wants a stable
  compiler underneath it and a full cross-walk at arc-open. Ready-made acceptance exists:
  sandhi 1.9.6's `test_server_reject_arena_is_flat` currently asserts the delta over 600
  responses is exactly 600 × 16; the expected figure becomes **0**.
- **macOS concurrency last (Slot 11).** Real platform work with a real broken verb on a gate
  host, so it cannot be dropped — but it is the only pinned row with **no consumer waiting**,
  it mirrors an already-shipped split, and the VR-01 guards mean it cannot rot silently. See
  open question 4.

---

## Reactive windows — deliberately-unallocated capacity

**These are budget, not filler, and not slack to be raided when an arc runs long.** Agnos ABI
mirrors and consumer-filed repairs land as their own releases *between* arcs, following the
bare-metal open-window pattern. They are **not** counted inside the arc sizes above. The old
roadmap said reactive work was "not counted in the arc lengths", which in practice gave it no
budget at all — that is what these four windows fix.

**Measured baseline** (counted from `CHANGELOG.md`, per release touching
`lib/syscalls_x86_64_agnos.cyr`): 6.0.x **0.33** slots / 10 releases · 6.1.x **0.24** · 6.2.x
**1.32** · 6.3.x **0.65** · 6.4.x **1.40** (11 of the 12 were new syscall numbers; `.68` was an
ABI widen of existing `#13`). Broadening to all agnos-facing reactive work in 6.4.x → **~1.9 /
10 releases**. Over ~50 releases that is **~9–10 agnos-facing items, ~7 of them syscall/ABI-peer**.

**Unit cost is small; clustering is the real constraint.** 6.4.x's 11 new-number slots covered
32 numbers — modal size **2 wrappers**, median 2, mean 2.9, **every one fit in ONE release and
every one was cycc byte-identical** (the peer is `#ifdef CYRIUS_TARGET_AGNOS`-ed out of every
non-agnos build, so it sits outside cycc's include closure). Several rode along inside releases
doing unrelated work — `.70` carried `#84`/`#85` **plus** the gate-placebo fix **plus** two
folds; `.82` carried the entire closeout **plus** the TS arena fix **plus** `#94`/`#95`. But
`.63 → .73` was **6 agnos slots in 11 releases** (0.55/release) when agnos's GPU arc stood up
the ring-3 band `#82`–`#93`, while the other ~53 releases of the minor carried 2 slots. **Size
the windows for the bursts and for the gnarly-bug half** (6.4.74's `_cfo` re-arm, 6.4.80's
`1 - 2 + 3 == 5`, 6.4.81's fourth `_cfo` occurrence — each one release, each found by *running
the compiler* during unrelated work, each displacing a planned slot), and treat agnos wrapper
adds as the cheap ride-along. That is how 6.4.x actually absorbed them.

**Parity is currently FULL — there is no outstanding wrapper gap** (re-derived 2026-08-07).
agnos is at **1.56.40**; its canonical dispatch
(`grep -oE "num == [0-9]+" kernel/core/syscall.cyr`) is **0–43 + 45–95 + 97**;
`lib/syscalls_x86_64_agnos.cyr` wraps all of those plus `#44` (`sched_yield`, which lives in
agnos's SYSCALL entry stub). The GPU band `#82`–`#95` is contiguous and asserted on both legs
by `scripts/agnos-crossbuild-gate.sh:354-443`, mutation-proven. **`#97 chan_op` was minted at
v6.5.8** (five ops CAPS/MINT/SEND/RECV/CLOSE, verified against the kernel at
`syscall.cyr:7620`, not against the ABI doc) and **`CH_ENDOW = 0x05` added at v6.5.9** — it
landed in agnos 1.56.40 *after* .8 minted the band, so the caps mask advertised an op the peer
had no name for. **`#96` (fork) stays deliberately UNMINTED**: on agnos an unknown `num` falls
through the dispatch chain and the caller reads the fall-through value as data, so a
minted-but-unimplemented constant is strictly worse than an absent one. The gate asserts both
directions. ⚠ The `sys_chan_*` prefix is load-bearing — `chan_send`/`chan_recv`/`chan_close`
are already the in-process MPSC thread channel and last-definition-wins would have silently
replaced them on agnos only.

**And the biggest 6.4.x generator is closed by design.** agnos `planning/gpu.md:979`: *"**No
new syscall number.** D-3 already settled this … `#92 gpu_shader_op` takes an array of
**64-byte** records with the op code inside the record, and the op code IS its bit index in the
`#89 gpu_caps` support word at `+28`."* MD-4 re-minted `#93` on the same descriptor-array
shape. The 1.56.x cuts through **.40** (bilinear, depth, persp-correct, pilot, cold-modeset,
HDMI audio, invalidate hoist) added **op codes, not numbers** — HDMI audio routes through the
existing snd band `#64`–`#69`. **Four windows, not five**, because that door is shut; **four,
not three**, because the arity-divergence class is live, the kriya symlink un-gate is armed,
and Slots 3/5/6 are a long mechanical stretch during which a consumer filing would otherwise
have nowhere to land.

⚠ **The GPU door being shut did NOT stop new numbers — it moved them.** Two arrived in
2026-08: **`#97 chan_op`** (v6.5.8) and the `CH_ENDOW` op + 4-arg `sys_spawn_path_env`
(v6.5.9), from agnos's **channel/capability** band, not its GPU band. Neither cost more than a
ride-along, so the *unit-cost* half of the model held exactly — but the prediction that the
number generator was closed did not. Read "the biggest 6.4.x generator is closed" as
retrospective, not as a forecast (this paragraph was written before .8/.9; corrected
2026-08-07).

**⚠ The baseline above measures the WRONG generator for what is actually filing now
(recorded 2026-08-03, at the W1 widening).** Every figure in it is counted from releases
touching `lib/syscalls_x86_64_agnos.cyr` — i.e. **agnos-kernel-facing ABI work** — and on
that basis it correctly concludes the biggest 6.4.x generator is closed by design. That
conclusion still holds *for syscall numbers*. It does not describe the class currently
producing filings.

**The agnosai PORT is a second, independent generator, and it files a different shape.**
Not syscall numbers: **missing stdlib primitives and codegen gaps** hit while porting real
Rust code — `vec_sort_by` (6.5.4: no fn in any of the 99 `lib/` modules took a comparator),
`sys_exit_group` (6.5.6: `sys_exit` is exit(2)), `async_await_readable_ms` (6.5.6: no
timeout variant existed). Three releases of W1 in the window's first week, none of them
agnos-ABI, none of them predicted by the measured baseline.

**Sizing rule for this class**: it is bounded by *how much of the port remains*, not by
agnos's syscall surface — and it arrives in bursts, because a port hits a whole subsystem's
worth of gaps at once (the 6.5.6 pair were filed the same afternoon, from the same bite).
Each fix is small and self-contained; the risk is **stalling the port**, not blast radius.
That is why W1 was widened to 13 rather than the remainder being pushed to W2: deferring
these behind a two-release compiler arc blocks the consumer the window exists to serve.
Re-check this paragraph at the next window — if the port has moved past its moat, W3/W4 can
shrink back toward the agnos-ABI baseline.

### ▣ W1 — v6.5.4 → .16 (13 patches) · pre-IR-arc · drains the known queue · **7 spent, 6 left**

Known drain queue (~3 releases' worth; the rest is reserve). When this window opened, six of
the then-16 open issues had been filed on 2026-07-28/29 and five were self-contained stdlib
fixes with supplied patches — per *an audit's output is fixes, not a backlog*, that class is
pack-into-a-release material, not roadmap rows, and `.7`–`.10` are what that looks like in
practice. **Only two of that burst are still open at 6.5.10** (`…sock-send-result-allocates`,
pinned to Slot 9, and `…fmt-int-buf-i64-min`, which shipped at `.8` and is awaiting archive).

> **WIDENED 5 → 13 patches (`.4` → `.16`) — maintainer decision, 2026-08-03.** Everything
> downstream shifts **+8** (the IR substrate arc moves `.9–.10` → `.17–.18`, and so on
> through the closeout band at `.40+`).
>
> **The reason is the agnosai port, and it is a deliberate sequencing choice, not scope
> creep.** These patch fixes are the early moat the port is currently moving through: each
> one unblocks something agnosai hit while porting, and the alternative to fixing them now
> is the port stalling out on them. A reactive window exists precisely to absorb
> consumer-filed repairs — narrowing it while the consumer is actively filing would push
> the work behind a two-release compiler arc and stall the thing the window is protecting.
> So W1 keeps ~4 patches of genuine reserve rather than being sized to the *known* queue
> alone; the queue is expected to grow while the port runs.
>
> **Spent: 7 of 13 — `.4` through `.10`. Six left: `.11`–`.16`.** (Updated 2026-08-07 against
> the CHANGELOG, not against this block's own prior count.)
>
> | patch | what it took | queue item |
> |:-:|---|:-:|
> | `.4` | `vec_sort_by` / `vec_select_nth`, the agnosai filing | **item 4** ✅ |
> | `.5` | displaced by the cyrius-doom IR=3 miscompile — a live consumer bug, not a queue item | — |
> | `.6` | agnosai `sys_exit_group` + sandhi `async_await_readable_ms`, both filed *and* shipped 2026-08-03, plus three defects found while fixing them | — (reserve) |
> | `.7` | the syscall-wrapper pass, all ten sub-items + the `vr01_` tcyr; `#@incdir`; `alloc_reset` | **item 1** ✅ |
> | `.8` | `i64::MIN` (12 sites), `distlib --all`/`--check`, the cross-OS coverage print, `thread_join`, `thread_create_detached`, the coverage + fail-open tool family | **items 2, 6** ✅ · **item 7 half** |
> | `.9` | agnos `CH_ENDOW` + `sys_spawn_path_env`; the three-state mutex; the growable arena + exhaustion policy | **item 3** ✅ |
> | `.10` | `distlib`'s `.deps` sidecar; `alloc_via` call plumbing | — (reserve) |
>
> **Still owed, with `.11`–`.16` to run them in: item 5 (`dir_list`, both halves), item 7's
> second half (full corpus on pi), item 8 (`CYRIUS_PKG_VERSION`), item 9
> (`folds_agnos_parity.sh` PREAMBLE).** Plus Slot 1's unshipped (b)–(e), which have no other
> home — see the slot table.
>
> ⚠ **The window is spending faster than its queue drains.** Three of the seven patches
> (`.5`, `.6`, `.10`) went to work that was *not* in the queue at all, which is what a
> reactive window is for — but it means "6 patches left" and "4 items left" are not the same
> arithmetic. Re-check the sizing before assuming `.16` still lands the IR arc at `.17`.
>
> ~~**Sequencing note — item 6 (`distlib --all`/`--check`) should go EARLY**~~ — **satisfied
> at `.8`**, and correctly: it landed before this window's sakshi 2.4.8 / bayan 1.4.1
> re-vendors. `.10` then found that the `.deps` sidecar the same command emits was itself
> under-reporting.
>
> ~~**Sharpest item in the queue — item 1(vi): `sys_chdir` … defined NOWHERE**~~ — **FIXED at
> v6.5.7**, defined on all three peer families.

> ⛔ **STEPS (i) AND (ii) ARE DISPROVEN — do NOT execute them (measured 2026-08-05, v6.5.7).**
> The premise is that repointing `lib/yantra.cyr:453` leaves the aarch64 `54 → 208` remap
> with "no consumer", freeing native `54` for `SYS_FCHOWNAT`. It does not, and the gap is not
> close:
> - `lib/net.cyr:15` has an unconditional `var NSYS_SETSOCKOPT = 54;` with **9** call sites
>   (`:222 :252 :277 :435 :450 :463 :476 :488 :501`) — `sock_reuse`, both timeouts,
>   `SO_REUSEPORT` and all four multicast verbs.
> - **51 repos** across `~/Repos` carry a raw `syscall(54, …)` emitter, and it is not all
>   vendored yantra: `argonaut/src/notify.cyr:122` writes it in its **own source**
>   (`setsockopt(fd, SOL_SOCKET, SO_PASSCRED, …)`).
>
> So the remap is **load-bearing ecosystem infrastructure**, not dead weight, and deleting it
> would silently break sockets on native aarch64-Linux for consumer code this repo does not
> control — with the cross-OS leg running only 36 of 260 `.tcyr` (re-derived 2026-08-07), so
> it very likely would not be caught. It is ALSO the mechanism that lets one source number work on both aarch64-Linux
> and macOS-arm64 (the macho leg maps both `54 → 105` at `emit.cyr:719` and `208 → 105` at
> `:742`).
>
> **A second candidate was tried and is also wrong**: `SYS_FCHOWNAT = 260` (the x86 number,
> the usual house pattern) collides with `SYS_WAIT4 = 260` at
> `lib/syscalls_aarch64_linux.cyr:102` — a `260 → 54` entry would rewrite every `wait4` into
> `fchownat` and break process reaping (`syscalls_linux_common.cyr:190`, `async.cyr:883/:888`).
>
> ⭐ **RESOLVED v6.5.7 — the private alias band.** Both candidate numbers are owned, so the
> fix is to stop borrowing real numbers: source numbers **≥1000 are cyrius-private aliases**
> that no OS will ever mint (Linux is in the 400s, growing ~5/yr; Darwin routes separately),
> renumbered to the true target by ESYSXLAT. The convention is **1000 + the native aarch64
> number**, so `SYS_FCHOWNAT = 1054` reads as its own documentation. An alias costs three
> lockstep edits — the aarch64-Linux arm (`1054 → 54`), the `_TARGET_MACHO == 2` arm
> (`1054 → 468`, because macOS-arm64 resolves this same peer), and a `_macho_arm_routes` row;
> any one of them missing is a stale-`x16` garbage call. ⚠ The Linux arm must sit **last** in
> its chain: it produces `x8=54` and the setsockopt entry compares against `54`, so placed
> earlier every `fchownat` would be re-caught and issued as `setsockopt` — the ordering trap
> already documented on flock/poll and epoll_wait. The v6.4.64 precedent at
> `lib/syscalls_aarch64_linux.cyr:174-178` ("native numbers pass through untranslated; the
> macho backend dual-maps") is the right shape and simply had no free number here.

1. ✅ **Syscall-wrapper pass — SHIPPED v6.5.7, complete end-to-end.** All ten sub-items, plus
   the `vr01_`-named tcyr the item asked for. That last line was the load-bearing one: the
   cross-OS leg runs only the `vr01_` glob, so without it these wrappers would have been
   compiled on four hosts and RUN on none. It turned the gate red on ecb and again on ach and
   surfaced **seven** host-invisible defects — two of them (`xrmdir` on macOS-arm64, the
   macOS-x86 `Stat` offsets) pre-existing rot unrelated to this item's own work. Sub-item (x)
   needed nothing: yukti's `_yk_mkdir` bridge already landed upstream at 2.3.1 and is vendored
   at 2.3.2. See CHANGELOG [6.5.7] "found by ports".
   <details><summary>Original plan (kept for the reasoning)</summary>

1. **Syscall-wrapper pass**, in this fixed internal order:
   ~~(i) repoint `lib/yantra.cyr:453`'s bare-literal `syscall(54, fd, 6, 1, one, 4)` at
   `SYS_SETSOCKOPT` so the aarch64 `54 → 208` remap at `src/backend/aarch64/emit.cyr:840` has
   no consumer; (ii) **only then** claim aarch64-native `54` for `SYS_FCHOWNAT`;~~
   **(i)/(ii) DISPROVEN — see the banner above.** Repointing `lib/yantra.cyr:453` upstream is
   still worth doing as bare-literal hygiene, but it unlocks nothing and is not a prerequisite.
   (iii) `fchownat` as the single wrapped primitive (x86 260 / aarch64 alias 1054 → 54; `AT_FDCWD` +
   `AT_SYMLINK_NOFOLLOW` gives `lchown` semantics) rather than the legacy trio — two of the
   agnos `92`–`95` band *terminate the caller* on ARM; (iv) explicit `-ENOSYS` agnos stubs,
   keeping the **FILE-level** `#ifdef` in `lib/syscalls.cyr` intact (do not weaken it to an
   in-fn check); (v) read the Darwin numbers off ecb/ach and add **both** the `EMACHO_SYSXLAT`
   `_msx()` entry and the aarch64 `_TARGET_MACHO == 2` cmp; (vi) `sys_chdir`;
   (vii) `xmkdir` + the `xrmdir`-shaped agnos bridge; (viii) `xmkdir_p` with Rust's
   `create_dir_all` ordering (full path first, walk parents only on `ENOENT` — the filing
   measured 43 µs → 6.0 µs); (ix) `xsymlink`/`xreadlink`/`xlink`; (x) fix `lib/yukti.cyr:1801`
   and `:5270` **upstream** in `~/Repos/yukti`, then re-vendor. One `.tcyr` in `tests/tcyr/crossos/` (this said `vr01_`-named; see the standing correction) so
   the cross-OS leg actually executes it on pi.
   </details>

2. ✅ **`i64::MIN` formatter class — SHIPPED v6.5.8, and it was 12 sites, not the 7 this item
   named.** The `n > 0` → `n != 0` loop-condition change was the load-bearing part, as pinned.
   ⛔ **THE COUNT IN THIS ITEM WAS WRONG AND THE MISSING FIVE WERE THE INTERESTING ONES** —
   **two of them are inside the compiler itself** (`PRNUM`, `_emit_decimal`), which this item
   never considered because it enumerated `lib/` only, and three were shipped demos.
   `str_from_int(i64::MIN)` was the one-character string `-`, and bayan then serialised
   `{"n":-}` — not JSON, with no error raised at any layer. sakshi was fixed upstream at
   **2.4.8** and re-vendored, per *never patch the fold*.
   ⭐ The through-line worth keeping: `fmt_hex`, sitting **directly below `fmt_int`**, had
   already been fixed for this exact `> 0` vs `!= 0` reason at **v6.4.69** — and its decimal
   siblings were never brought along. Grep the shape, not the function.
   <details><summary>Original site list (kept for the reasoning)</summary>

   `lib/fmt.cyr:10` (`fmt_int`), `:25` (`fmt_int_fd`), `:41` (`efmt_int`), `:103`
   (`fmt_int_buf`), `lib/string.cyr:98` (`print_num`), `lib/log.cyr:137`, `lib/sakshi.cyr:415`
   (`_sk_fmt_int`).
   </details>
3. ✅ **Three-state mutex — SHIPPED v6.5.9.** 0 = free / 1 = held / 2 = held-with-waiters;
   `mutex_unlock` no longer syscalls on every release. **392 ns → 48 ns** uncontended.
   ⛔ **THIS ITEM'S STATED PREREQUISITE WAS WRONG AND COST IT A PIN.** It was recorded here
   as blocked on `atomic_swap` plus a value-returning CAS, "single instructions on both
   arches" — real work with real-pi asm-review risk. Neither is needed: a SUCCESSFUL
   boolean `atomic_cas(m, 1, 0)` already proves the pre-value was exactly 1, which is the
   information `atomic_swap` would have returned. The item was cheaper than pinned, and the
   prerequisite is what kept it waiting. Adding `atomic_swap` remains worth doing on its own
   merits (it saves one CAS here) but it gates nothing.
   <details><summary>Original plan (kept for the reasoning)</summary>

3. **Three-state mutex.** Prerequisite first: `lib/atomic.cyr` exposes only
   `atomic_load`/`atomic_store`/`atomic_cas` (returns 0/1 via `sete`, discarding the observed
   value)/`atomic_fetch_add`/`atomic_fence` — so add `atomic_swap` and a **value-returning**
   CAS (single instructions on both arches: `xchg` / `lock cmpxchg` already computes the old
   value into rax and simply does not return it; `swpal`/`casal` on aarch64). Then the
   canonical Drepper "Mutex, Take 3" — both flagged subtleties (re-acquire **as 2**, needing
   the pre-store value) are genuinely load-bearing. **Verify the new aarch64 asm on real pi,
   not qemu.** Blast radius is measured, not inferred: `lib/thread.cyr` calls `mutex_lock` at
   `:335`/`:411`/`:434`/`:459`/`:488`, so every `chan_send`/`chan_recv`/`chan_try_*` pays it.
   </details>

4. ✅ **`vec_sort_by` + `vec_select_nth` — SHIPPED v6.5.4**, the stdlib's first ordering
   primitive; no fn in any of the 99 `lib/` modules had taken a comparator before it. Both hard
   constraints from the filing held: named **`vec_sort_by`, NOT bare `vec_sort`** —
   `itihas/src/util.cyr:57` already defines `vec_sort(v, cmp)` in the flat namespace and
   last-definition-wins would have broken it; and the **hybrid** (merge/heap with an insertion
   cutoff ~16) so the O(n) nearly-sorted case consumers get from hand-rolled insertion sorts is
   not lost. `vec_select_nth` = Hoare quickselect, median-of-3. `drishti/src/av1_mv.cyr:358`
   stays excluded from any migration — AV1-spec-prescribed sort.
5. **`dir_list` — both halves in one release.** Cheap half: a file-scope 4 KB `getdents`
   scratch (`dir_list` is already non-re-entrant, holding one fd and one buffer — the v6.4.61
   lazy `Err(EAGAIN)` singleton precedent) + a shared `basep`, which takes agora's 1-entry case
   from ~5.3 KB to under 1 KB. Hard half: `dir_list_into` with caller-owned scratch + names +
   offsets, existing `dir_list` kept as a thin wrapper, and the same treatment threaded through
   `dir_list_full`/`dir_walk`/`find_files`/`_with_prunes` (`dir_walk` recurses, so it
   multiplies). Taking only the cheap half would be the sliced-fix antipattern.
6. ✅ **`distlib --all` + `--check` — SHIPPED v6.5.8**, and it did land before this window's
   sakshi 2.4.8 / bayan 1.4.1 re-vendors, as the sequencing note asked. `--all` enumerates
   `[lib.<name>]` from the manifest so the list cannot drift; `--check` compares **bytes**, not
   version strings — the content requirement this item stated, and exactly what let sankoch
   2.7.6's nine sub-bundles look fresh while carrying the buggy encoder. Dogfooded on all 9
   bayan bundles in one command.
   ⛔ **The defect was worse than filed: both flags were previously swallowed by the arg loop
   and silently ran the base-bundle-only path, exiting 0** — so the command the issue told
   people to reach for already "succeeded" while doing the wrong thing.
   ⏳ **Residual owed elsewhere:** fixing the sankoch zip/zipall and sigil argon2 CI lists in
   *those* repos was part of this item and is not recorded as done in any 6.5.x CHANGELOG
   entry — re-check it in a remaining W1 patch.
7. ⚠ **Release-gate coverage — HALF SHIPPED v6.5.8. This item said "both halves in one bite"
   and got one.**
   ✅ Shipped: `cross-os-selfhost.sh:326-334` prints the coverage on every run, derived from
   the globs so it cannot go stale (`corpus: N of M tcyr selected by glob 'vr01_*' — M−N NOT
   run on $HOST`), plus one SSH connection per POSIX host instead of one per test (~1.8 s of
   handshake per test on cass, 0.9 s on pi). `CYRIUS_CROSS_OS_FULL=1` runs the whole corpus.
   ⛔ **Not shipped: the FULL corpus on pi.** `scripts/release-gate.sh:110` still passes the
   `vr01_` glob for all four hosts, so at 6.5.10 that is 36 of 260 — **224 tcyr unrun on every
   gated host**. `--full` was left opt-in deliberately, because ecb's first full-corpus run
   scored **235 pass / 23 fail** and wedging every release behind that is a separate arc
   (`2026-08-05-cross-os-full-corpus-23-failures-on-ecb`). That is a defensible call for
   *ecb* — it is **not** an argument against turning it on for **pi**, which is what this item
   actually asked for and which is where per-arch syscall numbering bites (v6.4.64
   `fchmod`/`getpeername`). ⭐ v6.5.7 proved the point twice over: one new `vr01_` file found
   seven host-invisible defects. Do not delete the filter; do finish the second half.
8. **Fold-in:** `CYRIUS_PKG_VERSION` — option 1 of the proposal only: surface
   `[package].version` (which already resolves `${file:VERSION}`) as one injected
   source-visible cstring. No new manifest surface, explicitly **not** const-eval. Keep it
   distinct from `proposals/2026-07-05-const-eval-comptime` (v6.6.x).
9. **Fold-in:** extend `tests/gates/platform/folds_agnos_parity.sh`'s PREAMBLE until the SKIP list is empty —
   it currently reports 11 of 12 (`SKIP: niyama — undefined variable 'NFD'`), so one fold's
   agnos exposure is still unmeasured.

### ▣ W2 — v6.5.19 → .21 (3 patches) · at the substrate/regalloc seam

Deliberately the low end: this is **reserve, not a known queue** — W1 drains the queue, and the
one named forward agnos candidate (`lstat`, the last half of the old `readlink` pair, agnos:
*"slot when a consumer — kriya `ln -s`, or ark install layouts — demands it"*) shares its
trigger with W1's symlink work, so it may arrive here or not at all. Its purpose is to give a
consumer filing arriving during the long substrate stretch a landing slot ~3 releases out
instead of ~20. Named fold-ins if nothing arrives:

- **Bare-metal forbidden-module check** — a deny-list or `#host_only`/`#kernel_ok` annotation
  checked in the include resolver under `CYRIUS_KERNEL`, plus a **negative** fixture (a kernel
  program pulling `lib/fs.cyr` must error); `tests/fixtures/freestanding_tls/kernel_link.cyr`
  is the positive case. Directly relevant to agnos, the repo 6.4.x was held open for.
- **Two cyrlint gates, one bite** — the bare-local-array slot-write lint and the syscall-write
  byte-length gate. Both are byte-length-vs-declared-size static checks. The argument for
  acting rather than watching is the trajectory: `grep -rn "syscall(SYS_WRITE" --include='*.cyr' .`
  went **543** (filed) → 593 (v6.4.82) → **609** (re-derived 2026-08-07 at 6.5.10, flat since
  6.5.2), i.e. the unguarded surface grows across a minor while the gate waits for consumer
  pressure that never comes for a lint. ~21 intentional bare-local-array sites in-tree.
- **Visibility adoption**, a file or two at a time where it pays.

### ▣ W3 — v6.5.26 → .30 (5 patches) · post-residency · the burst-risk window

Sized at the top of the range because this is where the historical burst lands and where cyrius
is the **named blocker** on an agnos item. The next new-number pressure is agnos 1.57.x/1.6x —
"USB device classes and plug-and-play" (filed 2026-07-28, *"the gap is wider than hot-add"*) and
the ark M4/M5/M6 band (atomic system-update / boot-slot primitive, nested/recursive exec,
argv/env length-caps raise). Both of the most syscall-shaped items say a **design call is owed
first**, so this is sized as reserve against a possibility, not against a known plan (see open
question 6).

Named candidate: the **`sock_accept`#57 VFS-fd bridge**. agnos: *"Landed at 1.49.4, then
partially reverted at 1.53.9: `sock_accept`#57 returns the raw `conn_id` again, BECAUSE the
cyrius `net.cyr` treats the return value as a `conn_id`. Accepted sockets are therefore not
epoll-able."* That is the `sys_reboot`#13 pattern shipped at 6.4.68 — an **existing number
changing meaning**, which is the silent class: a new number fails loudly (undefined fn) or
hard-errors on arity since 6.5.1, but a widen is invisible on both sides. `net.cyr` churn is
also easier once the vector-residency work is stable, hence post-Slot-6 rather than mid.

### ▣ W4 — v6.5.35 → .38 (4 patches) · feeding the closeout

A window **in front of** the closeout so the closeout's backlog re-triage and doc sync reflect a
drained queue rather than discovering one and displacing releases — which is exactly what
happened in 6.4.x, where the closeout audit kept finding live bugs and `.80`, `.81`, `.83` and
`.84` were all displaced by it. Deliberately **not** a closeout slot: the closeout's judgment
passes are their own work, and a minor-close slot still has to carry real code deliverables.

### Two standing riders every window carries

1. **Mutation-prove the gate, in the same release as the wrapper.** v6.4.70 shipped
   *"the agnos GPU-band gate was a PLACEBO"* — `agnos-crossbuild-gate.sh`'s emit-inspect used
   `grep 'mov eax,0x52'`-style checks, and mutation proved `#84 → 99` still reported PASS. The
   band had been "gated" since `.63` with no real coverage. "Gated" without a mutation proof
   means ungated.
2. **Diff `agnos/docs/development/agnos-userland-abi.md` against
   `lib/syscalls_x86_64_agnos.cyr` once per window.** That doc is the designated frozen
   normative contract both sides code against, and it is the only cheap place to catch an ABI
   **widen** of an existing number — the failure class no compile-time check can see. Note it
   currently has **17 missing rows** (`#64`–`#69` snd and `#71`–`#81` shm/blk/readdir bands are
   dispatched by the kernel and wrapped by cyrius but have no row), and
   `agnos/docs/development/syscall-additions.md`'s header is ~35 syscalls behind
   ("through v1.45.x — surface is now 0–60"). **Both are agnos-repo docs — surface the gap to
   the agnos agent; cyrius does not edit them.**

---

## Standing notes — traps this minor must not re-learn

- **The `PARSE_RETURN` tail path has now skipped a `PARSE_FNCALL` transformation FOUR times**:
  v6.3.36 (plain-struct params), v6.4.53 (value-form SIMD params), v6.5.1 (overload dispatch),
  v6.5.2 (the cstring-literal check). Each was fixed with the same narrow divert. That is the
  `_cfo` escalation shape — *"declared fixed, fourth occurrence in a path nobody enumerated"*.
  **Any new `PARSE_FNCALL`-resident transformation must be grepped against the tail path before
  it ships** — grep the SHAPE, not the operator.
- **An all-identical codegen differential is not evidence a fix is inert — it is evidence of a
  corpus blind spot.** Three consecutive releases: 6.5.0 was 0/253, 6.5.1's arity fix 0/253,
  6.5.2 0/253 — each a real wrong-answer-or-crash fix. Same finding as v6.4.80's 251/251. When
  a fix measures 0 diffs, add the shape to the corpus in the same release. (The corpus is
  **260** at 6.5.10; quote the live count, not these historical denominators.) The 6.5.8
  `i64::MIN` sweep is the same lesson from the other side: a **5,500-assertion suite** missed
  arena exhaustion because allocation tests are small-fixture by nature and nothing in them
  probed the ceiling.
- **A green CI checkmark is not verification.** The macOS compiler self-host rotted for ~9
  minors behind a job named "Mach-O ARM64 Native ✓" that only ran hello-world. `ach` became a
  first-class gate host at v6.4.59 after the Intel-Mac toolchain rotted ungated for ~2.5
  minors. Run the compiler on the hardware.
- **7 of the 16 open issue files still carry a "re-verified against live code at the v6.4.82
  closeout" header** (re-counted 2026-08-07; the other 9 were filed after that closeout and
  carry no re-verification stamp at all, which is the same problem wearing different clothes).
  v6.4.82 is three minors of releases stale, and it is exactly how the xmkdir filing came to
  re-assert `xrmdir` as missing **two days after 6.5.2 shipped it**. The header pattern is
  load-bearing — it is what makes a file trustworthy at a glance — so the re-verification stamp
  must move with each sweep or it becomes the rot it was designed to prevent. **Four of the 16
  are outright shipped-but-unarchived** — see the ⚠ note under *Where we are*.
- **A "found by ports" test is worth more than the gate that says the code compiles.**
  v6.5.7 shipped `tests/gates/platform/syscall_wrapper_pass.sh`, which proves the new wrappers *compile* on
  five targets — most of the risk, and none of the bugs. The one `.tcyr` that actually RAN
  them on hardware found **seven** defects, two of them pre-existing rot (`xrmdir` broken on
  macOS-arm64 since the day it shipped; a macOS-x86 `Stat` enum mixing two structs). Five of
  the seven were **half-fixes that stopped at the first symptom**. Whenever a slot adds a
  platform-facing verb, the `tests/tcyr/crossos/` file is the deliverable, not the nice-to-have (this said `vr01_`; see the standing correction).
- **A gate fixture in the wrong order is a vacuous gate.** Twice in v6.5.10 a mutation axis
  passed against deliberately-broken code because the fixture's decoy sat *after* the real key
  and the scan stops at its first match; v6.5.8 hit the same shape assuming `dir_walk` ordering.
  Mutation-prove the gate *and* check that the mutation is reachable.
- **When a rule in `CLAUDE.md` tells you to work around codegen, the rule is the bug report.**
  The retired "≤6 args" rule was a Win64 codegen P0 in disguise for about a year, and it got
  cited to file against *sigil*. This is the language repo: when the compiler cannot compile
  valid cyrius, fix the compiler. Premise-check **rules**, not just pins.

### UNVETTED filings — ✅ all three now CLOSED (kept for the lesson)

Three issues were authored by subagents and never reviewed by the maintainer. **All three
have since shipped** — xmkdir at **v6.5.7**, the `i64::MIN` formatter class at **v6.5.8**, the
mutex wake at **v6.5.9** — so the `[UNVETTED]` marks are retired from the slot table above.
The section stays because **what the outcomes proved is the durable part**: every one of the
three was *understated or mis-evidenced in the same direction*, and each shipped fix was
bigger than its filing. All three were reproduced by running code or a bench at 6.5.2 and all
three described **real** defects — but their evidence, not their conclusions, was the suspect
half:

- **`2026-07-29-no-portable-xmkdir-in-io-cyr`** — two false claims. It says the `x*` set has no
  `xrmdir` (it does — `lib/io.cyr:134`, shipped 6.5.2, with a CHANGELOG heading of its own) and
  that *"`lib/kavach.cyr` calls the unguarded form at eight sites"* — **`lib/kavach.cyr` does
  not exist in this repo**; the live raw callers are `lib/yukti.cyr:1801` and `:5270`, two
  sites, `sys_mkdir(cstr, 493)`. It also never makes its own sharpest argument: **`mkdir` is
  the one member of the family whose ARITY MATCHES** (2 args on every target — `(path, mode)`
  vs agnos's `(path, pathlen)`), which is precisely why 6.5.1's arity escalation is
  structurally blind to it and `folds_agnos_parity.sh` passes without catching it. It is the
  **last remaining member of the arity-identical-but-semantically-divergent class**.
- **`2026-07-29-fmt-int-buf-i64-min`** — no false claims; **understated**. It asks whether other
  formatters share the shape. They do: 7 sites, not 1.
- **`2026-07-29-mutex-unlock-unconditional-futex-wake`** — no false claims; one number not
  reproducible from the attached repro. Its `chan_try_send + chan_try_recv = 1.590 µs` row does
  not come out of the committed `.bcyr` (that harness emits only `nop_loop`/`alloc_16`/
  `atomic_cas_hit`/`mutex_lock_unlock`; measured 1 / 10 / 6 / 382 ns). The `.bcyr` header is
  honest about it; the issue body presents the row in the same measured table. The mechanism is
  independently verified via the `thread.cyr` call sites, so it is understated, not wrong.

**Read this as a signal about how subagent-authored filings fail: the conclusion survives, the
evidence does not.** Re-derive every line reference and count before acting on one.

---

## Potential backlog — 6.x-cycle, unscheduled (NOT parked to 7.x)

Real 6.x-line work without a committed slot; pulled into a release the moment a consumer or
priority surfaces. **These are technical items → they stay in the 6.x cycle, never 7.x.**

- **Embed data files as source strings — an `[embed]` / assets manifest section**
  (`proposals/2026-08-10-embed-data-files-as-source-strings`) — ⛔ **added 2026-08-11 by the
  placement-rule audit, which found it referenced in NONE of `roadmap.md`, `roadmap_6.md`,
  `roadmap-future.md` or `state.md`. It was completely homeless** — the third instance of that
  shape after the cx indirect call and the `net.cyr` arch guards, both caught by the 2026-08-07
  sweep. Ergonomics, not capability: the generated-`.cyr` idiom already works and is fleet-wide
  (`kashi_font_data.cyr` vendored in 6 repos, `shabdakosh/programs/gen_cmudict.cyr`,
  `kavach/src/scanning_data.cyr`, `ghurni/src/presets.cyr`), so nothing is blocked — agnosai
  shipped its generator and pins 6.5.19. **Sequence it after `CYRIUS_PKG_VERSION`** (Slot 1b):
  the proposal names that as its sibling, both are "a build-time value that source cannot
  read", and the smaller one should define the shape. Candidate for the v6.6.x ergonomics list.

- ~~**Tuples — lightweight multi-value returns**~~ — ✅ **SHIPPED v6.5.21**, archived to
  `proposals/archived/2026-08-13-tuple-multi-value-returns`. ⛔ **This entry, as originally
  written here, repeated the proposal's FALSE premise** ("ergonomics, not capability... nothing
  is blocked") and is kept only as the correction. Two-value multi-value return with
  destructuring had shipped at **v3.7.2** — `return (a, b);` + `var q, r = f();` — four majors
  before the filing; the proposal's table tested `return a, b;` and `var (x, y) = f();`, which
  differ only in where the parens go. Our own vidya entry (`language/features.cyml →
  ret2_rethi`) documented the paren-less form under a heading reading "NATIVE MULTI-RETURN",
  so a consumer following CLAUDE.md's search-vidya-first rule got the wrong syntax from the
  authoritative source. What was genuinely missing and shipped at `.21`: **arity 3** (the one
  real capability gap — `_dd_pow10`), a **declared return type** `fn f(): (f64, f64)` making
  arity checkable at a forward call, a **destructure contract** (there was none — `var q, r = 42;`
  compiled, and `dm(17,5) + (k/9) - 11` put the idiv REMAINDER in `r`), and **three silent
  miscompiles** the proposal never knew about: cx returned the first value twice (return-0
  emitter stubs), a `: f64` tuple lost its first value to a stale xmm0 on x86/PE — the exact
  Dekker shape — and f64 type was lost at the binding, which is why the `: f64` RETURN
  annotation had two uses ecosystem-wide, both in our own tests. **The lesson worth keeping:
  a consumer-filed capability table is a report about OUR docs as much as about the language —
  premise-check it against a RUN BINARY, not against the filing.**

- **`lib/net.cyr` AF_UNIX surface** (was §9 of `2026-07-30-net-cyr-x86-only-socket-syscall-numbers`,
  archived v6.5.12) — a yes/no DESIGN call for the maintainer, not a defect: whether `net.cyr`
  grows a Unix-domain socket surface alongside INET. Landed here rather than left in the issue
  queue when the rest of that filing resolved — §3 disarmed at v6.5.7, §4 premise-disproved on
  real pi, and the silent net.cyr ⇄ ESYSXLAT coupling gated at v6.5.11. Nothing blocks on it.

- **DRY the per-target pass-1/pass-2 top-level scanners** — `ls src/main*.cyr` = **7** forks
  (`main`, `main_aarch64`, `main_aarch64_macho`, `main_aarch64_native`, `main_cx`, `main_win`,
  `main_x86_macho`); no shared pass-1 dispatch helper. This is a recurring-bug class, not
  cosmetics: `#io` v5.8.20, `#pure` v6.2.2, and the v6.4.26 trap where a new `E*_PE` reroute
  needed return-0 stubs in aarch64 + cx and only `cass`'s `cycc_cx` caught the miss.
  Logic-preserving ⇒ gate is byte-identical self-host on all four hosts + seed-derive.
  Premise-check the fork count at slot entry.
- **DWARF debug-info emission** — backend/codegen work; it emits debug sections into the object
  file. Slot it when a real debugger story is needed. Distinct from the DX diagnostics arc,
  which was only the error-reporting layer.
- ~~**cx has no indirect call**~~ — **✅ SHIPPED v6.5.13, struck 2026-08-11.** `.cyx` opcode
  **105 (`callind`), PERMANENT**: `fn ECALLIND` is real at `src/backend/cx/emit.cyr:488`, the
  matching cxvm arm is at `programs/cxvm.cyr:272`, and the issue is archived `✅ RESOLVED
  v6.5.13` with `tests/gates/codegen/cx_indirect_call.sh` (8 assertions) green. Verified
  against **live code**, not the file's own claim. ⚠ This bullet was added by the 2026-08-07
  sweep *because the item "had no roadmap home at all"* — and it had in fact shipped six
  releases earlier. **The reason both this list and `roadmap-future.md` went on carrying it as
  open is that `## [6.5.13]` has an EMPTY CHANGELOG body**, so there was no canonical line to
  reconcile against. Backfill that entry.
- **`lib/net.cyr` hardcodes seven x86-only socket syscall numbers with zero arch guards**
  (`2026-07-30-net-cyr-x86-only-socket-syscall-numbers` — **ARCHIVED** `✅ RESOLVED v6.5.7 + v6.5.11`, closed deliberately WITHOUT its §4; filed by sandhi 1.9.7 via bote 3.2.1). ⛔ **Status corrected 2026-08-11: this file said "archived v6.5.12" 24 lines above and "open" here — a literal self-contradiction about one issue.** The unshipped §4 work below is real and correctly preserved in this backlog; what was wrong is calling the issue open, which sends a reader to the open queue to find nothing. Re-verified on the issue itself at 6.5.10:
  `lib/net.cyr:10-16` still carries the bare x86 numbers, `grep -c CYRIUS_ARCH lib/net.cyr` →
  **0**, and the nine `ESYSXLAT` x86-compat socket rows are live at
  `src/backend/aarch64/emit.cyr:865-873`. The §3 collision it worried about was **disarmed at
  v6.5.7 by a different mechanism** (the ≥1000 private-alias band, not the per-arch peer
  wrappers §4 proposed), so the sharp edge is gone but the §4 work is unshipped. Note the
  direct tension with the W1 "steps (i)/(ii) disproven" banner above: that remap is
  **load-bearing for 51 ecosystem repos**, so this is a migration, not a deletion.
- **Incremental compilation** — compiler work. Unpin condition: reconsider when cycc self-host
  crosses ~2 s. It is **648 / 652 ms at 6.5.10** (638 ms at 6.5.2) after 100+ releases, so the
  whole-program model is nowhere near the threshold. ⚠ Read that trend with care: 6.5.7 ran
  the SAME binary three times for **649 / 670 / 701 ms**, a 52 ms spread — **wider than any
  release-over-release delta this minor**, so a single number from this series carries no
  signal. The reporting obligation is live: **every 6.5.x release's mandatory bench run IS the
  report.**
- **Bare `var a[N]` byte-vs-slot convention** — a user design decision, not an arc. The typed
  spelling `var a: T[N]` shipped v6.2.1 and resolved the common case; what stays undecided is
  whether to lint the address-taken bare-local per-slot idiom or audit stdlib/consumers.
- **Reclaim the FREED compiler-state scalar holes** (fill-as-you-go, not a slot) — live count is
  **18** FREED regions in `src/main.cyr` at 6.5.10 (`grep -n FREED src/main.cyr`), roughly twice
  what roadmap-future.md enumerates. Policy: the next new compiler-state scalar goes into a hole
  rather than growing the band. Cite the live count and the heap map; do not maintain an
  enumerated list that goes stale every minor. (This line read "19 at 6.5.2" until 2026-08-07 —
  re-derive it, don't carry it.)
- **aarch64 `EMIT_F32V8_*` unreachable stubs** (`src/backend/aarch64/emit.cyr:2882-2884` (re-derived 2026-08-11; long cited as `:2691-2693`)) — the
  verb works via 2×128 NEON and there is no correctness gap, but three never-reached functions
  are what the closeout dead-code audit exists to find. Decide once: delete them, or leave one
  comment saying why they exist. Recorded here so the next closeout does not re-litigate it.
- **`ir_dce`/`ir_dead_store` uncapped wrappers and `CLASSIFY_CF`/`CF_TARGET`** — decide
  wire-or-delete inside Slot 3's opening bite; leaving a third option open is how they survived
  two closeouts.
- **`tantu` runtime extraction** — the async runtime lib → its own repo. Repo name reserved; a
  future-**minor** deliverable, still 6.x. **NOT sequenced, and not "next".**
- **Auto-vectorization of scalar SOA loops** — item 4 of the SIMD filing's own fix list, which
  that file already calls "longer term". Kept out of Slot 6 deliberately: folding it in would
  inflate a bounded residency slot into an open-ended arc.

## 7.x — public-release ONLY

**Language book** (reference/guide finalization) + **legal** (licensing / public-release prep).
**No codegen, runtime, or platform work ever lives here — if it compiles code, it is 6.x.**

The one genuine 7.x technical-adjacent item is **LEGAL-01**: cyrius is GPL-3.0-only and the
stdlib — including folded sigil, whose `sigil.cyr:533` elects the GPLv2-only leg of dual
BSD/GPLv2 code, and GPLv2-only is GPL-3-incompatible — is source-included into every consumer
binary at build time. That needs legal review plus an RLE-style linking-exception decision. It
compiles nothing and emits nothing; licensing sign-off is exactly what 7.x is for. The other
7.x item is `docs/stdlib-reference.md` authoring (currently "roughly 65 of 99" modules). Note
that "an installer aimed at strangers" is **not** a 7.x deliverable — `install.sh` exists and
ships today; that is 6.x tooling.

---

## Open questions — owed to the maintainer

Six decisions this document deliberately does **not** make. Rows above reference these by
number. Nothing here blocks starting Slot 1; items 1 and 5 are owed by Slot 3 entry.

1. **The self_compile budget — ✅ ANSWERED (user, 2026-07-29): the later performance track
   owns it.** Not a decision owed at Slot 3 entry after all — the budget gets set as part of
   that track rather than pinned up front, and **open question 5 below is to be reviewed
   together with it**, the two being the same subject. The material below stays as the input
   that track should start from.

   *Original framing:* half of the committed acceptance anchor is unstated.
   roadmap_6.md's anchor has two clauses: the svara formant bench closing to single-digit-× of
   the Rust baseline, **and** *"self_compile stays inside a stated budget"*. The svara figure is
   carried above; the budget is not, and the whole point of a *stated* budget is that it is
   stated before the arcs land rather than reconstructed after. Baseline **re-measured
   2026-08-07: 648 / 652 ms · 1,141,792 B at 6.5.10** (it was 638 ms · 1,129,288 B at 6.5.2 —
   **+12,504 B across eight releases**, all triaged growth tax). A defensible pair is
   *≤ 700 ms and ≤ 1.20 MB at minor close* — but the number is the maintainer's, not mine, and
   note that 6.5.10 is already **1.09 MB**, i.e. ~10 % of headroom under that candidate cap
   with the three biggest codegen arcs (Slots 3/5/6) still to land.
   **Note the live counter-pressure:** an IR=3-built cycc is currently **+5.02 % larger**
   (1,199,136 B, re-measured 2026-08-07), so if IR=3 ever becomes the default path the size
   half of any budget is already under strain — and the overhead has grown in both absolute
   and relative terms since 6.5.2 (+53,248 B / +4.7 % then).

2. **Bare-metal deliverable #4 — the forbidden-module check.** Never built; its issue was
   bulk-renamed into `issues/archived/` on 2026-07-10 (`79bae42f`, an 8-file rename) with **no
   resolution banner**, i.e. archived unfixed, while roadmap_6.md still lists it as a
   deliverable *and* an arc acceptance criterion. Either implement it in W2, or strike it from
   roadmap_6.md's acceptance list and say why. Leaving a never-built item as a shipped-arc
   acceptance criterion is the rot pattern.

3. **Per-item `private` — the promised syntax parses and does something much broader.**
   `_TL_VIS` (`src/frontend/parse.cyr:222-234`) handles token 153 by calling
   `_PRIV_MARK(FM_FILEID(...))` — a **FILE-level** flip — with an in-source comment recording
   that a per-item running flag was deliberately rejected because it would leak into later
   includes. So `private fn h(): i64 { … }` compiles with **no diagnostic** and privatises the
   *entire file*, `main` included. Three options: implement the per-item bit; make the per-item
   form a hard error pointing at the file-level declaration; or keep it and document the
   widening. Silently mis-parsing is the one outcome to rule out.

4. **macOS concurrency ordering (Slot 11).** Real platform work with a genuinely broken verb on
   a gate host, so it cannot be dropped — but it is the only pinned row with **no consumer
   waiting**, it mirrors an already-shipped split (`thread_win`), and the VR-01 guards mean it
   cannot rot silently. Keep it last, or pull it forward if a consumer appears?

5. **v6.5.x committed item 5 — the self-compile growth-tax audit — ✅ ANSWERED (user,
   2026-07-29): likely dropped, but re-review it WITH open question 1's performance track,
   since the two are related.** So it is explicitly *not* silently dropped — it is parked
   against that track's opening review, which decides whether it still earns a bite. Whoever
   opens the perf track: read this row and question 1 together, and record the outcome here
   either way.

   *Original framing:* it has no slot.
   roadmap_6.md's *"v6.5.x — ACTIVE MINOR"* section (`roadmap_6.md:115-118` at 2026-08-07 —
   the old `:1323-1369` reference here was dangling, that file is **321** lines since the
   2026-07-29 re-scope) commits v6.5.x to items **1–5** and its pull-forward note says
   v6.5.x carries *"the FULL shape, items 1–5, not just the substrate half."* Items 1–4 map to
   Slots 3/5/6. Item 5 does not appear in any slot, bite, or backlog row, and this document
   elsewhere reframes the minor's theme from self-compile growth tax to generated-code quality —
   which contradicts that note. All three prerequisites are shipped and verified
   (`scripts/bench-history.sh:174-181` runs `CYRIUS_PROF=1`; `lib/alloc.cyr:65/:85` carry the
   `_threads_active` single-threaded fast path; `2026-06-10-runtime-bench-suite-blind` is
   archived), so nothing blocks it. Either give it a named bite — a phase-resolved self_compile
   audit read off `bench-history.csv` + `CYRIUS_PROF`, in Slot 3 (shares the substrate) or W4
   (feeds the closeout) — or record here that it was retired, and why. **Do not let it vanish:
   silently dropping a user-committed item is exactly what this sweep exists to stop.**

6. **W3 sizing.** W3 is set at 5 patches on the assumption that the residency + coroutine arcs
   generate the minor's biggest consumer-facing behaviour change and therefore its biggest
   filing burst. If the agnos cadence in W1/W2 comes in lighter than the measured 6.4.x rate,
   W3 is the window to shrink first.

---

## Discipline (per [cycle-discipline.md](cycle-discipline.md))

**Premise-check each arc at slot entry** — empirically test that the gap still exists, against
the UPSTREAM repo source (`~/Repos/<dep>/src`), never the vendored `lib/` copy. This sweep is
the live example: three of the six rows in the previous v6.5.x table were describing work that
had already shipped or a blocker that had already died.

**`sh scripts/release-gate.sh` GREEN before EVERY `.NN` tag** — self-host fixpoint, **seed
derive** (`seed → cybs → cycc`; mandatory for ANY `src/` change, EVERY release — the cycc
fixpoint does not cover it, and cybs fails **silently** on things `build/cycc` compiles fine),
check.sh, cross-OS on ecb/ach/cass/pi (**real hardware, one host at a time** — fixed `/tmp` and
remote paths clobber under concurrency), bench. **Never tag with the gate RED.**

**Benchmark EVERY release** — `sh scripts/bench-history.sh` on a quiet box, before
`version-bump.sh`, with the headline delta (self_compile ms + cycc size) recorded in the
CHANGELOG. A perf delta is growth-tax by default; bisect only if one patch dominates. And a
byte-identical binary **cannot** regress — check the sha before triaging perf.

**One bug ships complete.** However nasty a bug turns out to be, fix it fully in one release.
Never slice one fix so the hard half defers. **An audit's output is fixes, not a backlog** —
file only when the fix genuinely cannot pack into the patch (a heap/brk **layout** change ⇒
two-step bootstrap, a design decision that is the user's, cross-repo coordination, or a full
gate cycle the release cannot absorb) and **name the reason**.

**When stuck, ASK.** Never decide to defer, slip, re-slot, or split mid-execution. Splits are
planned decisions made *before* starting. **Only the user pivots focus** — surface findings;
never unilaterally redirect. Deferral is real only when FILED with a roadmap slot and acceptance
criteria, and once documented-and-deferred, move on.

**Fix the SOURCE repo, not the fold.** sigil/sakshi/bayan/sandhi/yukti/… are the language's OWN
stdlibs — a fix applied only to the vendored `lib/<dep>.cyr` evaporates at the next re-vendor.
Patch upstream, version-bump, regen **all** distlib profiles, re-vendor. And mind the
snapshot-ping-pong loop when editing anything in `lib/`.
