# Cyrius — Claude Code Instructions

## Project Identity

**Cyrius** — Sovereign, self-hosting systems language. Assembly up.

- **Type**: Self-hosting compiler toolchain
- **License**: GPL-3.0-only
- **Version**: 6.0.88

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
- **Cross-OS self-host is non-negotiable, on REAL hardware** — "self-hosting" means cycc reproduces itself byte-identical on **every target it claims to support**, not just x86_64 Linux. After ANY compiler-backend or stdlib change, verify cycc self-hosts on **ecb (macOS, arm64)** + **cass (Windows, PE)** via SSH — they're wired in `~/.ssh/config`, one `ssh` away, every slot. **A green CI checkmark is NOT verification.** The macOS compiler self-host rotted silently for ~9 minors (v5.3.13 → v6.0.32, 400+ patches) behind a CI job named "Mach-O ARM64 Native ✓" that only ran hello-world / exit-code programs and never once built or self-hosted `cycc`. It surfaced only when a human installed on a Mac and got a broken toolchain — the exact "found by ports" failure. Hello-world smoke is a placebo; the compiler self-hosting on the target IS the test. Never trust a checkmark over running the compiler on the hardware. See `feedback_macos_windows_ci_gate_mandatory`, `reference_verification_hosts_ssh`, Closeout 3b.
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

## P(-1): Project Hardening

Before starting new work on a release, run this audit phase:

1. **Cleanliness** — `cyrius fmt --check`, `cyrius lint`, `cyrius vet`
2. **Test sweep** — all .tcyr pass, heap audit clean, self-hosting verified
3. **Benchmark baseline** — `cyrius bench` before changes
4. **Audit** — identify stale code, dead paths, optimization opportunities
5. **Refactor** — address findings from audit
6. **Post-audit benchmarks** — compare against baseline
7. **Document** — update CHANGELOG, roadmap, vidya

## Closeout Pass (before every minor/major bump)

Run a closeout pass before tagging x.Y.0 or x.0.0. Ship as the last patch of the current minor (e.g. 4.2.5 before 4.3.0). **Mechanical checks first, then the judgment-call passes (refactor / code review / cleanup), then the doc sync.**

### Mechanical (automated, fast-fail)
1. **Self-host verify** — cycc compiles itself byte-identical
2. **Bootstrap closure** — seed → cybs → asm → cybs byte-identical
3. **Full check.sh** — all gates green (count grows per minor; record the number)
3b. **Cross-OS self-host (NON-NEGOTIABLE — added v6.0.x after the macOS rot incident)** — cycc must build from the correct per-target source AND **self-host byte-identical on real macOS (ecb) + Windows (cass)**, not just x86_64 Linux. Hello-world/exit-code smoke is NOT self-host — the macOS port rotted v5.3.13→v6.0.31 precisely because the `macho-arm64-native`/`windows-native` CI jobs only ran tiny programs, never the compiler. Verify via the `macos-14`/`windows-latest` CI jobs (once extended to self-host) AND/OR SSH to ecb/cass. A minor does NOT close with macOS/Windows self-host unverified or red. See [reference: verification hosts, `feedback_macos_windows_ci_gate_mandatory`].

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
9. **Security re-scan** — quick grep for new `sys_system`, `READFILE`, unchecked writes. Full audit every 2-3 minors (last: v5.0.1).
10. **Downstream check** — all `cyrius.cyml` `cyrius` fields across ecosystem repos point to the released tag.

### Docs (silent-rot prevention)
11. **CHANGELOG/roadmap/vidya sync** — all docs reflect current state. Vidya in particular needs explicit refresh per minor (it falls out of sync silently — no compile-time check):
   - **`vidya/content/cyrius/language.toml`** — language usage. Add `[[entries]]` blocks for any new syntax / builtins / directives shipped this minor (e.g. `#regalloc`, `secret var`, `#pe_import`, multi-return, struct initializer). Update existing entries when behavior changed (e.g. `&local` arch dispatch, `_cyrius_init` binding flip). Refresh the `overview` entry's compiler-size + cc-binary-name + version line at every minor.
   - **`vidya/content/cyrius/field_notes/compiler.toml`** — compiler internals + non-obvious gotchas. Add field notes for anything that surprised us this minor (e.g. RBP-after-`clone()` race, `FUTEX_PRIVATE_FLAG` mismatch with kernel `CLONE_CHILD_CLEARTID`, parse.cyr unguarded x86-emit paths that shipped silently, `mov rN, rax` byte-order typos that segfault on Windows). One entry per gotcha; future-claude searching vidya before reimplementing should hit them.
   - **`vidya/content/cyrius/field_notes/language.toml`** — user-facing language gotchas (e.g. no `var` redecl in same scope, no comparisons in fn-call args, parser's `#ifdef`-but-not-`#else`).
   - **`vidya/content/cyrius/implementation.toml`** / **`types.toml`** — bump version refs and any structural changes (heap map, fixup table, fn table caps, IR opcode count, backend modules).
   - **`vidya/content/cyrius/dependencies.toml`** / **`ecosystem.toml`** — refresh when deps bump (sigil 2.8.4 → next, etc.) and when downstream consumer counts / test counts change.
   - **Cross-check the version**: every vidya file mentioning a `cc?` version (`cc3 4.8.5`, `cycc 5.4.x`, etc.) should match the current `VERSION` file. `version-bump.sh` doesn't touch vidya — that's manual at closeout.

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
                 ☐ Full suite: sh scripts/check.sh
4. IF BROKEN   — Revert, apply ONE change, test, repeat
                 If stuck, STOP and ASK the user — never defer on your own
5. AUDIT       — Full chain: bootstrap, all suites, self-hosting
6. DOCUMENT    — Update: CHANGELOG, roadmap, benchmarks, vidya
```

## Project Structure

```
bootstrap/           29KB seed binary + cybs.cyr + asm.cyr
src/
  main.cyr           Compiler entry point (includes modules)
  main_aarch64.cyr   Cross-compiler (swaps arch includes)
  frontend/          lex.cyr, parse.cyr
  backend/x86/       emit.cyr, jump.cyr, fixup.cyr
  backend/aarch64/   emit.cyr, jump.cyr, fixup.cyr
  backend/cx/        emit.cyr (cyrius-x bytecode)
  common/            util.cyr, ir.cyr
lib/                 Standard library (81 modules + 9 deps)
programs/            80 programs (tools, tests, demos, algorithms)
tests/               Test suites (tcyr/*.tcyr, heapmap.sh)
benches/             Benchmarks (*.bcyr)
fuzz/                Fuzz harnesses (*.fcyr)
build/               Generated binaries (gitignored except the current-major
                     compiler + a prior-major seed binary — currently cycc
                     and cc3. cc3 (the last legacy seed bridging the
                     pre-v6.0.0 rename history) is tracked through v6.x and
                     drops at the v6.x → v7.x bump. From v7.x onward ONLY
                     `cycc` is tracked — `cycc` is the final, forever binary
                     name (per `Version lives in VERSION + --version, never
                     in binary names` above), so no prior-seed slot is
                     needed: there are no more name changes for fresh
                     checkouts to bridge.)
docs/                Architecture, roadmap, benchmarks, language guide
```

## Key References

- `docs/guides/cyrius-guide.md` — Complete language reference
- `docs/development/roadmap.md` — Current-cycle (v6.x) remaining work
- `docs/development/roadmap-future.md` — Long-term watching list (unpinned items, speculative work, v7.0+ aspirations)
- `docs/development/cycle-discipline.md` — Evergreen operating principles (slot acceptance, bottom-to-top priority, premise-check, cross-host smoke, cycle-close shape)
- `docs/development/state.md` — Volatile cycle / pin / sweep state (refreshed every release)
- `docs/development/dev-tools-linux.md` — per-environment dev toolchain (Linux x86_64 first; `qemu-user`/`wine` to reproduce aarch64/PE self-host bugs locally, `llvm-objdump` disasm, SSH cross-host verify). macOS/Windows siblings to follow. Install these before cross-target codegen work.
- `docs/doc-health.md` — Living doc-currency ledger (per-tier fresh / stale / archived; refreshed when docs are touched)
- `CHANGELOG.md` — Source of truth for all changes
- `../vidya/content/compiler_bootstrapping/cyrius_*.toml` — 90+ vidya entries

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
