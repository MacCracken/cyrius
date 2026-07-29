# Handoff — **v6.5.0 is out**: `public`/`private`. v6.5.x continues.

> **Written 2026-07-29**, at the v6.5.0 ship. Read this, then `CLAUDE.md`, then
> [`state.md`](state.md). **Refresh or delete this file when the next minor ships** — a stale
> handoff is worse than none.

---

## Where things stand

| | |
|---|---|
| Version | **6.5.0** — the v6.5.x OPENER (v6.4.x closed at .85; .86 was the sandhi fold) |
| cycc x86_64 | **1,124,968 B** — seed 29,024 B → cybs → cycc byte-identical |
| Gates | `check.sh` **150 / 0** + 5 shell gates · release gate GREEN all 5 steps |
| Cross-OS | ecb · ach · cass · pi — all `SELFHOST_OK` + VR-01 `LIBTEST_OK` on real hardware |
| Corpus | **253** `.tcyr` · 99 `lib/*.cyr` · api-surface **4755** |
| Heap | **100** regions, 0 overlaps — v6.5.0 added **no** region (see below) |
| Open issues | **15** · 3 proposals · 273 archived |

## What v6.5.0 shipped

**File-scoped visibility — the language's first enforced encapsulation boundary.** A top-level
`private` flips that FILE to private-by-default; per-item `public` re-exposes; a file with no
declaration behaves exactly as it did before. Covers **fns and global vars**. Cross-file reference
to a private item is a **hard error**, routed through the multi-error path so one compile reports
all violations. Private fns are also dropped from the exported symbol table — `lib/regex.cyr`
adopted it and its exported symbols went **24 → 14**.

Substrate: `_fnt_fileid` (fn-indexed, lazy-alloc at 32768) and `_var_fileid` (vcnt-indexed,
lazy-alloc at 1048576), plus fn_flags bit 6. **Lazy-alloc was chosen precisely to avoid a heap-map
change** — no new region, no layout change, therefore no two-step bootstrap.

## ⚠ Read this before trusting a green gate

**`release-gate.sh` step 3 graded `check.sh` by grepping its printed summary line, never its exit
status** — so every gate `check.sh` runs *after* the check binary (`qemu-boot`, `sign-efi`, and the
three added this arc) was **advisory**. A failure aborts `check.sh` with a non-zero exit while the
already-printed `0 failed` summary stays on screen, and the release gate reported GREEN over it.

Found when `fileid_substrate.sh`'s matcher broke — the debug dump gained a visibility column
(`<id> <name>` → `<id> <P|-> <name>`) and every lookup silently returned empty. It failed for an
entire multi-phase arc without turning anything red. **Both are fixed and mutation-proven** (plant
an `exit 1` gate → RED; restore → GREEN), but the lesson generalises and is now in
`methodology.cyml`: **grading a subprocess by parsing its stdout instead of checking `$?` turns
every appended check into a no-op.** When you add a shell gate, verify it can turn the RELEASE gate
red — not merely that it can fail.

## Open, live, and worth reading first

- `issues/2026-07-29-agnosai-int-overload-call-result-misdispatch.md` — **confirmed High.** I
  reproduced it: `take(make())` runs the *wrong* overload's body; the repro exits 1 where 0 is
  expected. Repro is committed at `issues/repros/`. **Not fixed in 6.5.0 by explicit user
  instruction** ("we are not repairing ANY FILES ISSUES WITH THIS RELEASE"). This is the one to
  pick up first.
- `issues/2026-07-27-intrinsics-cannot-flank-a-term-tier-operator.md` — **partially addressed**:
  v6.4.83 extracted `PARSE_INTRIN` out of `PARSE_TERM`'s head and wired it into `PARSE_FACTOR`.
  Re-verify what remains against live code before assuming the whole issue is open.
- `issues/2026-07-28-main-source-diagnostic-line-wrong-after-an-include.md` — diagnostics report
  the wrong LINE for the main source once any `include` is present. **The obvious fix was tried and
  disproved**: carrying a resume line in the marker changed nothing. The issue records the
  disproved theory so the next attempt does not repeat it. The remaining suspect is that `FM_BUILD`
  and the lexer's `tok_lines` count marker lines differently.

## v6.5.x continues with

1. **Perf/IR substrate** — the `CYRIUS_IR=3` failures are bounded, fixable bugs. SIMD
   register-residency is gated on this.
2. **Stackless coroutines** — ▲ PINNED v6.5.x; `roadmap-future.md` is authoritative. Its issue is
   deliberately left OPEN as the acceptance record — do not "clean it up".
3. **macOS-arm64 threading** also homes here.
4. **`_`-prefix visibility** was explicitly deferred out of the visibility design — `private` is the
   enforced mechanism, `_` stays a convention. Do not conflate them.

**Nothing codegen ever parks to 7.x.** 7.x is the language book + legal-for-public-release, only that.

## Standing traps (the expensive ones)

- **cybs cannot lex `>>>`** — self-hosts fine on `build/cycc`, then seed-derive fails with a bare
  `syntax error`. The cleanest proof the cycc fixpoint does NOT cover the seed chain. cybs also
  mis-compiles fns with too many global/literal references (`_grow_g1..g7`, `TOKNAME_BUILTIN`,
  `PP_FNAME_TOO_LONG` are all split for this reason).
- **A byte-identical rebuild after a real behaviour change is a TELL, not a reassurance** — it means
  the edit sits on a path cycc's own source never takes. That is how the Phase 2b var stamp was
  caught sitting inside the annotated-only (`ann_scalar < 8`) branch, firing only for `var x: i32`.
- **The parser is two-pass and pending-modifier flags leak across it.** `_pub_pending` was consumed
  in `PARSE_FN_DEF` but not `_prescan_fn_sig`, so `private` worked in a main source and silently did
  nothing from an include. Consume in BOTH passes.
- **The heap map is machine-read.** Prose on a map line is parsed as the size. Keep it on
  continuation lines.
- **`var x[N]` local = N BYTES; a bare top-level `var x[N]` = N×8.**
- **Cyrius precedence is NOT C's** — `&`/`|`/`^` share the `+`/`-` tier. `1 | 2 + 1` == 4. `>>` is
  LOGICAL, `>>>` is ARITHMETIC. Verify by running the compiler.
- **`#` starts a comment** — the include directive is bare `include "..."`. A `#include` probe is
  inert, which is how a CVE-32 repro was written that tested nothing.
- **A raw agnos syscall number off-agnos is the whole hazard.** #94 is `lchown` on x86_64 (arg1 = a
  path pointer) and **`exit_group` on aarch64 — it terminates the process.** The file-level `#ifdef
  CYRIUS_TARGET_AGNOS` gate is the barrier; off-agnos these fns must not exist.
- **`cyrius lib sync` is refused in this repo** — it would revert every fold. To refresh a folded dep:
  `cp <upstream>/dist/<name>.cyr lib/<name>.cyr`, then refresh the install snapshot immediately.
- **`cyrius distlib` regenerates only the main bundle** — run it per profile and grep each for the fix.

## Process

- The user handles **all** git. Never commit, push, or tag. Never use `gh` — `curl` the API.
- `release-gate.sh` GREEN before every `.NN`. `--quick` is steps 1–3, explicitly not release-ready.
- Run `cross-os-selfhost.sh` **one host at a time** (fixed /tmp paths clobber).
- **An audit's output is FIXES, not a backlog** (`CLAUDE.md` "Execution integrity"). File only when
  the fix genuinely cannot pack into the patch — and NAME the reason.
- **Mutation-prove every gate**, and prove it against the RELEASE gate, not just its own exit code.
