# Handoff — **v6.5.5 is out.** v6.5.x continues; nothing is mid-arc.

> **Written 2026-07-30.** Read this, then `CLAUDE.md`, then [`state.md`](state.md), then
> [`roadmap.md`](roadmap.md) for the slot sequence. **Refresh or delete this file when the
> next release ships** — a stale handoff is worse than none.

---

## Where things stand

| | |
|---|---|
| Version | **6.5.5** — release gate GREEN, all 5 steps |
| cycc x86_64 | **1,133,440 B** — seed 29,024 B → cybs → cycc byte-identical |
| Gates | `check.sh` **150 / 0** + **10** shell gates · bench 644 ms |
| Cross-OS | ecb · ach · cass · pi — all `SELFHOST_OK` + VR-01 `LIBTEST_OK` on real hardware |
| Corpus | **254** `.tcyr` · 99 `lib/*.cyr` · api-surface **4777** · heap 100 regions / 0 overlaps |
| Queue | **16** open issues · 2 proposals · 279 archived |
| Mid-arc work | **None.** 6.5.5 is complete; the next slot is open. |

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
  filing; **no fn in any of the 99 `lib/` modules took a comparator**). Folded sigil 3.12.2 /
  yukti 2.3.2 / sandhi 1.9.8 / mabda 4.0.8. Fixed the sign-efi gate, which was **vacuous**
  against the exact defect sigil 3.12.2 fixes (single 8-aligned fixture) *and* was grading the
  installed helper instead of the repo build. Re-derived every folded-dep version table from
  live `lib/` headers — 3 of 4 had rotted again, and `yantra` was missing from both.
- **.5** — the `CYRIUS_IR=3` switch-dispatch miscompile filed by cyrius-doom. Filed as LASE;
  it is **DCE**. `CYRIUS_LASE_OFF=1` is not LASE-specific — `ir_apply_lase` is the only
  NOP-filler and applies marks from three passes. Root cause: an `IR_RAW_EMIT` marker only
  shields raw bytes until the **next recorded node**, and `ESWITCH_DISPATCH_PRE` recorded
  four nodes between its marker and its raw `sub`/`cmp`, hiding their rcx reads from DCE.
  Closes `switch_dispatch` (18 → 0); **7 of the 8 residual IR=3 mismatches remain**. Also
  folded bayan 1.4.0.

## ⚠ Read before trusting anything in the tree

**Three of the 15 open issues are UNVETTED.** They were filed by subagents during the 6.5.2
triage, which had been told not to write files, and **neither the maintainer nor I have
reviewed them**: `2026-07-29-fmt-int-buf-i64-min`,
`2026-07-29-no-portable-xmkdir-in-io-cyr`, `2026-07-29-mutex-unlock-unconditional-futex-wake`.
Verify their claims against live code before acting. The `xmkdir` one is at least
*plausible* — it is the companion observation to the `xrmdir` added at 6.5.2 — but that is
not verification.

**A gate being green is not the same as a gate being run.** Two blind spots were found and
closed this minor, both of the same family:
1. `release-gate.sh` graded `check.sh` by its printed summary instead of its **exit status**,
   so every shell gate appended after the check binary was advisory (fixed 6.5.0).
2. `tests/io_rdwr_agnos.sh` was **CI-only** — CI ran it, nothing local did, so the release
   gate went GREEN on a tree whose CI then went RED (fixed 6.5.1).
   When you add a gate, verify it can turn the RELEASE gate red, and check both sides:
   `grep -ohE 'sh tests/[a-z0-9_]+\.sh' .github/workflows/*.yml` versus what `check.sh` runs.

## Two things owed to the maintainer

Both are recorded as answered open questions in [`roadmap.md`](roadmap.md), and both belong
to the **later performance track** — to be reviewed **together** when it opens:

1. **The self_compile budget.** roadmap_6's acceptance anchor has two clauses; the svara
   figure is carried, the budget clause was never actually stated anywhere. Baseline to set
   it against: **654 ms · 1,129,288 B**.
2. **v6.5.x committed item 5 — the self-compile growth-tax audit.** Likely dropped, but
   parked against that track's opening review rather than silently discarded. Its
   prerequisites are all shipped, so nothing blocks it.

## Where the next slot is likely to start

[`roadmap.md`](roadmap.md) holds the sequence and four reactive windows (5/3/5/4 patches) for
issue repair and agnos syscall additions. The IR substrate's *correctness* blocker died at
6.5.2, so what remains there is:

- **8 residual default-vs-IR=3 exit mismatches** — `const_chained_multiply_fold`,
  `field_name_shadows_global`, `float`, `math_inverse_trig`, `math_pack_integration`,
  `subword_signed_load`, `switch_dispatch`, `types`. Now genuinely **bisectable**: 6.5.2
  fixed the `_read_env` shared-buffer aliasing that had made `CYRIUS_FOLD_OFF` /
  `CYRIUS_LASE_OFF` silently no-ops, which is why the filed issue's bisection table showed
  five identical hashes (every row was the same no-op run).
- **The regalloc walls, re-verified live at 6.5.2**: `ir_lower_all` has zero callers;
  `IR_SENABLE(S,2)` (record-only / re-emit) is never activated, only mode 1 and only in 2 of
  7 forks; 24 `IR_RAW_EMIT` sites on the x86 path; `ir_build_edges` gives `IR_SWITCH` a
  single fall-through edge, so the CFG is wrong for switch, not merely incomplete.

## Standing traps (the expensive ones)

- **cybs cannot lex `>>>`**, and mis-compiles fns with too many global/call references. The
  cleanest proof the cycc fixpoint does NOT cover the seed chain. **6.5.3 changed the
  `#@file` marker FORMAT, which cybs also parses** — exactly the class only seed-derive sees.
- **"0 of 253 changed" means the corpus has no coverage of the shape, not that the change is
  safe.** It said 0/253 for the overload arity fix, the `_int` gate, and the const-fold fix —
  all three were real. At 6.5.2 I nearly removed the `_int` route on a 0/253 reading;
  behaviour testing showed `println(fncall())` would have gone from printing `5` to nothing.
- **A byte-identical rebuild after a real behaviour change is a TELL** — the edit is on a path
  cycc's own source never takes.
- **Before concluding a fix "doesn't work", check whether something else overwrites the same
  record afterwards.** The 6.5.3 diagnostic fix had been implemented correctly once, verified
  present in the binary, and reverted as disproved — because a second hand-rolled emitter
  wrote a base-less duplicate right after it.
- **An unreachable fn's body error never surfaces** (it is DCE'd). A test whose erroring fn is
  never called is vacuous — this silently neutered an early version of the 6.5.3 gate.
- **The heap map is machine-read.** Prose on a map line is parsed as the size.
- **`var x[N]` local = N BYTES; a bare top-level `var x[N]` = N×8.**
- **Cyrius precedence is NOT C's** — `&`/`|`/`^` share the `+`/`-` tier. `>>` is LOGICAL,
  `>>>` is ARITHMETIC. **`#` starts a comment** — the include directive is bare `include`.
- **A raw agnos syscall number off-agnos is the whole hazard.** #94 is `lchown` on x86_64 and
  **`exit_group` on aarch64**. The file-level `#ifdef CYRIUS_TARGET_AGNOS` gate is the barrier.
- **`cyrius lib sync` is refused in this repo** (it would revert every fold) but is the
  CORRECT mechanism downstream — and it resolves from the **pinned** cyrius version's
  snapshot, so a downstream repo pinning an old version silently gets old stdlib.
- **`cyrius distlib` regenerates only the main bundle** — run it per profile and grep each.

## Process

- The user handles **all** git. Never commit, push, or tag. Never use `gh` — `curl` the API.
- `release-gate.sh` GREEN before every `.NN`. `--quick` is steps 1–3, explicitly not
  release-ready.
- Run `cross-os-selfhost.sh` **one host at a time** (fixed /tmp paths clobber).
- **An audit's output is FIXES, not a backlog.** File only when the fix genuinely cannot pack
  into the patch — and NAME the reason.
- **Mutation-prove every gate**, and prove it against the RELEASE gate, not just its own exit.
- **Fix the SOURCE repo, not the fold.** A fix applied only to a vendored `lib/<dep>.cyr`
  evaporates at the next re-vendor.
