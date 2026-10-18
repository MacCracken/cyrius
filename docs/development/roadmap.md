# Cyrius Development Roadmap — v6.7.x (active minor)

**Scope** — the **active minor only** (v6.7.x, the LANGUAGE minor): what is left of its release sequence, the spec
of each remaining feature, the Break 2 candidates, the folded-stdlib follow-ups and the unscheduled 6.x backlog.
Shipped work does not stay here: each release's record, with the user's decisions, is its
[CHANGELOG.md](../../CHANGELOG.md) entry (traits: [ADR-007](../adr/007-traits.md)); one line per release is in
[completed-phases.md](completed-phases.md). The minors after this one are in [roadmap_6.md](roadmap_6.md), the
unpinned watching list is [roadmap-future.md](roadmap-future.md), volatile state is [state.md](state.md).

> ⛔ **Consumer work is never tracked here** (CLAUDE.md, top rule — user, 2026-10-08). This file holds the language,
> its toolchain and the folded stdlibs (what `lib/` vendors). A consumer's follow-ups live in that consumer's own
> roadmap — the last ones were moved out on 2026-10-08 — and a consumer meets a cyrius change at its own pin bump,
> through the CHANGELOG and [ecosystem-migration.md](ecosystem-migration.md). agnos is a consumer.

## Where we are

**Current head: v6.7.14** (2026-10-17) — Break 2 repair 4, generics · the frontend · infra (the heavier release): 137 issues closed in nine lanes over three waves, the IR arena (a heap-layout change), the fold patra 1.16.4 · cycc **2,433,512 B** · `cycc-native-aarch64` **2,351,456 B** · **642** `.tcyr`, **335** in `crossos/` · **106** `lib/*.cyr` · **550** shell gates under `tests/gates/<bucket>/` · api-surface **5,891** · **122** open issues · **2** open proposals · next ledger id **CYRIUS-2026-0036**

> Every figure above is DERIVED (2026-10-08), never carried. `version-bump.sh` rewrites only the stamp's version and
> the `(…)` after it — re-derive the rest at each release (`find tests/gates -name '*.sh' | wc -l`, …). Keep the stamp
> at the start of its line with no nested parentheses in its parenthetical, or
> `tests/gates/toolchain/version_bump_doc_anchors.sh` goes red.

v6.6.x closed at 6.6.20. 6.7.0–6.7.6 shipped (2026-10-07 → 2026-10-08): [completed-phases.md](completed-phases.md)
§ *v6.7.x*.

## The v6.7.x operating rule (user, 2026-10-07)

1. **Language only between the breaks.** A feature release carries language features and nothing else. What it finds
   is FILED as an issue (`docs/development/issues/`), with a repro, the same turn; it is fixed in the release only when the feature cannot
   ship around it (a prerequisite bug) — **or when repairing it is faster than writing the issue: then it is repaired
   where it was found** (user, 2026-10-09), its own commit with its regression row; a quick fix that changes what
   compiles is still asked first. The repair releases are re-balanced at each one's open against what was filed since. A P0 security finding is reported the turn it is found — whether it interrupts
   the arc is the user's call.
2. **Catch-up breaks clear the backlog.** Break 1 was 6.7.6. **6.7.9 is a repair batch before the next feature** (user,
   2026-10-11): two lanes — the quick fixes and the critical / high issues — to take weight off the queue; B7 + P5-B
   moved to 6.7.10 and every later release shifted one. Break 2 is 6.7.11 – 6.7.15 (user, 2026-10-09; the fourth
   repair release added at the 6.7.12 open, user 2026-10-15; the fifth at the 6.7.13 integration, user 2026-10-16): the
   open queue repaired to 0 bugs, so fuller audits can follow. 6.7.16 is the full security audit + the refactor /
   optimization review (user, 2026-10-09; renumbered 2026-10-15 and 2026-10-16). The closeout's number is OPEN (user,
   2026-10-09): what the 6.7.16 reviews produce ships first, in as
   many releases as it takes, and the closeout follows.
3. **Every language decision is the user's** — asked at the arc's start, recorded with its date, never a lane's
   "default" (CLAUDE.md *Execution integrity*).
4. **Every new syntax ships with** a `tests/tcyr/crossos/` file (it runs on ecb / ach / cass / pi), a guide section and a
   vidya entry.

## Release sequence

| Release | Content |
|---|---|
| 6.7.0 – 6.7.14 | ✅ shipped — A traits · C3 trait-bounded generics · B1 `const` + C1 `const fn` · B2 `bool` · B3 the if-expression · B5 `loop` / `do` + B8 `OP=` on every lvalue · the W2 stdlib wave + Break 1 · B4 tuples + B6 default / named arguments (6.7.7) · checked `dyn` + C2 the bounds-checked mode (6.7.8) · the repair batch (6.7.9) · B7 packed narrow fields + the handle line + P5-B execution coverage (6.7.10) · Break 2 repair 1: multi-value receives, call arguments, struct copies and operators, generics + the frontend, cybs, the tools (6.7.11) · Break 2 repair 2: the platform release (6.7.12) · repair 3: struct values (6.7.13) · repair 4: generics, the frontend, infra (6.7.14) |
| 6.7.15 | Break 2, repair 5 (added 2026-10-16): **what 6.7.14 filed** (112 placed), re-balanced at its open; the 6.7.14 changes beyond the decisions' text and the decision questions among them asked there |
| 6.7.16 | **the full security audit + the refactor / optimization review** (user, 2026-10-09): the audit the 2–3-minor rule owes (last: 6.5.45), its findings fixed in the release · the largest files elevated · the libs improved with what the last months added |
| 6.7.17 → | what the 6.7.16 reviews produce — the number of releases is open, set at 6.7.16's close (user, 2026-10-09) |
| closeout | **after the review follow-ups** (number open): the closeout checklist ([cycle-discipline.md](cycle-discipline.md)) — the checklist, not an audit campaign |

**Break 2 is 6.7.11 – 6.7.15** (user, 2026-10-09; 6.7.14 added 2026-10-15, 6.7.15 added 2026-10-16): repair the open queue to 0, so fuller audits can follow. Each repair
release runs its lanes in waves, at most two `src/` lanes at a time. Each lane owns its files, and a cross-lane hunk
travels as a named hand-off patch. The binary is rebuilt once on the merged tree. There is one review round, and the
decisions are asked in one round at the open. The `2026-10-09-*` links resolve when 6.7.7 merges; they are on the
lanes until then.

**Why this order.** dyn and B7 both own `parse_types.cyr` and `parse_decl.cyr`'s field arms, so they never share a
release; C2 pairs cleanly with either. dyn goes first for two reasons. It builds directly on B4's anonymous-struct
interning and B6's argument marshaller. And its cx pair emitters must exist before B7 moves `f32 × 4` / `u8 × 16`
structs into cx's 16-byte class. P5-B is split to 6.7.10 now, at planning, because 6.7.8's two `src/` lanes are
taken; it reuses C2's flag plumbing. A third feature release is needed only if an open picks one of these:
- dyn as a generic type argument (5c);
- one of C2's heavy options: branch coverage, `*T` checked against poison headers, or raw `&a + e` checks;
- typed fn pointers too big for the dyn lane;
- u128 carriage inside 6.7.x. That needs the aarch64 register fix (6.7.7), so it would come after the repairs.

## Spec — the remaining features

Every feature of the v6.7.x plan has shipped (its spec and the user's decisions are in its CHANGELOG entry): traits,
C3 bounds, `const` / `const fn`, `bool`, the if-expression, `loop` / `do`, `OP=` on every lvalue, B4 tuples and B6
default / named arguments (6.7.7), checked `dyn` and the C2 bounds-checked mode (6.7.8), B7 packed narrow fields with
the handle line and size-independent struct copies, and P5-B execution coverage (6.7.10). What remains is repair
(6.7.11 – 6.7.15), the audit and review (6.7.16) and the closeout.

⚠ Every new keyword is a new reserved word (`IS_KEYWORD_TOK`).

## The releases after 6.7.8 (placed 2026-10-09; shifted one 2026-10-11)

Sized from every open issue and the three remaining features (the 6.7.x release-plan workflow, 2026-10-09; sizes and the full lane maps: `~/.cache/c6/plan678_712.json`). Every issue's `**Placement:**` line names its release; the open shapes of each feature are decided at its open.

### 6.7.15 — repair 5 (added at the 6.7.13 integration, 2026-10-16)

The user (2026-10-16): "we can add another release of repairs as 6.7.15, make 6.7.14 heavier as I'm sure we will have
another bunch of bugs from .14 that will make .15 balance out considering how many we have hit during repairs." 6.7.14
keeps every issue placed there (the heavier release); 6.7.15 takes what 6.7.14 files, and is re-balanced at its open.

**Filed by 6.7.14** (112 placed here at its integration, 2026-10-17 — from the nine lanes, their reviews and the
release-docs pass; [issues/README.md](issues/README.md) § *Open queue* lists them). Among them: one High pre-existing in
each of wave 1 (a nested type argument closed by `>>` then `,` drops the next argument) and wave 3 (a frame temporary
taken while an `#inline` fn's arguments are evaluated lies past the frame — the inline path's SFLC half); the
[6.7.14 changes beyond the decisions' text](issues/2026-10-17-6714-behaviour-changes-beyond-the-decisions-text.md) (keep
or restore each); the decision questions they raised (a redeclared global's value read between two declarations); and
[the Windows ProtectedRoots flag-1 measurement](issues/2026-10-15-windows-protectedroots-flag1-user-root-unverified.md),
which waits on the user's step at cass's desktop.

### 6.7.16 — the full security audit + the refactor / optimization review (user, 2026-10-09; renumbered from 6.7.14 at the 6.7.12 open, and from 6.7.15 at the 6.7.13 integration)

Its own release, after the queue is at 0 bugs — **not** the closeout (the closeout stays the checklist). Scope is
set at its open, in one round; the output of both reviews is FIXES (CLAUDE.md *Execution integrity*), with only what
cannot pack filed.

- **The full security audit** (CLAUDE.md § *Security Audit Process*; last full audit
  `docs/audit/2026-09-03-security-audit.md` at 6.5.45 — the 2–3-minor rule is due): map the attack surfaces (the TLS
  stacks, `net` / `http` / `ws` / sandhi, DNS, shared temp paths and Windows plantable paths, the release / download
  channel and the seed → cybs → cycc chain, `pam`, secrets in memory) as they stand after 6.7.x's growth; scan; report
  in `docs/audit/<date>-security-audit.md`; a ledger id only for an actual vulnerability (attacker + boundary named);
  P0 / P1 fixed in the release, each with a regression test.
- **The refactor / optimization review — elevate the large files.** The frontend has outgrown its files
  (`parse_fn.cyr` ~13.9 K lines, `parse_expr.cyr` ~6.4 K, `parse_decl.cyr` ~6.2 K, `lex_pp.cyr` ~5.3 K, `parse.cyr`
  ~4.5 K; `cbt/commands.cyr` / `deps.cyr` ~6.6 K each): split them along their real seams (the trait / generic /
  const-fn modules, the call path, the statement dispatch), shrink the giant fns that sit near cybs's per-fn
  reference ceiling (PARSE_FNCALL, PARSE_RETURN, `_PARSE_FN_DEF_IMPL`, `_PARSE_FACTOR_IMPL`, `_field_load_on`), dedupe
  the walkers and scanners the 6.7.x features each grew. Logic-preserving: byte-identical self-host + the whole-corpus
  differential, seed-derive on every bite. Optimization: the self_compile growth tax (1,175 ms at 6.7.6) and cycc size,
  measured same-box before / after.
  - **The layout direction (user, 2026-10-09 — "just thoughts", settled at 6.7.16's open):** folders with direct
    names instead of prefixed files, as `backend/` already does — `src/frontend/parse/expr.cyr` for `parse_expr.cyr`,
    `parse/types/type.cyr` (beside `struct.cyr`, `tuple.cyr`, …) for `parse_types.cyr`, `parse/fn/` for the pieces of
    `parse_fn.cyr` (definitions, the call path, the return / tail path, traits, generics, the const-fn evaluator),
    `lex/` for `lex.cyr` + `lex_pp.cyr`; `cbt/` likewise (`commands.cyr` / `deps.cyr` by verb and stage). Measured
    2026-10-09: cycc embeds no `src/frontend/` path (a pure move rebuilds byte-identical); the include chain is the
    seven forks' `lex.cyr` / `parse.cyr` lines plus `parse.cyr`'s own; cybs's include handler takes a 4 KB name per
    nesting level; ~90 gate files and the docs name these paths. How:
    1. **Moves first, as their own bites — `git mv` + include lines + every path reference, no content change** (the
       grep covers `tests/gates/`, `scripts/`, `.github/workflows/`, `programs/`, `cbt/`, docs, vidya, the open issues'
       `file:line` pointers); byte-identical cycc and seed-derive prove it. Then the splits, each its own bite, so
       history follows (`git log --follow`) and every diff stays reviewable.
    2. **Keep the include graph as flat as today** — one parent includes a folder's files — since cybs's nesting
       depth is bounded; seed-derive on every bite.
    3. **Watch basename collisions** (`lex/lex.cyr` beside `ts/lex.cyr`) wherever a tool or diagnostic keys on a
       basename (`#@file` markers, `CYRIUS_SYMS`, crash localization, cyrdoc).
    4. **`src/`, `cbt/` and `programs/` are internal — free to move. `lib/` paths are the stdlib's public contract**
       (`include "lib/str.cyr"`, `[deps] stdlib`, distlib): reorganizing `lib/` keeps every old path working (a
       one-line include of the new home) and is the user's call per module.
    5. **At 6.7.16, not before** — with no lanes in flight, and after the repair releases, whose issue files cite
       today's `file:line`.
- **Improve the libs with what the last months added**: where it makes `lib/` clearer or safer, use the 6.7.x
  language (traits, `const` / `const fn`, `bool`, tuples, default / named arguments, `loop` / `do`, `OP=`), fill the
  gaps the folds and the repair releases exposed, and retire hand-rolled patterns the language now covers. ⚠ A lib
  file `src/` includes must stay compilable by cybs (no new syntax there); a public symbol's removal or semantic change
  is the user's call (`removed_symbol_census.sh`); a fold's improvement lands in its SOURCE repo and is re-vendored.

- Filed 2026-10-12 / 13 (the 6.7.10 lanes and their reviews):
  - [The compiler's own self-compile prints the large-static-data advisory (cycc's globals are over the 131,072 B line)](issues/2026-10-13-self-compile-prints-large-static-advisory.md);


### 6.7.17 → — what the reviews produce, then the closeout (number open)

The 6.7.16 reviews' findings that did not pack into 6.7.16 ship next, in as many releases as they take — sized and
placed at 6.7.16's close, never squeezed into the closeout. Then the closeout:


The [cycle-discipline.md](cycle-discipline.md) checklist, ticked into its ledger:
- **Mechanical:** `release-gate.sh` (record check.sh's count) and the bench.
- **Judgment:** heap map (the retired IR bands), the dead-code floor, the 2–3 consolidations the minor earned, code
  review, cleanup.
- **Compliance:** the security re-scan (the full audit ran in 6.7.16); folds byte-identical to their tags (yantra,
  bayan); `verify-store.sh`.
- **Docs:** CHANGELOG / roadmap / state; vidya (tuples, defaults, `dyn`, the bounds mode, packed fields, coverage);
  the backlog re-triaged to 0 open.

### Proposals — later in the 6.7.x line (the user, 2026-10-15: "keep proposals for later in 6.7.x line")

After Break 2 and the 6.7.16 audit; their release is set when the review follow-ups are:
[adjacent string-literal concatenation](proposals/2026-10-13-adjacent-string-literal-concatenation.md) ·
[`memmove`](proposals/2026-10-14-memmove.md).

### Placed arcs — open by design (moved out of the bug queue)

- [Native TLS capability limits](issues/2026-10-08-native-tls-capability-limits.md):
  - items 1–5 go to [roadmap_6](roadmap_6.md), a capability arc on top of 6.7.12's conformance bite and its 6.7.14 residue;
  - item 6 goes to [roadmap-future](roadmap-future.md), pending constant-time X448 / P-521 in sigil's source.
- [Constant `if` arms](issues/2026-10-08-constant-if-arms-not-folded.md) → roadmap_6, beside the DCE compaction arc.
- [The public-constants `const` migration](issues/2026-10-08-lib-public-constants-const-migration.md) → roadmap_6:
  a stdlib arc that changes what compiles, with sandhi's patch planned at its open.
- [Build profiles and `[build] target`](issues/2026-10-08-manifest-build-profiles-and-target-unread.md) →
  roadmap-future: a CLI feature with two forks.
- [Poison guard pages](issues/2026-10-08-poison-guard-pages-unbuilt.md) → roadmap-future: P6's unbuilt step, which
  needs a PE `VirtualProtect` reroute.
- u128 carriage → roadmap_6, after 6.7.7's register fix. The file itself closes in 6.7.14.

## Folded-stdlib follow-ups (cyrius's own work)

The twelve folds — sakshi, sigil, bayan, sandhi, ganita, niyama, mabda, vani, yantra, yukti, patra, sankoch — are the
language's own stdlib. A fix lands in the fold's SOURCE repo and is released there, then re-vendored byte-identical
(`cmp` against the tag's `dist/`) with its `docs/ecosystem.md` row updated. Each fold's own roadmap holds its longer
list (W2 left there: public `const` / `bool` sweeps in each repo's own minor, traits for hand-rolled dispatch after
checked `dyn`, sigil 3.14.0's cbank retirement, …; sandhi's libssl session-resumption test). Filed here:

- [`#derive(Serialize)` does not support a `: cstring` field — it is taken for a nested struct (asked by sigil)](issues/archived/2026-10-08-derive-serialize-cstring-fields.md)
- [`lib/math.cyr` has no public length-bounded `f64_parse` — the correctly rounded core is internal (`_f64_parse_n`)](issues/archived/2026-10-08-f64-parse-no-public-length-bounded-form.md)
- [cyrius's own `lib/` still spells its public constants as `var` — the public-constants-are-`const` migration (asked by the folds' W2 sweeps)](issues/2026-10-08-lib-public-constants-const-migration.md)
- [No stdlib `ppoll` wrapper, and the agnos peer lacks `sys_ioctl` / `sys_fstatat` stubs (asked by yukti)](issues/archived/2026-10-08-no-ppoll-wrapper-and-agnos-ioctl-fstatat-stubs.md)
- [No `sock_set_nodelay`, and Windows `sys_setsockopt` is a -38 stub although net.cyr reaches ws2_32 setsockopt — `TCP_NODELAY` is never set on PE (asked by yantra)](issues/archived/2026-10-08-sock-set-nodelay-windows-route.md)
- [`xflock` has no Windows route (`LockFileEx` not wired) — patra's crash recovery never runs on Windows (asked by patra)](issues/archived/2026-10-08-xflock-windows-lockfileex-not-wired.md)
- [yantra: nine test files include `src/web.cyr` / `src/mobile.cyr` without `src/security.cyr` (undefined-function warnings)](issues/archived/2026-10-08-yantra-tests-miss-security-include.md)
- [sigil has no runtime logging: none of its `src/` files calls sakshi](issues/2026-10-12-sigil-has-no-runtime-logging.md) — unplaced (the user, 2026-10-12: "leave it for later")
- **Adoptions 6.7.9 opened** — prepared 2026-10-11 as fold patches pinned to cyrius 6.7.9, refolded in 6.7.10
  (CHANGELOG [6.7.10], with the sakshi and sigil fixes): yukti → `sys_ppoll`; bayan → `f64_parse_n`; yantra → `sock_set_nodelay`.
- **Constraints on any fold release**: never change the fold API cyrius's own `lib/` calls (sigil's 73 fns, 8 of them
  private `_x509_*` / `_ecdsa_*` used by `tls_native_hs12` / `hs13` / `tls.cyr`; sakshi's 6 in `log.cyr`; bayan
  `base64_encode` in `ws` / `ws_server`; sandhi `sandhi_server_find_header` in `ws_server`). cyrius must not make the
  stdlib internals the folds use `private` (bayan `_sb_grow_a` / `_sb_die`; niyama `_uc_decode_utf8` /
  `_uc_decompose_cp_recursive` / `_uc_emit_utf8`; ganita `_f64_rem_pio2`). A `const` beside a same-name `var` is a
  hard error (sandhi `HTTP_OK` / `HTTP_NOT_FOUND` against `lib/http.cyr` is why sandhi's public consts wait). Adopting
  6.7.x syntax raises a fold's minimum toolchain. yukti pulls sakshi and patra as git tags, so it releases after them.
  yantra's `dist/` is untracked: its refold is `cyrius distlib` at the tag.

## The backlog — `docs/development/issues/`

The backlog is [`issues/`](issues/) (user, 2026-10-08: "issues that are backlogged should have issue/ filed, not sit
in the roadmap"): one file per item, each with a repro and a `**Placement:**` line. This file carries placements and
links only. Only the user promotes an unplaced item into a release. **73** files were filed on 2026-10-08 —
the whole former backlog, premise-checked against 6.7.6, plus what the 6.7.7 lanes found — grouped in
[`issues/README.md`](issues/README.md) § *Open queue*. Placed later-minor work (the DCE compaction arc, `net.cyr` §4,
AF_UNIX, the syscall families) is in [roadmap_6.md](roadmap_6.md); unpinned features (DWARF, `tantu`,
auto-vectorization, …) are in [roadmap-future.md](roadmap-future.md).

## 7.x — public-release ONLY

The language book + legal (licensing / public-release prep). **No codegen, runtime or platform work ever lives at
7.x — if it compiles code, it is 6.x.**

## Open questions — standing defaults, not a queue

Each item carries its default and work starts under it; a genuine fork is asked in one line, that turn — never parked
here as "owed".

1. **The self_compile budget and the growth-tax audit — the later performance track owns both** (user, 2026-07-29;
   the audit is likely dropped, decided at that track's opening review). Input: **1,175 ms · 1,806,240 B at 6.7.6**
   (923 ms · 1,586,184 B at 6.6.19; the old ≤ 700 ms / ≤ 1.20 MB pair is exceeded on both halves — an input to
   re-decide, not a missed target). Record the outcome here.

## Standing notes — traps this minor must not re-learn

- **A batched release** runs strictly sequentially; parallelism is only INSIDE one, in git-worktree lanes where each
  file has one owning lane and every cross-lane hunk travels as a named hand-off patch to a named merge step. At most
  two `src/` lanes, one of which commits `build/cycc`; the binary is rebuilt once on the merged tree (fixpoint +
  seed-derive), `build/cycc-native-aarch64` once with `cyrius pulsar`. Ratchets and censuses (`CORPUS_FLOOR`,
  `CYCC_CEIL`, the alloc census, the cross-compile allowlist, the self-sufficiency floors) are integration steps.
  **A per-lane green is not a merged green.**
- **A ledger id (`CYRIUS-YYYY-NNNN`) is spent in the commit that records it, and only for an actual security
  vulnerability** (attacker and boundary named). That commit moves the ledger
  (`docs/audit/2026-10-08-security-ledger.md`) and state.md's next-id.
- **Text handed into a cyrius string literal obeys the 6.6.11 lexer**: a driver `_gate("…")` description carrying a
  bare `"` or an unknown escape (`\<LF>`, `\q`) stops `programs/checks` compiling.
- **A fold's CI runs isolated, never by hand-extracted steps**: a clean `git archive` copy with `path` deps commented
  out, a throwaway `CYRIUS_HOME` (a copy of the pinned slot, an EMPTY dep cache) and a throwaway `HOME`, with GitHub's
  shell semantics (`bash -e` unless the workflow says `shell: bash`).
- **The `PARSE_RETURN` tail path has skipped a call-site obligation five times** (v6.3.36, v6.4.53, v6.5.1, v6.5.2,
  and `defer` at 6.6.7). The diverts are one predicate now (`_tc_must_divert`, parse_fn.cyr), so a new obligation is a
  new line THERE; grep the tail path for the SHAPE of any new `PARSE_FNCALL`-resident transformation.
  `EDEFER_SAVE` / `EDEFER_RESTORE` must preserve every return register of every return convention (x86: rax, rdx, r8,
  xmm0, xmm1; aarch64: x0–x3, q0, q1; cx: r0–r5) — a new return class that adds a register adds it there.
- **A filing's target list is a report about what the reporter builds, not about the bug.** Reproduce on every host
  that shares the path before scoping the fix (the v6.6.1 DCE issue said "PE only" while x86 Mach-O crashed on ach).
- **An all-identical codegen differential is evidence of a corpus blind spot**, not that a fix is inert: when a fix
  measures 0 diffs, add the shape to the corpus in the same release.
- **A "found by ports" test beats the gate that says the code compiles**: whenever a slot adds a platform-facing verb,
  the `tests/tcyr/crossos/` file is the deliverable.
- **A gate fixture in the wrong order is a vacuous gate**, and a fixture that shares the implementation's assumption
  proves nothing: mutation-prove the gate and check the mutation is reachable.
- **The FREED compiler-state scalar holes are a policy, not a work item**: the next new compiler-state scalar goes into
  a hole (`grep -n FREED src/main.cyr`), not a new slot in the band.
- **Re-derive every count in this file at each release** — a number in a roadmap has nothing checking it.
