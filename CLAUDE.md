# Cyrius — Claude Code Instructions

## Project Identity

**Cyrius** — Sovereign, self-hosting systems language. Assembly up.

- **Type**: Self-hosting compiler toolchain
- **License**: GPL-3.0-only
- **Version**: 5.11.53

## Goal

Own the language. Own the toolchain. No crates.io. No external governance. Assembly is the cornerstone. Cyrius writes the AGNOS kernel.

## Current State

> Volatile state lives in [`docs/development/state.md`](docs/development/state.md) —
> current version, cc5 size, in-flight slots, recent shipped releases,
> consumers, verification hosts, bootstrap chain. Refreshed every release.
> Historical release narrative lives in
> [`docs/development/completed-phases.md`](docs/development/completed-phases.md).

This file (`CLAUDE.md`) is **preferences, process, and procedures** —
durable rules that change rarely, not state that bumps every release.

## Quick Start

```bash
sh bootstrap/bootstrap.sh          # bootstrap from seed
cat src/main.cyr | build/cc5 > /tmp/cc5 && chmod +x /tmp/cc5  # build compiler
cat src/main.cyr | /tmp/cc5 > /tmp/cc5b && cmp /tmp/cc5 /tmp/cc5b  # self-hosting verify
sh scripts/check.sh                # full audit
cyrius test                        # run .tcyr suite
cyrius fuzz                        # run .fcyr harnesses
cyrius bench                       # run .bcyr benchmarks
```

## Key Principles

- **Self-hosting is non-negotiable** — cc5==cc5 byte-identical after every compiler change
- **Two-step bootstrap for heap changes** — cc5 compiles cc5b, cc5==cc5b
- **Assembly is the cornerstone** — understand every instruction the compiler emits
- **Test after EVERY change** — not after the feature is "done"
- **ONE change at a time** — never bundle unrelated changes
- **Research before implementation** — vidya entry before code
- **When stuck, ASK the user** — never decide to defer, slip, re-slot, or split work mid-execution. Splits are planned decisions made *before* starting; reactive scope changes when stuck are deferment and count as slipping. Report findings and wait for direction. See [*Micro-Work and Agent Deferment*](https://github.com/MacCracken/agnosticos/blob/main/docs/articles/micro-work-and-agent-deferment.md) for the four-case classification (commit-through / prereq-bug / pre-planned decomposition / the sleight-of-hand to reject).
- **Bootstrap chain integrity** — never break seed → cyrc → bridge → cc5
- **Version lives in `VERSION` + `--version`, never in binary names** — after the v6.0.0 `cc5` → `cyc` rename, the compiler binary is `cyc` *forever*. No `cc6` at v7.0.0, no `cc7` at v8.0.0, no funny business. The cc3 → cc5 rename at v5.0.0 was the last name-change penalty paid; v6.0.0 fixes the pattern. Anyone tempted to add a version digit to a binary name (compiler, linker, formatter, anything) is reintroducing the bug we explicitly removed. `VERSION` file + binary `--version` output are the only sources of truth.

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
1. **Self-host verify** — cc5 compiles itself byte-identical
2. **Bootstrap closure** — seed → cyrc → asm → cyrc byte-identical
3. **Full check.sh** — all gates green (count grows per minor; record the number)

### Judgment-call passes (where bugs hide)
4. **Heap map audit** — beyond "verify the map matches usage", evaluate:
   - Newly-added regions (are they documented, sized correctly, at stable offsets)
   - Unused / stale regions (any region no code writes to → candidate for removal)
   - Regions that hit caps across the minor (grow before they bite)
   - Opportunity for consolidation (adjacent regions owned by the same subsystem)
5. **Dead code audit** — remove unreachable fns; record the remaining floor in CHANGELOG. The `note: N unreachable fns` output from cc5 is the baseline.
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
   - **Cross-check the version**: every vidya file mentioning a `cc?` version (`cc3 4.8.5`, `cc5 5.4.x`, etc.) should match the current `VERSION` file. `version-bump.sh` doesn't touch vidya — that's manual at closeout.

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
                 ☐ Self-hosting: cc5==cc5 byte-identical
                 ☐ Full suite: sh scripts/check.sh
4. IF BROKEN   — Revert, apply ONE change, test, repeat
                 If stuck, STOP and ASK the user — never defer on your own
5. AUDIT       — Full chain: bootstrap, all suites, self-hosting
6. DOCUMENT    — Update: CHANGELOG, roadmap, benchmarks, vidya
```

## Project Structure

```
bootstrap/           29KB seed binary + cyrc.cyr + asm.cyr
src/
  main.cyr           Compiler entry point (includes modules)
  main_aarch64.cyr   Cross-compiler (swaps arch includes)
  bridge.cyr         Bridge compiler (cyrc feature set)
  frontend/          lex.cyr, parse.cyr
  backend/x86/       emit.cyr, jump.cyr, fixup.cyr
  backend/aarch64/   emit.cyr, jump.cyr, fixup.cyr
  backend/cx/        emit.cyr (cyrius-x bytecode)
  common/            util.cyr, ir.cyr
lib/                 Standard library (54 modules + 6 deps)
programs/            59 programs (tools, tests, demos, algorithms)
tests/               Test suites (tcyr/*.tcyr, heapmap.sh)
benches/             Benchmarks (*.bcyr)
fuzz/                Fuzz harnesses (*.fcyr)
build/               Generated binaries (gitignored except current-major
                     compiler + prior-major seed binary — currently cc5
                     and cc3. Sequence: cc3 drops at v6.0.0/cyc cut, cc5
                     becomes the prior-major seed during v6.x as the LAST
                     legacy binary; cc5 drops at the v6.x → v7.x bump and
                     from v7.x onward ONLY cyc is tracked — `cyc` is the
                     final binary name (per `Version lives in VERSION +
                     --version, never in binary names` above), so no
                     more prior-seed slot is needed because there are no
                     more name changes for fresh checkouts to bridge.)
docs/                Architecture, roadmap, benchmarks, language guide
```

## Key References

- `docs/cyrius-guide.md` — Complete language reference
- `docs/development/roadmap.md` — Current-cycle remaining work only (lean, refreshed at cycle close)
- `docs/development/roadmap-old.md` — Prior roadmap held verbatim for cleanout; source for v6.x items to pull forward at v5.x close
- `docs/development/cycle-discipline.md` — Evergreen operating principles (slot acceptance, bottom-to-top priority, premise-check, cross-host smoke, cycle-close shape)
- `docs/development/state.md` — Volatile cycle / pin / sweep state (refreshed every release)
- `docs/doc-health.md` — Living doc-currency ledger (per-tier fresh / stale / archived; refreshed when docs are touched)
- `CHANGELOG.md` — Source of truth for all changes
- `../vidya/content/compiler_bootstrapping/cyrius_*.toml` — 90+ vidya entries

## DO NOT

- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to GitHub API only
- Do not add language features without updating vidya
- Do not skip self-hosting verification after compiler changes
- Do not modify parse.cyr arch-specific functions — they live in emit files
- Do not remove build/cc5-native-aarch64 — ARM binary needed for self-hosting on ARM hardware (generated by `cyrius pulsar`)
- **v5.0.0 is the recommended minimum** — cc5 IR, cyrius.cyml manifest, patra 1.0.0, sankoch 1.2.0. v5.0.1+ adds security hardening (alloc/vec overflow guards). v5.1.0+ adds macOS Mach-O support.

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
