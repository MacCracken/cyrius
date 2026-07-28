# Cyrius — Claude Code Instructions

## Project Identity

**Cyrius** — Sovereign, self-hosting systems language. Assembly up.

- **Type**: Self-hosting compiler toolchain
- **License**: GPL-3.0-only
- **Version**: 6.4.82

## Goal

Own the language. Own the toolchain. No crates.io. No external governance. Assembly is the cornerstone. Cyrius writes the AGNOS kernel.

## Current State

> Volatile state lives in [`docs/development/state.md`](docs/development/state.md) —
> current version, cycc size, in-flight slots, recent shipped releases,
> consumers, verification hosts, bootstrap chain. Refreshed every release.
> Historical release narrative lives in
> [`docs/development/completed-phases.md`](docs/development/completed-phases.md).

This file (`CLAUDE.md`) is **preferences, process, and procedures** —
durable rules that change rarely, not state that bumps every release.

## Quick Start

```bash
sh bootstrap/bootstrap.sh          # bootstrap from seed
cat src/main.cyr | build/cycc > /tmp/cycc && chmod +x /tmp/cycc  # build compiler
cat src/main.cyr | /tmp/cycc > /tmp/cc5b && cmp /tmp/cycc /tmp/cc5b  # self-hosting verify
sh scripts/check.sh                # full audit
cyrius test                        # run .tcyr suite
cyrius fuzz                        # run .fcyr harnesses
cyrius bench                       # run .bcyr benchmarks
```

## Key Principles

- **Self-hosting is non-negotiable** — cycc==cycc byte-identical after every compiler change
- **Cross-OS self-host is non-negotiable, on REAL hardware** — "self-hosting" means cycc reproduces itself byte-identical on **every target it claims to support**, not just x86_64 Linux. After ANY compiler-backend or stdlib change, verify cycc self-hosts on **ecb (macOS, arm64)** + **ach (Intel-Mac, x86-macho)** + **cass (Windows, PE)** + **pi (aarch64)** via SSH — they're wired in `~/.ssh/config`, one `ssh` away, every slot. **A green CI checkmark is NOT verification.** The macOS compiler self-host rotted silently for ~9 minors (v5.3.13 → v6.0.32, 400+ patches) behind a CI job named "Mach-O ARM64 Native ✓" that only ran hello-world / exit-code programs and never once built or self-hosted `cycc`. It surfaced only when a human installed on a Mac and got a broken toolchain — the exact "found by ports" failure. Hello-world smoke is a placebo; the compiler self-hosting on the target IS the test. Never trust a checkmark over running the compiler on the hardware. See `feedback_macos_windows_ci_gate_mandatory`, `reference_verification_hosts_ssh`, Closeout 3b.
- **Two-step bootstrap for heap changes** — cycc compiles cc5b, cycc==cc5b
- **Never use raw `cat | cycc` for projects** — always invoke `cyrius build`. The CLI wrapper resolves deps, auto-prepends includes from `cyrius.cyml`, handles cross-arch + strict flags, and produces consistent output naming. Raw `cat | cycc` is for compiler-internal self-host (the verifier script + bootstrap chain) — not consumer code.
- **Assembly is the cornerstone** — understand every instruction the compiler emits
- **Test after EVERY change** — not after the feature is "done"
- **ONE change at a time** — never bundle unrelated changes
- **Research before implementation** — vidya entry before code
- **When stuck, ASK the user** — never decide to defer, slip, re-slot, or split work mid-execution. Splits are planned decisions made *before* starting; reactive scope changes when stuck are deferment and count as slipping. Report findings and wait for direction. See [*Micro-Work and Agent Deferment*](https://github.com/MacCracken/agnosticos/blob/main/docs/articles/micro-work-and-agent-deferment.md) for the four-case classification (commit-through / prereq-bug / pre-planned decomposition / the sleight-of-hand to reject).
- **Bootstrap chain integrity** — never break seed (asm) → cybs → cycc. Historical chain: pre-v3.9.5 stage1f → cyrc (v3.9.5) → cybs (v6.0.0); top compiler was cc3 → cc5 (v5.0.0) → cycc (v6.0.0). Bridge intermediate retired at v5.11.66.
- **Version lives in `VERSION` + `--version`, never in binary names** — at v6.0.0 both compiler binaries got descriptive, version-agnostic names: the bootstrap compiler (formerly `cyrc`) is now **`cybs`** (Cyrius Bootstrap) and the top compiler (formerly `cc5`) is now **`cycc`** (Cyrius Computer Compiler). These names are *forever*. No `cycc6` at v7.0.0, no `cybs7` at v8.0.0, no funny business. The cc3 → cc5 rename (v5.0.0) and the cyrc → cybs + cc5 → cycc rename (v6.0.0) sequence was the LAST name-change penalty paid. Anyone tempted to add a version digit to a binary name (compiler, bootstrap, linker, formatter, anything) is reintroducing the bug we explicitly removed. `VERSION` file + binary `--version` output are the only sources of truth.

## Release & Slot Discipline

**Atomic commits, packed releases.** Two different granularities — don't
conflate them (the v6.0.33 mistake):

- **Commits are fine-grained** — one logical change ("bite") per commit:
  clean history, single-thing revertability. Bite freely.
- **Releases (`.NN`) are coarse** — a release bundles MANY bites into one
  coherent unit. The CHANGELOG entry has several bullets, not one.

Rules (user 2026-06-02, 20-yr QA/DevOps direction):

1. **A bug ships complete — no granularity by gnarliness.** However nasty
   a bug turns out to be when investigated, fix it fully in one release.
   NEVER slice one fix to defer the hard half across patches. "Easy part
   now, hard part next slot" is the antipattern, even when each piece
   "works." See `feedback_one_bug_one_complete_fix`.
2. **Arcs are 1–2 releases, not per-phase releases.** A multi-phase arc
   (e.g. TLS 1.3 client) is ONE, maybe two releases, with the phases
   landing as commits/bites INSIDE the release — not 8–9 thin releases.
3. **Once a roadmap is agreed, execute it.** When the user asks for
   roadmapped items and a structure is agreed, build to it. Only request
   a split if there is a TRULY HIGH NEED — not reactively when work grows.
   Stop asking "should this be its own slot?" — that question is the nibble.
4. **Only the user pivots focus.** Re-scoping, re-prioritizing, changing
   what we work on is the user's call EXCLUSIVELY. Surface findings; never
   unilaterally redirect or defer.
5. **See the whole shape first** so the release can be packed
   intentionally. For cross-OS / compiler work that means running it on
   ecb/cass at slot one (the Cross-OS self-host principle), not
   discovering scope layer by layer and reaching for a split each time.
6. **Benchmark EVERY release — non-negotiable, not occasional, not
   CI-only** (user 2026-06-08). Every `.NN` cut runs
   `sh scripts/bench-history.sh` (the 3-tier suite → `BENCHMARKS.md` +
   appends `bench-history.csv`) on a quiet box as part of slot
   completion, alongside the self-host verify — BEFORE `version-bump.sh`.
   Record the headline delta (self_compile ms + cycc size) in the
   CHANGELOG entry. Relying on CI alone, or running it "when we
   remember," is the gap that let the +65 % self_compile growth-tax go
   unnoticed for a whole minor. A perf delta is then triaged per
   [`feedback_perf_deltas_growth_tax_default`] (growth-tax by default;
   bisect only if one patch dominates). The bench run is a release
   gate, not a closeout-only step.

## P(-1): Project Hardening

Before starting new work on a release, run this audit phase:

1. **Cleanliness** — `cyrius fmt --check`, `cyrius lint`, `cyrius vet`
2. **Test sweep** — all .tcyr pass, heap audit clean, self-hosting verified
3. **Benchmark baseline** — `cyrius bench` before changes
4. **Audit** — identify stale code, dead paths, optimization opportunities
5. **Refactor** — address findings from audit
6. **Post-audit benchmarks** — compare against baseline
7. **Document** — update CHANGELOG, roadmap, vidya

## Release Gate — `sh scripts/release-gate.sh` GREEN before EVERY `.NN` tag

**The single consolidated pre-tag check. Run it and get GREEN before
`version-bump.sh` + tag + handoff.** It exists so no individual gate is run à la
carte and skipped — the way the v6.3.0 seed break happened: a compiler change
passed the cycc self-host fixpoint + check.sh + cross-OS, so it *looked* done, but
`seed-derive-cycc.sh` wasn't run (it had only ever been framed as a *closeout*
check), and the change broke the `seed → cybs → cycc` chain. CI caught it, not us.

Gates, fail-fast:
1. **Self-host fixpoint** — `build/cycc` reproduces itself AND == `cycc(src)`.
2. **Seed derive** — `seed → cybs → cycc` byte-identical. **The most important
   test, and the one v6.3.0 missed.** The cycc self-host fixpoint (1) does NOT
   cover it: **cybs** (the hand-assembly bootstrap compiler the 29 KB seed
   assembles) is far more limited than `build/cycc` and fails **SILENTLY** on
   things `build/cycc` compiles fine — too many global/call references in one
   function, tail calls. **Mandatory for ANY `src/` change, on EVERY release — not
   only at minor/major closeouts.** (`gen1`, cybs's output, being ~72 KB smaller
   than `build/cycc` is NORMAL — it's the bootstrap intermediate, only `gen2 ==
   build/cycc` matters; don't chase it.) See
   `feedback_seed_derive_mandatory_cybs_limits`.
3. **check.sh** — all gates green.
4. **Cross-OS self-host** — ecb (macOS-arm64) + ach (Intel-Mac) + cass (Windows) + pi (aarch64), REAL
   hardware, sequential. A green CI check is NOT this.
5. **Bench** — record self_compile + cycc size in the CHANGELOG (non-blocking).

`version-bump.sh` ALSO runs the seed-derive gate after its cycc rebuild — a safety
net on every real `.NN` bump, since version-bump is always run at slot close
(`CYRIUS_SKIP_SEED_GATE=1` only for a known doc/lib-only bump). `release-gate.sh
--quick` runs steps 1-3 (fast local iteration — NOT release-ready). **NEVER tag
with the gate RED. Losing the seed costs days of repair.**

## Closeout Pass (before every minor/major bump)

> **Runnable checklist + per-closeout ledger:** [`docs/development/cycle-discipline.md`](docs/development/cycle-discipline.md) "Closeout checklist + ledger" — tick the boxes there and RECORD the run (gate counts, findings, follow-ups). This section is the durable *spec* (the why behind each step); that doc is what you open, run, and log against each closeout.

Run a closeout pass before tagging x.Y.0 or x.0.0. Ship as the last patch of the current minor (e.g. 4.2.5 before 4.3.0). **Mechanical checks first, then the judgment-call passes (refactor / code review / cleanup), then the doc sync.**

### Mechanical (automated, fast-fail) — this IS `scripts/release-gate.sh` (run it)
1. **Self-host verify** — cycc compiles itself byte-identical
2. **Bootstrap closure (seed-derive)** — `seed → cybs → cycc` byte-identical (`seed-derive-cycc.sh`). NOT covered by the cycc self-host fixpoint — see the Release Gate above; this is item 2 of the gate and is mandatory EVERY release, not just at closeout.
3. **Full check.sh** — all gates green (count grows per minor; record the number)
3b. **Cross-OS self-host (NON-NEGOTIABLE — added v6.0.x after the macOS rot incident)** — cycc must build from the correct per-target source AND **self-host byte-identical on real macOS-arm64 (ecb) + Intel-Mac (ach) + Windows (cass) + aarch64 (pi)**, not just x86_64 Linux. Hello-world/exit-code smoke is NOT self-host — the macOS port rotted v5.3.13→v6.0.31 precisely because the `macho-arm64-native`/`windows-native` CI jobs only ran tiny programs, never the compiler. Verify via the `macos-14`/`windows-latest` CI jobs (once extended to self-host) AND/OR SSH to ecb/ach/cass/pi. (`scripts/release-gate.sh:92` runs all FOUR — `for H in ecb ach cass pi`; ach became a first-class gate at v6.4.59 after the Intel-Mac toolchain rotted ungated for ~2.5 minors, which is the same rot these bullets exist to prevent.) A minor does NOT close with macOS/Windows self-host unverified or red. See [reference: verification hosts, `feedback_macos_windows_ci_gate_mandatory`].

### Judgment-call passes (where bugs hide)
4. **Heap map audit** — beyond "verify the map matches usage", evaluate:
   - Newly-added regions (are they documented, sized correctly, at stable offsets)
   - Unused / stale regions (any region no code writes to → candidate for removal)
   - Regions that hit caps across the minor (grow before they bite)
   - Opportunity for consolidation (adjacent regions owned by the same subsystem)
5. **Dead code audit** — remove unreachable fns; record the remaining floor in CHANGELOG. The `note: N unreachable fns` output from cycc is the baseline.
6. **Refactor pass** — review the minor's additions for consolidation. When a minor added multiple `_TARGET_X` branches / new enum variants / new heap regions / parallel codepaths, check whether the dispatch can collapse into a single switch, whether helpers can merge, whether repeated inline asm blocks want a common emitter. Not about rewriting — about spotting the 2-3 obvious consolidations the minor earned.
7. **Code review pass** — walk the minor's diffs end-to-end. Specifically look for: ABI leaks (unguarded x86 encodings on non-x86 paths, SysV leaks on Win64 paths), missed `_TARGET_PE` guards, byte-order typos in hand-rolled encoding hex literals, silently-ignored errors, off-by-one in fixup arithmetic. The places automated tests don't catch.
8. **Cleanup sweep** — stale comments (grep for old version refs, outdated TODOs, references to renamed fns), dead `#ifdef` branches, unused includes, orphaned files in `build/` / `tests/`.

### Compliance / external
9. **Security re-scan** — quick grep for new `sys_system`, `READFILE`, unchecked writes. Full audit every 2-3 minors. **Last full audit: `docs/audit/2026-07-27-security-audit.md` (CVE-32…CVE-36) at cycc 6.4.82**; the one before it was `docs/audit/2026-06-10-deep-dive-review.md` (…CVE-31) at cycc 6.1.31. *(This line read "last: v5.0.1" until v6.4.82 — three minors stale, which is how the re-scan cadence quietly slipped. The 2026-07-27 pass found three unbounded copies reachable from untrusted source, one of them a `SIGSEGV` from an `include` path.)*
10. **Downstream check** — all `cyrius.cyml` `cyrius` fields across ecosystem repos point to the released tag.

### Docs (silent-rot prevention)
11. **CHANGELOG/roadmap/vidya sync** — all docs reflect current state. Vidya in particular needs explicit refresh per minor (it falls out of sync silently — no compile-time check):
   - **`vidya/content/cyrius/language/`** (directory: `core.cyml`, `features.cyml`, `tooling.cyml`, `stdlib_modules.cyml`, `agents.cyml`, `index.cyml`) — language usage. Add `[[entries]]` blocks for any new syntax / builtins / directives shipped this minor (e.g. `#regalloc`, `secret var`, `#pe_import`, multi-return, struct initializer). Update existing entries when behavior changed (e.g. `&local` arch dispatch, `_cyrius_init` binding flip). Refresh the `overview` entry (in `language/core.cyml` / `index.cyml`) compiler-size + cc-binary-name + version line at every minor.
   - **`vidya/content/cyrius/field_notes/compiler/`** (directory: `methodology.cyml`, `patterns.cyml`, `gotchas.cyml`, `index.cyml` + `retros/`) — compiler internals + non-obvious gotchas. Add field notes for anything that surprised us this minor (e.g. RBP-after-`clone()` race, `FUTEX_PRIVATE_FLAG` mismatch with kernel `CLONE_CHILD_CLEARTID`, parse.cyr unguarded x86-emit paths that shipped silently, `mov rN, rax` byte-order typos that segfault on Windows). One entry per gotcha; future-claude searching vidya before reimplementing should hit them.
   - **`vidya/content/cyrius/field_notes/language/`** (directory: `parser_syntax.cyml`, `semantics_runtime.cyml`, `platform_abi.cyml`, `diagnostics_caps.cyml`, `stdlib_format.cyml`, `shell_runtime.cyml`) — user-facing language gotchas (e.g. no `var` redecl in same scope, no comparisons in fn-call args, parser's `#ifdef`-but-not-`#else`).
   - **`vidya/content/cyrius/types.cyml`** (note: `implementation.toml` is retired — archived at `archive/implementation.cyml`) — bump version refs and any structural changes (heap map, fixup table, fn table caps, IR opcode count, backend modules).
   - **`vidya/content/cyrius/dependencies.cyml`** / **`ecosystem.cyml`** — refresh when deps bump (sigil 3.12.1 → next, etc.) and when downstream consumer counts / test counts change.
   - **Cross-check the version**: every vidya file mentioning a `cc?` version (`cc3 4.8.5`, `cycc 5.4.x`, etc.) should match the current `VERSION` file. `version-bump.sh` doesn't touch vidya — that's manual at closeout.
12. **Backlog re-triage (rot sweep)** — sweep the open `issues/` + `proposals/` queue and re-pin the roadmap. **Verify each item's resolved-status against LIVE code / CHANGELOG — NOT the file's own claim** (a shipped-but-still-framed-as-pending entry is the exact rot: cx sat target-less for a couple majors when it was ready, TS→JS emit shipped v6.1.10 but stayed "minor TBD" in `roadmap-future.md` for months). Archive the resolved (`issues/archived/`, `proposals/archived/`); batch the rest by theme + dependency; re-pin them into an ordered roadmap sequence (arc **finish-out** items soonest, big new arcs after the queue is clean). **Enforce the placement rule: every technical / codegen / runtime item lives in the 6.x line or the `roadmap.md` "potential backlog" — NOTHING codegen is EVER parked to 7.x** (7.x = the language book + legal-for-public-release, that's it). Also re-scan the `roadmap-future.md` "watching" list for stale-shipped entries and mark them SHIPPED. Keep the open dir lean (~10–12). See [`feedback_no_codegen_parking_in_v7`]. (Cheap to run any time on request — "re-triage the backlog" — but MANDATORY at minor/major closeout, when a release burst has piled up drift.)

Order matters: mechanical checks fail-fast (if self-host breaks, stop). Judgment passes uncover scope for a follow-up patch if needed (landing the refactor during closeout is fine IF it stays byte-identical; otherwise defer to the next minor's first patch). Doc sync is last so it reflects whatever the judgment passes changed.

## Security Audit Process

Periodically (before major releases, after significant changes), run a security audit:

1. **Research** — review known vulnerability classes for compilers and build tools:
   - Buffer overflows (fixed-size heap regions, unchecked writes)
   - Command injection (shell commands from user-controlled input)
   - Path traversal (include directives, dep resolution, file writes)
   - Integer overflow (limit checks, table sizes)
   - Race conditions (temp files, concurrent access)
   - Trust chain (seed binary, release signing, dep integrity)
2. **Scan** — static analysis of source for vulnerable patterns:
   - `sys_system()` / `sys_execve()` with user-controlled args
   - `READFILE` / `sys_open` with unvalidated paths
   - `store8`/`store64` without bounds checking near region boundaries
   - Silent overflow on table limits (return instead of error)
   - Predictable temp file paths
3. **Report** — file findings in `docs/audit/{date}-security-audit.md`:
   - Each finding gets a CVE-XX identifier, severity (P0-P3), affected file, vector, impact, fix
   - Action items organized into current and upcoming minor versions
   - Don't move existing roadmap items — add security items alongside
4. **Fix** — prioritize by severity:
   - P0 (Critical): fix in immediate patch release
   - P1 (High): fix in current minor version
   - P2 (Medium): fix in next minor version
   - P3 (Low): track for future
5. **Verify** — regression test each fix, re-audit affected area

## Development Loop

```
1. RESEARCH    — Check vidya for existing patterns
2. BUILD       — ONE change at a time
3. TEST        — After EACH change:
                 ☐ Basic: 'var x = 42;' → 42
                 ☐ Self-hosting: cycc==cycc byte-identical
                 ☐ SEED (any src/ change): sh scripts/seed-derive-cycc.sh
                   — the cycc fixpoint does NOT cover the seed→cybs→cycc chain
                 ☐ Full suite: sh scripts/check.sh
4. IF BROKEN   — Revert, apply ONE change, test, repeat
                 If stuck, STOP and ASK the user — never defer on your own
5. AUDIT/GATE  — sh scripts/release-gate.sh GREEN (self-host + seed-derive +
                 check.sh + cross-OS + bench) before version-bump + tag
6. DOCUMENT    — Update: CHANGELOG, roadmap, benchmarks, vidya
```

## Project Structure

```
bootstrap/           29KB seed binary + cybs.cyr + asm.cyr
src/
  main.cyr           Compiler entry point (includes modules); 7 per-target forks
                     (main.cyr + main_aarch64{,_macho,_native}.cyr, main_win.cyr,
                     main_x86_macho.cyr, main_cx.cyr) + version_str.cyr (generated)
  frontend/          lex.cyr, lex_pp.cyr, parse.cyr + the parse_* split
                     (parse_ctrl/decl/expr/fn/types.cyr)
  backend/x86/       emit.cyr, jump.cyr, fixup.cyr, decode.cyr (length-decoder),
                     float.cyr (SSE/AVX FP + ALL SIMD emitters — the v6.4.x arc)
  backend/aarch64/   emit.cyr, jump.cyr, fixup.cyr
  backend/cx/        emit.cyr (cyrius-x bytecode; runner: programs/cxvm.cyr)
  backend/js/        emit.cyr (TS/TSX → JS, `cycc --emit-js`)
  common/            util.cyr, ir.cyr
lib/                 Standard library (~99 lib/*.cyr modules)
programs/            ~83 program files + subdirs (tools, tests, demos, algorithms)
tests/               Test suites (tcyr/*.tcyr, heapmap.sh)
benches/             Benchmarks (*.bcyr)
fuzz/                Fuzz harnesses (*.fcyr)
build/               Generated binaries (gitignored except `cycc`, `cc5`,
                     `cycc-native-aarch64`). `cycc` is the current-major
                     compiler (the final, forever binary name per `Version
                     lives in VERSION + --version, never in binary names`
                     above); CI / install bootstrap from it. `cc5` is the
                     PRIOR-major compiler — the last v5.x top compiler
                     (5.11.69), renamed to `cycc` at v6.0.0 — kept per the
                     "current + one prior-major" tracking policy as a
                     historical / break-glass reference (NOT in the bootstrap
                     chain). `cycc-native-aarch64` is the ONE cross-bin
                     that's tracked, because it's the only one that can't be
                     regenerated by cross-compiling — ARM hardware self-host
                     needs a binary that already runs on ARM (built via
                     `cyrius pulsar`). The other `cross_bins` in cyrius.cyml
                     (`cycc_aarch64`, `cycc_win`) are rebuilt on demand by
                     CI / install and stay ignored. **cc3 (the v4.x-era seed)
                     was DROPPED at v6.1.0**: at the v6.0.0 cut the
                     prior-major slot should have rotated cc3 → cc5 but
                     didn't, leaving cc3 a stale prior-PRIOR; corrected here.
                     At v7.0.0 the prior-major slot rotates to the last v6.x
                     `cycc` — same binary name, so the slot effectively
                     retires (no more renames to bridge).
docs/                Architecture, roadmap, benchmarks, language guide
```

## Key References

- `docs/guides/cyrius-guide.md` — Complete language reference
- `docs/development/roadmap.md` — **Active minor** (current v6.x.y), slot-by-slot
- `docs/development/roadmap_6.md` — Whole-v6.x-cycle reference (framing, per-minor budgeting, v6.2.x → v6.5.x, the closed v6.0.x summary)
- `docs/development/roadmap-future.md` — Long-term watching list (unpinned items, speculative work, v7.0+ aspirations)
- `docs/development/cycle-discipline.md` — Evergreen operating principles (slot acceptance, bottom-to-top priority, premise-check, cross-host smoke, cycle-close shape) **+ the runnable Closeout checklist + per-closeout ledger** (the doc you open/run/record against at every minor/major bump)
- `docs/development/state.md` — Volatile cycle / pin / sweep state (refreshed every release)
- `docs/development/dev-tools-linux.md` — per-environment dev toolchain (Linux x86_64 first; `qemu-user`/`wine` to reproduce aarch64/PE self-host bugs locally, `llvm-objdump` disasm, SSH cross-host verify). macOS/Windows siblings to follow. Install these before cross-target codegen work.
- `docs/doc-health.md` — Living doc-currency ledger (per-tier fresh / stale / archived; refreshed when docs are touched)
- `CHANGELOG.md` — Source of truth for all changes
- `../vidya/content/cyrius/*.cyml` (+ the `language/` and `field_notes/{compiler,language}/` subdirs) — 90+ cyrius vidya entries

## Working Agreements (distilled 2026-07-07 from session-feedback memory)

Durable rules from user feedback across v5.x–v6.4.x, consolidated here from
per-session memory files so they survive environment changes.

### Execution integrity
- **A filed repro is the spec** — the user-reported verbatim test case must pass. Never edit a consumer repro to fit the fix; never substitute an easier task for the hard one ("a bug before a feature" is only legit as a genuine prerequisite).
- **A consumer filing enumerates the FULL surface they need** — shipping a subset labeled "hardening"/"tightening" is a silent deferral.
- **Never misrepresent build/trust state** ("works from the seed", "chain intact") — state plainly how it actually works.
- **AN AUDIT'S OUTPUT IS FIXES, NOT A BACKLOG** (user 2026-07-27, angry and right). Nowhere in the closeout procedure or the audit process does it say "just document it". If you found it and the fix packs into the patch you are already writing, **fix it** — filing it instead converts work into someone else's work. Writing an issue up properly costs about the same as fixing it, so filing-when-you-could-fix is the *more expensive* choice, and it hands back a bigger queue than you started with. The v6.4.81 tell: an audit shipped 4 fixes and grew the open queue 11 → 15; three of those four were two-line changes.
  **File only when the fix genuinely cannot be packed into this patch** — and name the reason: it needs a heap/brk **layout** change (⇒ two-step bootstrap), a design decision that is the user's, cross-repo coordination, or a full gate cycle the release cannot absorb. "It's a different subsystem", "it's P2", "it's out of scope for this release" are NOT reasons. A scope line the user drew around *shipping* (e.g. ".81 = the fixes") is not licence to file everything else — it bounds the release, not the fixing.
- **Deferral is real only when FILED** (its own issue, that turn — not buried in prose) AND pinned to a roadmap slot with acceptance criteria. Once documented-and-deferred, MOVE ON — don't re-investigate it every slot.
- **Read the actual code before concluding something blocks work**; don't raise a blast-radius alarm from a crude scan and reach for a defer — verify precisely, then FINISH the fix.
- **When a gate blocks a legitimate feature, fix the gate** — never drop the feature.
- "Push X back" means ship it then pivot — NOT revert.
- Cross-repo smokes naming a repo missing from `~/Repos` must surface the gap to the user, not silently skip.

### Verification habits (beyond the Release Gate)
- **LOOK at live artifacts, don't parrot verdicts** — docs/pins/issues go stale in a fast-moving project; run the binary on the host yourself.
- check.sh's grep summary masks tcyr segfaults/exit-code failures — run a per-file exit-code loop before claiming green.
- **CI shell-loop gates (SKIP/XFAIL) must be tested under `bash -eo pipefail`** — `var=$(failing_cmd)` trips `set -e` before the bookkeeping. The release gate's cross-OS step runs only the `vr01_` glob; reproduce full-corpus aarch64 failures locally with `qemu-aarch64`.
- **cass (Windows) gotchas**: Defender ML (`Bearfoos.A!ml`) quarantines the unsigned cycc.exe → 0-byte output / "cannot execute" that LOOKS like a compiler bug — run under the excluded `C:\cyrius-tests`, check `Get-MpThreat`. `cmd /c "prog & echo %errorlevel%"` falsely reports 0 (parse-time expansion). `prog < in > out 2>nul &` corrupts the redirect — use `2> err & exit` then inspect. Wrap multi-host SSH chains in `if…else exit 1`, never bare `&&` chains under `set -e` (non-final failures pass silently).
- Run `cross-os-selfhost.sh` ONE host at a time — fixed /tmp + remote paths clobber under concurrency.
- A helper that compiles is not a helper that works — end-to-end verify new helpers before commit.
- Hardware-only bugs (GPU/COM, no debugger/stdout): exit-code probes over SSH.
- Logic-preserving refactors are proven with the byte-identical self-host + differential-corpus recipe — and stale includes invalidate the comparison (refresh first).
- Clean up test artifacts: local /tmp probes AND remote binaries scp'd to cass/ecb/pi.

### Planning & slots (extends Release & Slot Discipline)
- **Premise-check at slot entry** — empirically test that the gap still exists (pins go stale; three consecutive slots were already-shipped work). Premise-check against the UPSTREAM repo source (`~/Repos/<dep>/src`), never the vendored `lib/` copy.
- **Scope arcs at PLANNING time** (grep the sites, set phase boundaries up front); a mid-execution "we should split this" is suspect — only bug-squash-to-clear-a-hurdle is a legit mid-execution out.
- Roadmap the WHOLE arc and cross-check roadmap_6 / roadmap-future / issues so nothing dangles. Roadmap prose like "needs downstream coordination" is a self-instruction — execute it when the slot opens.
- Priority runs bottom-to-top: kernel/baseOS blockers before application/library wins. Keep an open reactive window during bare-metal/kernel phases.
- Cross-repo arcs do the FULL dependency cross-walk at arc-open (one coordinated filing, not drip).
- Non-blocking cosmetic/tooling fixes fold into adjacent work — no dedicated slots. Minor-open/closeout slots include real code deliverables, not just docs.
- **Version bumps only when a release ships** — a failed/in-flight release is re-cut at the SAME version. User drives all bumps/CHANGELOG ("X.Y.Z is out, lets keep moving" = bump for the next slot); agent runs `version-bump.sh` + state.md refresh at slot close; user push+tag is the CI gate. No minor-component bumps for surface-preserving refactors.
- Don't pin minor patch-count windows — the user states expected size at each arc-open and it changes. **Large minors (~45–99 releases) are the norm; never propose a theme-per-minor.**

### Communication
- **Decide with sensible defaults and act** — surface at most ONE genuine fork, rarely. When the user picks an option, GET MOVING; no re-confirming.
- "continue" / "free to continue" = skip recap and work — no status ceremony, no plan-back.
- No end-of-turn /schedule pitches in this project.
- No hand-wave recommendations ("trust the accumulator", "default to A unless…") — push back with specifics when a proposal is vague.
- Repos with no active bug or ask don't exist for the current work — don't proactively pull them in.

### Ecosystem & stdlib
- sigil/sakshi/bayan/ganita/etc. are the **language's OWN stdlibs** (sovereign), never "external upstream". Anything shipping into `lib/` via `cyrius deps` IS stdlib — full stdlib discipline applies.
- **Fix the SOURCE repo, not the fold** — a fix applied only to cyrius's vendored `lib/<dep>.cyr` evaporates at the next re-vendor. Patch upstream, version-bump it, regen dist, re-vendor.
- Sibling-repo agents editing cyrius source is a hard violation regardless of patch correctness — revert + file as an issue.
- Ecosystem-wide renames must cover ALL source extensions, not just `.cyr`/`.tcyr`.
- Lib files referencing flag constants (O_WRONLY, MAP_PRIVATE, …) must include their definers — self-sufficient modules.
- **Sovereignty**: no Python/bash/C as a shipped slot deliverable (same category error as crates.io). Every bootstrap rung added to seed→cycc enlarges the trusted base — minimize rungs.
- DCE-"dead" fns may be external API surface (`--lex-ts`, cyrdoc, downstream consumers) — check before removal.
- `cbt/cyrius.cyr` (the CLI) cross-compiles to PE/Mach-O — Linux-syscall lib includes break it; guard with `#ifdef` + early return.

### Docs & issues hygiene
- CHANGELOG is canonical history; state.md is current-cycle volatile only; **archive docs, don't delete** — and grep `.github/workflows/` + release scripts for hard-coded path deps first.
- Issues archive to `issues/archived/` at slot close; keep the open dir a lean working queue (~10–12); consolidate the P3/"someday" deferral tail into roadmap entries, not issue files.
- Source comments keep the WHY-invariant plus a one-line `CHANGELOG [X.Y.Z]` pointer — not history blocks.

## Language & test conventions (recurring gotchas)

- **fns take any number of args** (verified 5–20 on real Windows/Linux/aarch64, v6.4.64). The old
  rule here read *"≤6 args cleanly; args 7+ have shown corruption — restructure instead"*. That was
  **wrong in both directions and it was OUR bug, not the caller's**: 7–9 args were always fine, and
  **10+ silently corrupted argument 1 on Win64** (ECALLPOPS' PE branch shuttled stack args through a
  fixed 5-register table and had no code path past `nextra == 5`, so it both mis-popped the register
  args and emitted no stack-arg writes at all). Fixed in v6.4.64; gated by
  `tests/tcyr/vr01_win64_stack_args.tcyr` on real hardware.
  **The lesson worth keeping is not about arity.** A codegen bug had been written down as a language
  rule telling users to restructure their code around it — so for ~a year it was never fixed, and it
  got cited (2026-07-14) to file a *sigil* issue asking a stdlib to contort around a cyrius defect.
  This is the language repo: **when the compiler can't compile valid cyrius, fix the compiler.** If a
  rule here tells you to work around codegen, treat the rule as the bug report.
- **`var x[N]` local = N BYTES** (rounded to 8), not N slots — use `var a: i64[N]` for slots. Bare top-level arrays = N×8 (fixed v6.4.10).
- **Reserved words are a CLASS, not a short list.** `TOKNAME_BUILTIN` (`src/common/util.cyr`) is
  the single source of truth — **67** builtin/intrinsic names plus the ~25 statement keywords, and
  `IS_KEYWORD_TOK` *derives* from it so the two sets cannot drift. It covers `syscall`,
  `load8/16/32/64`, `store8/16/32/64`, every `f64_*` / `f64v_*` / `f32_*` / `f32v_*` / `f32v8_*` /
  `iv_*` intrinsic, plus `union`, `defer`, `secret`, `async`, `await`, `u128`,
  `bitget/bitset/bitclr`, `ret2/rethi` — and `pub`/`shared`/`match`/`in`/`default`/`stack`. The
  parser rejects any of them as an identifier and (since v6.4.77) NAMES the one you hit.
  This line used to read "`secret`, `pub`, `shared` are reserved keywords" — three names for a
  67-name class, which is structurally the same error as the retired "≤6 args" rule: a partial
  observation written down as a language rule. Read the table, don't extend the list here.
- tcyr files MUST end `var r = assert_summary();` (or an explicit exit syscall) so success exits 0. Name tests topically, never temporally ("pass2"/"v3" — 20-yr QA pet peeve).
- cyrfmt flattens multi-line call continuations to 4-space indent — write them that way up front.
- aarch64 stdlib syscall numbers that collide with an x86 number in ESYSXLAT get silently mis-remapped — use the x86 number + an ESYSXLAT entry.
- When restoring/fixing user configs, restore only what was there — no unrequested "sensible defaults".

## DO NOT

- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to GitHub API only
- Do not add language features without updating vidya
- Do not skip self-hosting verification after compiler changes
- Do not modify parse.cyr arch-specific functions — they live in emit files
- Do not remove build/cycc-native-aarch64 — ARM binary needed for self-hosting on ARM hardware (generated by `cyrius pulsar`)
- **v5.0.0 is the recommended minimum** — cycc IR, cyrius.cyml manifest, patra 1.0.0, sankoch 1.2.0. v5.0.1+ adds security hardening (alloc/vec overflow guards). v5.1.0+ adds macOS Mach-O support.

## Downstream repo setup (ecosystem rule)

Downstream repos (mabda, sigil, sakshi, yukti, kybernet, hadara, …) MUST
populate their `lib/` via `cyrius deps` — never by symlinking `lib/` to
`<this repo>/lib`. The symlink pattern caused a real, repeating corruption
in v5.5.30–v5.5.33: an agent working in the downstream repo that edited
`lib/<anything>.cyr` (format / lint / dead-code cleanup) wrote through the
symlink into this repo. Because mabda can't see cyrius's `lib/fdlopen.cyr`
callers, a "dead code" pass removed `dynlib_bootstrap_environ` /
`dynlib_read_auxv` / `dynlib_auxv_get` four times, each surfacing as a CI
failure here and producing the `restore dynlib_*` commit cluster.

If you're investigating apparently-spontaneous file corruption in `lib/`:

```sh
find /home/macro/Repos -maxdepth 3 -type l -lname "*cyrius/lib*" 2>/dev/null
find ~/.cyrius -type l | xargs -I{} sh -c 'readlink -f "{}" | grep -q "Repos/cyrius" && echo "{} -> $(readlink -f \"{}\")"'
find ~/Repos -maxdepth 2 -type l -name lib  # directory-level lib symlinks (the bad pattern)
```

Either command returning a result means a downstream repo is aliasing
its `lib/` back into this one. Sakshi was confirmed at v5.8.23 ship
(its `lib` was a directory-level symlink to `~/.cyrius/lib`); fixed
by `rm sakshi/lib && (cd sakshi && cyrius deps)`. Other downstream
repos at audit time had only single-file `lib/<dep>.cyr` symlinks
(legitimate `cyrius deps` output, not the corruption antipattern).

### Snapshot-ping-pong protection (cyrius-side `lib/*.cyr` edits)

When editing `lib/*.cyr` files in this repo, be aware of the
**snapshot-ping-pong loop**: `version-bump.sh` runs `install.sh
--refresh-only` which copies `lib/*.cyr` from the repo into
`~/.cyrius/versions/<v>/lib/` and `~/.cyrius/lib`. Subsequent
`cyrius deps` resolution (e.g., during `check.sh`) can copy the
snapshot version BACK into the repo, overwriting your edit if
the snapshot is stale.

Mitigation when editing any file in `lib/`:

1. Make the edit in `lib/<file>.cyr`.
2. **Immediately refresh the install snapshot** before running
   any tool that triggers `cyrius deps` resolution:
   ```sh
   cp lib/<file>.cyr ~/.cyrius/versions/$(cat VERSION)/lib/<file>.cyr
   cp lib/<file>.cyr ~/.cyrius/lib/<file>.cyr   # if the symlink-target also exists as a file
   ```
   Or run `sh scripts/version-bump.sh "$(cat VERSION)"` (same-version
   regenerate path) which re-runs `install.sh --refresh-only`.
3. Run `sh scripts/check.sh` to verify; the file should now stick.

Discovery: surfaced at v5.8.23 mid-bite-2 when `lib/tagged.cyr`
edits reverted between Edit calls during the v5.8.21 sum-type
migration. Root cause was the v5.8.22 install snapshot still
containing the pre-migration hand-rolled fns; `check.sh`'s
`cyrius deps` step copied them back into the repo.
