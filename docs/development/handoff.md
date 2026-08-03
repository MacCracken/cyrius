# Handoff — **v6.5.6 is out.** v6.5.x continues; nothing is mid-arc.

> **Written 2026-08-03.** Read this, then `CLAUDE.md`, then [`state.md`](state.md), then
> [`roadmap.md`](roadmap.md) for the slot sequence. **Refresh or delete this file when the
> next release ships** — a stale handoff is worse than none.

---

## Where things stand

| | |
|---|---|
| Version | **6.5.6** — release gate GREEN, all 5 steps |
| cycc x86_64 | **1,133,440 B** — seed 29,024 B → cybs → cycc byte-identical |
| Gates | `check.sh` **153 / 0** + **10** shell gates · bench 643/648 ms |
| Cross-OS | ecb · ach · cass · pi — all `SELFHOST_OK` + VR-01 `LIBTEST_OK` on real hardware |
| Corpus | **254** `.tcyr` · 99 `lib/*.cyr` · api-surface **4783** · heap 100 regions / 0 overlaps |
| Queue | **16** open issues · 2 proposals · 281 archived |
| Mid-arc work | **None.** 6.5.6 is complete; the next slot is open. |

## What v6.5.x has shipped

- **.0** — file-scoped `public`/`private` for fns *and* global vars. Opt-in per file, hard
  error on violation, private excluded from `.dynstr`, `lib/regex.cyr` adopted.
- **.1** — overload-suffix dispatch made arity-aware, plus the `PARSE_RETURN` tail-path
  divert. Folded bayan 1.3.0 / sakshi 2.4.7 / yantra 1.0.2 / sandhi 1.9.7.
- **.2** — the `ir_const_fold` jump-span miscompile (**default-vs-IR=3 mismatches 35 → 8**);
  the `_read_env` aliasing that made every IR knob silently inert; `xrmdir`; yukti 2.3.0's
  six agnos ABI defects.
- **.3** — diagnostic lines surviving `include` expansion; `install.sh`'s ETXTBSY strand;
  `version-bump.sh`'s same-version early exit.
- **.4** — `vec_sort_by` / `vec_select_nth`, the stdlib's first ordering primitive (the agnosai
  filing). Folded sigil 3.12.2 / yukti 2.3.2 / sandhi 1.9.8 / mabda 4.0.8. Fixed the
  vacuous sign-efi gate. Re-derived every folded-dep version table from live `lib/` headers.
- **.5** — the `CYRIUS_IR=3` switch-dispatch miscompile filed by cyrius-doom. Filed as LASE;
  it is **DCE**. Closes `switch_dispatch` (18 → 0); **7 of the 8 residual IR=3 mismatches
  remain**. Also folded bayan 1.4.0.
- **.6** — the agnosai/sandhi pair, W1: **`sys_exit_group`** (a threaded program's idiomatic
  epilogue hung — `sys_exit` is exit(2)) on all 3 syscall peer families;
  **`async_await_readable_ms`** (a cooperative server could not be woken to stop);
  macOS-x86's untranslated 231 → silent SIGSYS; `proj-tcyr`'s 8-bit exit truncation
  (256 failures scored PASS); `cyrius fuzz` blind to scaffolded harnesses. Folded sandhi
  1.9.9 + vani 1.1.3.

## ⚠ Read before trusting anything in the tree

**Three of the 16 open issues are UNVETTED.** Filed by subagents during the 6.5.2 triage,
never reviewed by the maintainer or by me: `2026-07-29-fmt-int-buf-i64-min`,
`2026-07-29-no-portable-xmkdir-in-io-cyr`,
`2026-07-29-mutex-unlock-unconditional-futex-wake`. Verify against live code before acting.

**A gate being green is not the same as a gate being run.** Two blind spots were closed
earlier this minor (release-gate grading check.sh by stdout not `$?`; `io_rdwr_agnos.sh`
being CI-only). **6.5.6 found the third shape: a fix that shipped with no gate at all.**
`cyrius bench`'s tests/ walk (v6.4.78) and `cyrius test`'s (v6.4.72) were both ungated, so
when `cyrius fuzz` had the identical defect nothing caught it for two minors. When you fix
one member of a family, gate the **family invariant**, not the instance.

**CI runs neither `check.sh` nor `build/cyrius_check`** — only `tests/heapmap.sh` and
`tests/io_rdwr_agnos.sh`. Everything else is local / release-gate only. Verified 6.5.6:
`grep -ohE 'sh tests/[a-z0-9_]+\.sh' .github/workflows/*.yml`.

## Two things owed to the maintainer

Both are recorded as answered open questions in [`roadmap.md`](roadmap.md), and both belong
to the **later performance track** — to be reviewed **together** when it opens:

1. **The self_compile budget.** roadmap_6's acceptance anchor has two clauses; the svara
   figure is carried, the budget clause was never actually stated anywhere. Baseline to set
   it against: **654 ms · 1,129,288 B**.
2. **v6.5.x committed item 5 — the self-compile growth-tax audit.** Likely dropped, but
   parked against that track's opening review rather than silently discarded.

## Where the next slot is likely to start

W1 (v6.5.4 → .8) still has its named queue; .6 spent one of its reserve patches on the
agnosai/sandhi pair. Unstarted W1 items: the **syscall-wrapper pass** (item 1 — `fchownat`,
`sys_chdir`, `xmkdir`/`xmkdir_p`, `xsymlink`/`xreadlink`/`xlink`; note `sys_chdir` is called
at `lib/regression.cyr:658` and **defined nowhere**, so that stdlib file cannot compile for
any consumer reaching it), the **`i64::MIN` formatter class** (all 7 sites), the
**three-state mutex**, **`dir_list` both halves**, **`distlib --all`/`--check`**, and the
**release-gate coverage** bite.

Then the IR substrate (Slot 3): **8 residual default-vs-IR=3 exit mismatches** and the
regalloc walls (`ir_lower_all` has zero callers; `IR_SENABLE(S,2)` never activated;
`ir_build_edges` gives `IR_SWITCH` a single fall-through edge).

## Standing traps (the expensive ones)

- **cybs cannot lex `>>>`**, and mis-compiles fns with too many global/call references. The
  cleanest proof the cycc fixpoint does NOT cover the seed chain.
- **"0 of 254 changed" means the corpus has no coverage of the shape, not that the change is
  safe.**
- **A byte-identical rebuild after a real behaviour change is a TELL.** Corollary found at
  6.5.6: an **identical byte SIZE** is not identical bytes — the 231 xlat entry left cycc at
  exactly 1,133,440 B while 872,790 bytes moved. `cmp`, don't `ls -l`.
- **`lib/` is NOT free of cycc byte-identity risk.** `src/main.cyr` includes only
  `lib/alloc.cyr` + `lib/vec.cyr`, but `alloc.cyr:44` unconditionally pulls `lib/atomic.cyr`
  and both pull `lib/fnptr.cyr` — the real closure is **four** files. Editing `atomic.cyr` or
  `fnptr.cyr` moves the compiler (measured: 425,580 bytes).
- **The api-surface gate does NOT skip folded distlib bundles** (lint/fmt/cyrdoc do, via
  `_aw_is_distlib_bundle`). sandhi/sigil/mabda/vani are the majority of the 4783 entries, so
  a fold that removes or re-arities a public fn turns the gate RED. Run
  `cyrius_api_surface --update` and verify **zero removals by set difference**, not by the
  summary line.
- **`lib/sakshi.cyr` uses a THIRD fold-header format** (`Bundled distribution of sakshi
  v2.4.7`). A two-pattern scan silently drops it from the drift table.
- **A per-file `.tcyr` loop that reuses one output path silently runs STALE binaries** —
  ETXTBSY on the redirect, prior binary still executable, exit 0. Use a unique path per test.
- **An unreachable fn's body error never surfaces** (it is DCE'd).
- **The heap map is machine-read.** Prose on a map line is parsed as the size.
- **`var x[N]` local = N BYTES; a bare top-level `var x[N]` = N×8.**
- **Cyrius precedence is NOT C's** — `&`/`|`/`^` share the `+`/`-` tier. `>>` is LOGICAL,
  `>>>` is ARITHMETIC. **`#` starts a comment** — the include directive is bare `include`.
- **A raw agnos syscall number off-agnos is the whole hazard.** The file-level
  `#ifdef CYRIUS_TARGET_AGNOS` gate is the barrier.
- **`cyrius lib sync` is refused in this repo** but is the CORRECT mechanism downstream.
- **`cyrius distlib` regenerates only the main bundle** — run it per profile and grep each.

## Process

- The user handles **all** git. Never commit, push, or tag. Never use `gh` — `curl` the API.
- `release-gate.sh` GREEN before every `.NN`. `--quick` is steps 1–3, explicitly not
  release-ready.
- Run `cross-os-selfhost.sh` **one host at a time** (fixed /tmp paths clobber).
- **An audit's output is FIXES, not a backlog.** File only when the fix genuinely cannot pack
  into the patch — and NAME the reason.
- **Mutation-prove every gate**, and prove it against the RELEASE gate, not just its own exit.
- **Fix the SOURCE repo, not the fold.**
