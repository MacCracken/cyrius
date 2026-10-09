# Cyrius — Claude Code Instructions

## Project Identity

**Cyrius** — Sovereign, self-hosting systems language. Assembly up.

- **Type**: Self-hosting compiler toolchain
- **License**: GPL-3.0-only
- **Version**: 6.7.6

## Goal

Own the language. Own the toolchain. No crates.io. No external governance. Assembly is the cornerstone. Cyrius writes the AGNOS kernel.

## Where things live

This file is **rules, process and procedures only** — no state, no history. State and history have their own homes:

- [`docs/development/state.md`](docs/development/state.md) — volatile state: version, sizes, gate results, corpus counts,
  in-flight work, the next security-ledger id, the user's open decisions, the verification hosts' last result.
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — the active minor (remaining features, break candidates,
  folded-stdlib follow-ups, the unscheduled backlog); [`roadmap_6.md`](docs/development/roadmap_6.md) — work placed after
  it; [`roadmap-future.md`](docs/development/roadmap-future.md) — the watching list.
- [`CHANGELOG.md`](CHANGELOG.md) — the source of truth for what shipped, with the user's decisions;
  [`completed-phases.md`](docs/development/completed-phases.md) — one line per release.
- [`cycle-discipline.md`](docs/development/cycle-discipline.md) — the runnable closeout checklist + per-closeout ledger.
- [`ecosystem-migration.md`](docs/development/ecosystem-migration.md) — what a consumer meets at its pin bump.
- [`dev-tools-linux.md`](docs/development/dev-tools-linux.md) — the dev-box toolchain (qemu-user, wine, llvm-objdump, SSH).
- [`docs/doc-health.md`](docs/doc-health.md) — the doc-currency ledger (fresh / stale / archived per file).
- `docs/guides/cyrius-guide.md` — the language reference. `../vidya/content/cyrius/` — vidya (language entries, compiler
  and language field notes, gotchas). `docs/adr/` — the decisions.

## Quick Start

```bash
sh bootstrap/bootstrap.sh          # bootstrap from seed
cat src/main.cyr | build/cycc > /tmp/cycc && chmod +x /tmp/cycc  # build compiler
cat src/main.cyr | /tmp/cycc > /tmp/cc5b && cmp /tmp/cycc /tmp/cc5b  # self-hosting verify
sh scripts/check.sh                # full audit
cyrius test                        # the whole .tcyr corpus (recursive)
cyrius test <file|dir>...          # files, and directories walked recursively
cyrius fuzz                        # .fcyr harnesses (recursive)
cyrius bench                       # .bcyr benchmarks (recursive)
```

This repo's `cyrius.cyml` sets `[build] test_standalone = true`: each test compiles with only its own includes.

## Key Principles

- ⛔⛔ **DO NOT ACTIVELY REVIEW CONSUMERS, UNLESS IT IS A REPORTED ISSUE** (user, 2026-10-08 — "ONE LAST TIME").
  Other than the folded stdlibs (what `lib/` vendors), a cyrius session never opens, greps, surveys, diffs or writes
  notes into another repo: no pin-move notes, no sibling follow-up filings, no "which consumers does this touch"
  scans. The ONLY consumer work is a bug a consumer FILED against cyrius (`docs/development/issues/`) — cyrius's own
  bug, fixed in cyrius. No language fixes its consumers: a consumer meets a change when IT bumps its pin and reads the
  CHANGELOG / `ecosystem-migration.md`. Consumer work never sits in cyrius's roadmap — it lives in that consumer's own
  roadmap. **agnos is a consumer**, not a stdlib.
- **Self-hosting is non-negotiable** — cycc == cycc byte-identical after every compiler change.
- **Cross-OS self-host is non-negotiable, on REAL hardware.** "Self-hosting" means cycc reproduces itself byte-identical
  on every target it claims: after ANY compiler-backend or stdlib change, verify on **ecb** (macOS arm64), **ach**
  (Intel Mac), **cass** (Windows PE) and **pi** (aarch64) — one `ssh` away each. **A green CI checkmark is NOT
  verification**: the macOS self-host rotted for ~9 minors behind a CI job that only ran hello-world. The compiler
  self-hosting on the target IS the test.
- **Two-step bootstrap for heap changes** — cycc compiles cc5b, cycc == cc5b.
- **Never use raw `cat | cycc` for projects** — invoke `cyrius build`, which resolves deps, prepends the manifest's
  includes, handles cross-arch and strict flags, names outputs consistently, and writes the `#@incdir` marker that makes
  `include` resolve relative to the entry file. Raw `cat | cycc` is for the compiler's own self-host (the verifier and
  the bootstrap chain) only.
- **Assembly is the cornerstone** — understand every instruction the compiler emits.
- **Test after EVERY change. ONE change at a time. Research before implementation** — a vidya entry before code.
- **When stuck, ASK the user** — never decide to defer, slip, re-slot or split work mid-execution. Splits are planned
  before starting; a reactive scope change is deferment. Report findings and wait
  ([*Micro-Work and Agent Deferment*](https://github.com/MacCracken/agnosticos/blob/main/docs/articles/micro-work-and-agent-deferment.md)).
- **Bootstrap chain integrity** — never break seed (asm) → cybs → cycc.
- **Version lives in `VERSION` + `--version`, never in binary names.** `cybs` (bootstrap) and `cycc` (top compiler) are
  the names forever: no version digit in any binary name (compiler, bootstrap, linker, formatter, anything).

## Release & Slot Discipline

- **Do NOT pre-write `VERSION`.** Run `sh scripts/version-bump.sh <new>` and let it write `VERSION`: it rewrites
  `CLAUDE.md`'s version line, `cyrius.cyml`'s self-pin, the CHANGELOG header and the roadmap stamp only on a version
  CHANGE, so a hand-written `VERSION` silently skips all of them.
- **Atomic commits, packed releases** — two granularities, never conflated. A commit is one logical change (a bite); a
  release (`.NN`) bundles many bites into one coherent unit with a multi-bullet CHANGELOG entry.
  1. **A bug ships complete.** However nasty it turns out, fix it fully in one release — never slice off the hard half.
  2. **Arcs are 1–2 releases**, their phases landing as bites inside them — not one thin release per phase.
  3. **Once a roadmap is agreed, execute it.** Request a split only on a TRULY HIGH need, never reactively.
  4. **Only the user pivots focus.** Re-scoping and re-prioritizing are the user's call exclusively.
  5. **See the whole shape first** — for cross-OS / compiler work, run it on the hardware at slot one.
  6. **Benchmark EVERY release** — `sh scripts/bench-history.sh` on a quiet box, before `version-bump.sh`; record
     self_compile ms + cycc size in the CHANGELOG. A perf delta is growth tax by default; bisect only when one patch
     dominates.
- **Releases are strictly sequential.** Parallel git-worktree lanes exist only for bites INSIDE the current release.
- **Never offer to ship a release without one of its primary asks** — say what it waits on and keep working.
- **Version bumps happen only when a release ships**; a failed or in-flight release is re-cut at the SAME version. The
  agent runs `version-bump.sh` and refreshes `state.md` at slot close; the user pushes and tags.
- **The agent commits bites; the user pushes and tags.** Never push, never tag.

## P(-1): Project Hardening

Before new work on a release: (1) cleanliness — `cyrius fmt --check`, `cyrius lint`, `cyrius vet`; (2) test sweep — all
`.tcyr` pass, heap audit clean, self-host verified; (3) benchmark baseline; (4) audit for stale code, dead paths and
optimization openings; (5) refactor; (6) post-audit benchmarks; (7) document — CHANGELOG, roadmap, vidya.

## Release Gate — `sh scripts/release-gate.sh` GREEN before EVERY `.NN` tag

The single consolidated pre-tag check, so no gate is run à la carte and skipped. Fail-fast:

1. **Self-host fixpoint** — `build/cycc` reproduces itself AND equals `cycc(src)`.
   **1b. ARM binary lockstep** — the tracked `build/cycc-native-aarch64` equals what this tree cross-builds (regenerate
   with `cyrius pulsar`).
2. **Seed derive** — `seed → cybs → cycc` byte-identical. **The most important test**, and mandatory for ANY `src/`
   change on EVERY release: the cycc fixpoint does NOT cover it. cybs (the hand-assembly bootstrap compiler the 29 KB
   seed assembles) is far more limited than cycc and has failed SILENTLY on code cycc compiles; the seed itself has
   input and label caps (gate row S of `cybs_call_arity_named.sh` guards `bootstrap/cybs.cyr`'s headroom). gen1 (cybs's
   output) differing in SIZE from `build/cycc` is normal — only `gen2 == build/cycc` matters.
3. **check.sh** — every gate green.
4. **Cross-OS self-host** — ecb · ach · cass · pi on REAL hardware (`SELFHOST_OK` + the `tests/tcyr/crossos/` suite).
5. **Bench** — self_compile + cycc size into the CHANGELOG (non-blocking).

`version-bump.sh` also runs the seed-derive gate after its rebuild (`CYRIUS_SKIP_SEED_GATE=1` only for a known doc /
lib-only bump). `release-gate.sh --quick` runs 1–3 (iteration, NOT release-ready). **NEVER tag with the gate RED —
losing the seed costs days of repair.**

## Closeout Pass (before every minor/major bump)

Run before tagging `x.Y.0` / `x.0.0`, shipped as the last patch of the current minor. The runnable checklist and the
ledger to record each run are in [`cycle-discipline.md`](docs/development/cycle-discipline.md).

> ⛔ **A closeout is THIS CHECKLIST, not an audit campaign** (user, 2026-10-07 — 6.6.20 took ~38 hours and half a
> weekly budget for an hours-long job). One light pass per item; fix what packs trivially into the closeout patch; the
> rest goes to the backlog for the USER to place. **At most ONE review round per change** — read the sibling paths and
> run the gates BEFORE committing, so a fix never needs review → fix → re-review. No approval-gated Workflow / Agent
> launches mid-release; ultracode is not licence to widen scope. When the scope question is real ("the audit found N
> things — fix all, some, or file them?"), ask it ONCE, up front. A "handoff" means updating `state.md`, only when
> asked — never a handoff file.

**Mechanical — this IS `scripts/release-gate.sh`:** 1 self-host · 2 seed-derive · 3 check.sh (record the count) ·
3b cross-OS self-host on ecb / ach / cass / pi — a minor does NOT close with macOS / Windows self-host unverified.

**Judgment passes (where bugs hide):**
4. **Heap map** — newly added regions documented, sized and at stable offsets; unused regions removed; regions that hit
   caps grown before they bite; adjacent same-subsystem regions consolidated.
5. **Dead code** — remove unreachable fns; record the remaining floor (cycc's `note: N unreachable fns`) in the CHANGELOG.
6. **Refactor** — the 2–3 consolidations the minor earned (parallel `_TARGET_X` branches, enum variants, heap regions,
   codepaths that can collapse into one switch or a common emitter). Not a rewrite.
7. **Code review** — walk the minor's diffs for ABI leaks (x86 encodings on non-x86 paths, SysV on Win64), missed
   `_TARGET_PE` guards, byte-order typos in hand-rolled hex, silently ignored errors, off-by-ones in fixup arithmetic.
8. **Cleanup** — stale comments (old version refs, outdated TODOs, renamed fns), dead `#ifdef` branches, unused
   includes, orphaned files in `build/` / `tests/`.

**Compliance:**
9. **Security re-scan** — a quick grep of the attack surfaces below for new `sys_system`, `READFILE`, unchecked writes;
   a full audit every 2–3 minors. A ledger id is for an ACTUAL security vulnerability only (see below).
10. **Folds** — each folded stdlib's latest tag equals its `docs/ecosystem.md` row and `lib/` is byte-identical to it.
    Consumers are never surveyed (top rule).

**Docs (silent-rot prevention):**
11. **CHANGELOG / roadmap / vidya sync.** Vidya falls out of sync silently — refresh it per minor:
    `vidya/content/cyrius/language/` (new syntax / builtins / directives; changed behaviour; the overview entry's
    compiler size, binary name and version), `field_notes/compiler/` (one entry per surprise or gotcha of the minor),
    `field_notes/language/` (user-facing gotchas), `types.cyml` (version refs, heap map, fixup table, caps, IR opcode
    count, backend modules), `dependencies.cyml` / `ecosystem.cyml` (fold versions). Every vidya file citing a `cc?`
    version must match `VERSION` — `version-bump.sh` does not touch vidya.
12. **Backlog re-triage** — sweep `docs/development/issues/` + `proposals/` and re-pin the roadmap. Verify each item's
    status against LIVE code and the CHANGELOG, never the file's own claim. Archive the resolved; batch the rest by
    theme and dependency (finish-out items soonest). **Nothing codegen is EVER parked at 7.x** — 7.x is the language
    book + legal-for-public-release only; every technical item lives in the 6.x line or roadmap.md's backlog. Delete
    stale-shipped watching entries. Keep the open issue dir lean (~10–12).

Order matters: mechanical first (if self-host breaks, stop), then judgment, then docs, so the docs reflect what the
judgment passes changed. A closeout refactor lands in the closeout only if it stays byte-identical; otherwise it is the
next minor's first patch.

## Security Audit Process

> ⛔ **A ledger id (`CYRIUS-YYYY-NNNN`) is reserved for an ACTUAL SECURITY VULNERABILITY — everything else is a BUG in
> `docs/development/issues/`** (user, 2026-10-08). A finding is a vulnerability only when **an attacker who does not
> already control the victim's own code, build or chosen dependencies** can cross a boundary to cause code execution,
> memory corruption, an authentication / authorization bypass, disclosure of a secret, tampering with a trusted
> artifact, or a denial of service from a remote or unprivileged position. **Name the attacker and the boundary in one
> line, or it gets no id.** Bugs, however severe, get no id: a miscompile, table overflow or accepted bad syntax on the
> developer's OWN source (the compiler is not a sandbox for untrusted source); a `private` / visibility defeat; a leak;
> manifest / resolver / dev-workflow behaviour driven by manifests, repos and directories the developer chose (a
> dependency already runs its code in your build — and restricting local `path` dev work is the wrong fix: "NOT A
> SECURITY ISSUE AND NEVER WAS"); the project's own dev / CI scripts; a crash on the developer's own input. Never write
> "security-relevant" on one of those. Ids are the project's own (never a self-minted `CVE-…`, never a GitHub advisory
> or a CNA request); the ledger is an internal record. Its path and the next free id are in `state.md`; the commit that
> spends an id moves both.

1. **Map the attack surface** — where attacker-controlled input reaches cyrius code:
   - **Network peers / on-path attackers:** the TLS stacks (native and libssl: chain, hostname, EKU, client-certificate
     and signature verification; record and handshake parsing), `lib/net.cyr` / `http` / `ws` / sandhi (peer-chosen
     lengths and allocations, deadlines, a peer killing the process), DNS answers.
   - **Other local users:** predictable shared `/tmp` names, files written or executed from shared or world-writable
     places, permissions, plantable drive-relative rooted paths on Windows.
   - **The release / download channel:** release signatures and their verification, the installer, pinned tags and the
     lock's commit pins, the seed → cybs → cycc trust chain.
   - **Privilege and authentication helpers:** `lib/pam.cyr`, setuid-relevant paths.
   - **Secrets in memory:** key material, nonces, shared secrets left in memory or dead stack — hardening (an issue, no
     id) unless the secret actually reaches an attacker (a measurable timing channel, a buffer on the wire).
2. **Scan** those surfaces — `sys_system()` / `sys_execve()` and shell lines built from attacker data; network-taken
   lengths; verification paths that fail open; temp-file creation; signature and pin checks.
3. **Report** in `docs/audit/{date}-security-audit.md` and the ledger: each vulnerability gets the next id with severity
   (P0–P3), attacker, boundary, file, vector, impact and fix; everything else is filed as a bug.
4. **Fix** — P0: an immediate patch release · P1: the current minor · P2: the next minor · P3: tracked.
5. **Verify** — a regression test for each fix; re-audit the affected area.

## Development Loop

```
1. RESEARCH    — Check vidya for existing patterns
2. BUILD       — ONE change at a time
3. TEST        — After EACH change:
                 ☐ Basic: 'var x = 42;' → 42
                 ☐ Self-hosting: cycc==cycc byte-identical
                 ☐ SEED (any src/ change): sh scripts/seed-derive-cycc.sh
                 ☐ Full suite: sh scripts/check.sh
4. IF BROKEN   — Revert, apply ONE change, test, repeat. If stuck, STOP and ASK.
5. AUDIT/GATE  — sh scripts/release-gate.sh GREEN before version-bump + tag
6. DOCUMENT    — CHANGELOG, roadmap, benchmarks, vidya
```

## Project Structure

```
bootstrap/       the 29 KB seed + cybs.cyr + asm.cyr
src/             main.cyr + the per-target forks (main_aarch64{,_macho,_native}.cyr, main_win.cyr,
                 main_x86_macho.cyr, main_cx.cyr) + version_str.cyr (generated)
  frontend/      lex, lex_pp, parse + the parse_* split; frontend/ts/ — the TypeScript front end
  backend/       x86/ (emit, jump, fixup, decode, float = SSE/AVX + all SIMD), aarch64/, macho/, pe/,
                 cx/ (bytecode; runner programs/cxvm.cyr), js/ (TS → JS), common/ (runtime, tokens, env —
                 shared by every fork; never re-fork them)
  common/        util, ir, syscall_xlat (AUTO-GENERATED by programs/gen_syscall_xlat.cyr — never hand-edit)
lib/             the standard library, incl. the folded stdlibs (docs/ecosystem.md)
programs/        tools, demos, port probes; checks/ (the check.sh driver); cyrius-init-templates/
cbt/             the `cyrius` CLI
tests/tcyr/<bucket>/   .tcyr in topical buckets; ⭐ crossos/ is the set the release gate runs on ecb/ach/cass/pi
tests/gates/<bucket>/  the shell gates (some registered in programs/checks/main.cyr, the rest driven from check.sh)
tests/               fixtures/, data/, scyr/, smcyr/, win/
benches/  fuzz/  docs/
build/           generated; tracked: cycc (the current compiler — CI / install bootstrap from it), cc5 (the
                 prior-major compiler, a break-glass reference, not in the bootstrap chain),
                 cycc-native-aarch64 (the one cross-bin that cannot be regenerated without ARM hardware —
                 built by `cyrius pulsar`, kept in lockstep by release-gate step 1b)
```

⛔ **Every reader of the tests tree is RECURSIVE and every gate carries a corpus FLOOR.** A flat `tests/tcyr/*.tcyr`
glob matches nothing and used to pass SILENTLY (cycc on empty stdin exits 0 and emits a runnable binary). Never
reintroduce one; derive counts (`find tests/gates -name '*.sh' | wc -l`), never quote them.

## Working Agreements

### Execution integrity
- **What valid cyrius MEANS is the user's decision** — never an agent "default", never "other languages do X". A fix
  that changes what yesterday's program does, or makes it stop compiling (binding rules, implicit address-of, reserved
  names, call semantics, preprocessor limits), is a language change: ask in ONE line first, justified from cyrius's own
  guide / vidya / ADRs. A compiler failing VALID cyrius is a codegen bug: fix it.
- **The user is the maintainer.** "Needs a maintainer decision" is deferral to nobody: take the sensible default and
  act, or ask in one line that turn.
- **A filed repro is the spec** — the reporter's verbatim case must pass; never edit it to fit the fix. A filing
  enumerates the full surface needed: shipping a subset labelled "hardening" is a silent deferral.
- **Never misrepresent build / trust state** ("works from the seed", "chain intact") — say plainly how it works.
- **An audit's output is fixes, not a backlog.** If the fix packs into the patch you are writing, fix it — filing costs
  about the same and hands back a bigger queue. File only when it genuinely cannot pack, and name why: a heap / brk
  LAYOUT change (two-step bootstrap), a decision that is the user's, or a full gate cycle the release cannot absorb.
  "Different subsystem" and "it's P2" are not reasons.
- **Fixing bugs is not hunting bugs.** One implementer + one reviewer per bite, reviewing THE BITE; an out-of-scope find
  goes to the backlog (only the user promotes it); a severe one met in passing is reported in one line, not swept for.
- **Deferral is real only when FILED** (its own issue, that turn) AND pinned to a roadmap slot with acceptance criteria;
  then move on. **"File the issue" means file only** — never bundle an implementation with it.
- **Read the actual code before concluding something blocks work.** Premise-check the CLAIMS in issue files, not just
  their pins — a filing's "verified" is a verdict, not evidence.
- **When a gate blocks a legitimate feature, fix the gate.** "Push X back" means ship it, then pivot — not revert.
- **Stay inside the asked scope.** A rejected tool call may have partly run: verify and revert.
- **Never declare a tool absent or a failure "environmental" without looking** (check more than `$PATH`).

### Verification habits (beyond the Release Gate)
- **LOOK at live artifacts; don't parrot verdicts** — run the binary on the host yourself.
- check.sh's summary can mask `.tcyr` segfaults and exit-code failures — run a per-file exit-code loop before claiming
  green. **A check that shares a defect with what it checks reads GREEN.**
- **Never edit the tree while check.sh or release-gate runs** — gates rebuild from the tree. **Wait on a PID**
  (`kill -0 $PID` loops), never `pgrep -f` / `pkill -f` a pattern (it matches the waiting shell itself).
- CI shell-loop gates (SKIP / XFAIL) must be tested under `bash -eo pipefail` — `var=$(failing_cmd)` trips `set -e`.
- The cross-OS leg runs only `tests/tcyr/crossos/`; reproduce aarch64 failures locally with `qemu-aarch64`.
  `cross-os-selfhost.sh` is safe to run concurrently; the release gate runs the four legs beside check.sh
  (`CYRIUS_GATE_SERIAL=1` for the old walk); check.sh runs in parallel (`CYRIUS_CHECK_JOBS`; `# check: serial` marks a
  timing gate that runs alone).
- **cass (Windows)**: Defender ML quarantines the unsigned `cycc.exe` (0-byte output / "cannot execute" that LOOKS like a
  compiler bug) — run under the excluded `C:\cyrius-tests`, check `Get-MpThreat`. `cmd /c "prog & echo %errorlevel%"`
  falsely reports 0 (use `cmd /v /c … !errorlevel!` or a `.bat`). `prog < in > out 2>nul &` corrupts the redirect — use
  `2> err & exit`. Wrap multi-host SSH chains in `if … else exit 1`, never a bare `&&` chain under `set -e`.
- A helper that compiles is not a helper that works — verify new helpers end to end before commit.
- A gate that cannot run (a missing sibling checkout, an unreachable host) says so BY NAME — never a silent SKIP read
  as coverage.
- Hardware-only bugs (GPU / COM, no debugger): exit-code probes over SSH.
- Logic-preserving refactors are proven by byte-identical self-host + a differential corpus (refresh stale includes
  first). An all-identical differential on a real fix means a corpus blind spot — add the shape.
- Clean up test artifacts: local probes AND binaries copied to cass / ecb / pi.

### Planning & slots
- **Premise-check at slot entry** — empirically test that the gap still exists; check against the UPSTREAM source
  (`~/Repos/<fold>/src`), never the vendored `lib/` copy.
- **Scope arcs at planning time** (grep the sites, set phase boundaries); a mid-execution "we should split this" is
  suspect — only clearing a genuine prerequisite bug is a legit mid-execution move.
- Roadmap the WHOLE arc; cross-check roadmap_6 / roadmap-future / issues so nothing dangles. Roadmap prose like "needs
  coordination" is a self-instruction — execute it when the slot opens.
- Priority runs bottom-to-top: baseOS / kernel blockers (when filed) before library / application wins.
- Non-blocking cosmetic / tooling fixes fold into adjacent work — no dedicated slots. Minor-open and closeout slots
  carry real code, not just docs.
- Don't pin patch-count windows; the user states the size at each arc open. **Large minors (~45–99 releases) are the
  norm — never propose a theme-per-minor.**

### Communication
- **Decide with sensible defaults and act** — surface at most ONE genuine fork, rarely. When the user picks, GET MOVING.
- "continue" / "free to continue" = skip the recap and work. No end-of-turn /schedule pitches.
- No hand-wave recommendations — push back with specifics when a proposal is vague.
- **Lead with release-ordering constraints**: a fold pinned to an unreleased cyrius gets "⛔ do not push / tag until
  cyrius X is out" as its FIRST line, never a parenthetical.

### Ecosystem & stdlib
- The folded stdlibs (sigil, sakshi, bayan, ganita, …, listed in `docs/ecosystem.md`) are the language's OWN stdlib,
  never "external upstream": what ships into `lib/` IS stdlib, with full stdlib discipline. Only a fold can gate a cyrius
  release; every other repo is a consumer (top rule).
- **Fix the SOURCE repo, not the fold** — a fix only in the vendored `lib/<fold>.cyr` evaporates at the next re-vendor:
  patch upstream, release it, regenerate its dist, re-vendor byte-identical. A fold release is a PATCH unless the user
  says otherwise. A fold's CI runs isolated (a clean `git archive` copy, throwaway `HOME` + `CYRIUS_HOME`, GitHub's shell
  semantics) — never by hand-extracted steps.
- A fold wave is planned whole at its open — dependency order, the fold API cyrius's own `lib/` calls — one plan, not
  drip.
- A bug a consumer FILES against cyrius is cyrius's bug: fix it (the repro is the spec). A consumer never gets an ORDER
  — a say in a release's sequencing, gates or scope. Adopting a fix is the reporter's job.
- Removing a public stdlib symbol is the user's call; `removed_symbol_census.sh` forces the accounting in
  `docs/retired-symbols.allow`.
- A sibling repo's agent editing cyrius source is a hard violation, however correct — revert it and file an issue.
- Ecosystem-wide renames cover ALL source extensions, not just `.cyr` / `.tcyr`.
- `lib/` modules are self-sufficient: a file that uses a flag constant (`O_WRONLY`, `MAP_PRIVATE`, …) includes its
  definer.
- **Sovereignty**: no Python / bash / C as a shipped deliverable; every bootstrap rung enlarges the trusted base —
  minimize rungs.
- DCE-"dead" fns may be external API (`--lex-ts`, cyrdoc, consumers) — check before removing.
- `cbt/cyrius.cyr` (the CLI) cross-compiles to PE / Mach-O: guard Linux-syscall includes with `#ifdef` + early return.

### Docs & issues hygiene
- The CHANGELOG is canonical history; `state.md` is volatile state only; this file is rules only.
- **Archive docs, don't delete** — and grep `.github/workflows/`, `scripts/` and `tests/gates/` for hard-coded paths
  first.
- Issues archive to `docs/development/issues/archived/` at slot close; keep the open dir a lean working queue (~10–12)
  and fold the P3 / "someday" tail into roadmap entries.
- Audit a corpus (vidya gotchas, the backlog) by DISSOLVING repeated instances into their class, not appending.
- Source comments keep the WHY plus a one-line `CHANGELOG [X.Y.Z]` pointer — not history blocks.

## Language & test conventions

- **When the compiler cannot compile valid cyrius, fix the compiler.** Never write a codegen bug down as a language rule
  ("≤ 6 args" was a Win64 codegen bug in disguise for a year). If a rule here tells you to work around codegen, the rule
  is the bug report. fns take any number of arguments.
- **`var x[N]` local = N BYTES** (rounded to 8), not N slots — use `var a: i64[N]` for slots. Bare top-level arrays are
  N × 8.
- **Reserved words are a CLASS** — `IS_KEYWORD_TOK` (`src/common/util.cyr`): `TOKNAME_BUILTIN`'s builtins, the
  hand-listed builtins and statement keywords, plus intrinsics recognised by name (`sizeof`, `mulh64`, `fncall0..8`).
  The parser names the one you hit. Read the tables and DERIVE the count — never quote one. `loop` and `kernel` are
  contextual. The hand-listed halves can drift from `TOKNAME`; a tool deriving the reserved set must read all four
  sources (as `[embed]`'s list does).
- `.tcyr` files end `var r = assert_summary();` (or an explicit exit) so success exits 0. Name tests topically, never
  temporally ("pass2", "v3").
- **cyrfmt continuation indent is a formatter contract**: 2 spaces per open paren level (canonical); 4 is accepted by
  `--check`; deeper is rejected. `cyrius fmt <file>` rewrites in place, `--dry` reports, `--check` exits 1 naming the
  line.
- **aarch64 syscall numbers**: a stdlib number that collides with an x86 number in ESYSXLAT is silently mis-remapped —
  use the x86 number + an ESYSXLAT entry. When both candidates are owned, use the private alias band: numbers ≥ 1000
  are cyrius-private, spelled `1000 + the native number` (see the comment above `SYS_FCHOWNAT` in
  `lib/syscalls_aarch64_linux.cyr`). ⚠ The aarch64-Linux arm stays LAST in its ESYSXLAT chain.
- **A wrapper that compiles on five targets is not a wrapper that runs.** Every new syscall wrapper needs a companion
  test in `tests/tcyr/crossos/` — the directory is the selector the cross-OS leg runs.
- Restoring a config, restore only what was there — no unrequested "sensible defaults".

## DO NOT

- **Push or tag** — the user does (the agent commits bites).
- **Use the `gh` CLI** — use `curl` against the GitHub API.
- Add language features without updating vidya, or skip self-host verification after a compiler change.
- Modify `parse.cyr`'s arch-specific functions — they live in the emit files.
- Remove `build/cycc-native-aarch64` — ARM self-host needs it (`cyrius pulsar` regenerates it).
- Write into `~/.cyrius/deps` — it is resolver-owned; hand-staged content makes `cyrius deps` skip git and drop the
  commit pin.

## Downstream repo setup (`lib/` is never a symlink)

A repo populates `lib/` with `cyrius deps` — never by symlinking `lib/`, or any `lib/<dep>.cyr`, to this repo or to
`~/.cyrius`. A write that follows the link (format, lint, a dead-code pass, a re-vendor) lands in the target — that is
how `dynlib_*` was deleted from this repo's `lib/fdlopen.cyr` four times, and how `cyrius deps` once overwrote the
shared stdlib at exit 0. Both shapes (directory and file) are refused (`_dep_dest_is_linked`;
`tests/gates/toolchain/deps_symlinked_lib_refused.sh`). Investigating spontaneous `lib/` corruption:

```sh
find /home/macro/Repos -maxdepth 3 -type l -lname "*cyrius/lib*" 2>/dev/null
find ~/.cyrius -type l | xargs -I{} sh -c 'readlink -f "{}" | grep -q "Repos/cyrius" && echo "{} -> $(readlink -f \"{}\")"'
find ~/Repos -maxdepth 2 -type l -name lib  # directory-level lib symlinks (the bad pattern)
```

⚠ A rule that declares one shape of a defect acceptable prevents the fix from covering it — check whether the tool
actually handles a shape before calling it fine.

## The install store is written from TAGS, never from a drifted tree

`~/.cyrius/versions/<v>` is what a consumer pin MEANS: once `<v>` is tagged, that slot must equal the tag.

- `install.sh --refresh-only`, `cyrius pulsar` and `cyrius lsp` REFUSE a released slot when the tree has moved past the
  tag and the destination is live. Tree == tag proceeds; an untagged `VERSION` proceeds (the in-flight bump); a throwaway
  `CYRIUS_HOME` proceeds. `CYRIUS_REFRESH_RELEASED=1` forces it — throwaways only.
- **Re-cutting a version at a new commit**: `git tag -f <v> HEAD` FIRST, then refresh. Never bump to get past the refusal.
- **After EVERY tag, run `sh scripts/install.sh --refresh-only` once at the tagged commit** — the reconciling write
  (`version-bump.sh` refreshes before the bump commit exists).
- `check.sh` stages its own throwaway `CYRIUS_HOME` from the tree, so nothing writes the live store mid-slot. Never copy
  `lib/<f>.cyr` into `~/.cyrius/...` and never run a same-version `version-bump.sh` to "refresh a snapshot" — both are
  the corrupting write.
- Every refresh stamps `versions/<v>/SOURCE_COMMIT`. `sh scripts/verify-store.sh` compares every tagged slot (lib,
  tracked bins, `scripts/cyriusly`, stamp) to its tag; `--restore <v>` rewrites a slot from its tag (⚠ `cycc_win` is the
  PE32+ compiler, `CYRIUS_TARGET_WIN=1`). Run the report at every closeout.
