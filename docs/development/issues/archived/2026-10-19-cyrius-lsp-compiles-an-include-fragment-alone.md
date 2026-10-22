# `cyrius-lsp` compiles an include fragment ALONE — every name from an earlier include reads "undefined", so diagnostics in any multi-file project (cyrius's own `src/` included) are false — RESOLVED

> ✅ **RESOLVED in v6.7.16** (TL-15, `7eb1197ea`, with TL-13, `535ce6ef3` (the `[lsp] skip` key), TL-14, `d8c3537e0` (the guide's [embed] sentence, a find in passing), and the review fixes TL-15r, `cf2b34ef1`, and TL-15r2, `65ac12b59` — the issue's decision, the user 2026-10-19: `[lsp] skip` added, the design's other defaults stand. Each project file is checked through its unit, chosen from the include graph (column-0 includes resolved as cycc resolves them, each with the targets its #ifdef stack lets through): an entry as itself; a fragment through the entry that reaches it (the manifest's first, then the fewest hops, then path order), publishing on that unit's files; a Windows / agnos / macOS / EFI-only file under the target's selector; an aarch64- or cx-only one as one Information note, not compiled; a public lib/ module as `include "lib/<m>.cyr"` alone; a lib/ peer through its nearest public module; an `[lsp] skip` file never. The output is read whole (64 MiB cap), one compile serves every fragment until a dependency changes on disk, and go-to-definition resolves includes from the project root (the found-in-passing item). On the filed files: parse_ctrl.cyr e55 → 0, ir.cyr e46 → 0, x86/emit.cyr e36 → 0, lib/syscalls_windows.cyr w67 → 0, bootstrap/cybs.cyr e3 → 0 (skipped). The acceptance sweep (row S, 159 files, graded on each file's last publish) passed at the lane head with lib/yukti.cyr exempt — the yukti 2.3.17 fold did not compile alone (filed) — and in full on main once the yukti 2.3.18 refold (`87190c421`) removed that exemption. Beyond the decision's text: this repo's `[lsp] skip` also names src/main_aarch64_native.cyr (TL-15r2, the review's default); the lib/ peer rule is the stdlib gate's, not the parenthetical above; an inherited CYRIUS_TARGET_* no longer reaches a project child. A clean fragment's note cleared by opening another file of its unit (filed from the review) is fixed in the t16 lane (`956e41e44`). Rows: tests/gates/toolchain/lsp_fragment_compiles_its_unit.sh F1 – F23 (each with its mutant) and S; manifest_key_inventory.sh axis 6; cli_fork_failure_named.sh axis 3; cross-os-selfhost.sh L4 on ecb and ach. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 using the `cyrius-lsp` Claude Code plugin in this repo: the session's
diagnostics on `src/common/ir.cyr`, `src/frontend/parse_ctrl.cyr`, `parse_fn_def.cyr`, `src/backend/x86/emit.cyr`,
`lib/syscalls_windows.cyr`, `bootstrap/cybs.cyr` and a fold's `src/bytes.cyr` were all false. Design measured
read-only the same day (below).
**Placement:** 6.7.16 — Break 2, repair 6 (tools lane, wave 1, unit T5; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19):** 6.7.16; the `[lsp] skip` manifest key is added (`cyrius.cyml` gains
`[lsp] skip = ["bootstrap/cybs.cyr"]`); the design's other defaults stand.
**Severity:** Medium — the language server's diagnostics are wrong for every file that is not itself a compile unit, in
every multi-file project; no boundary is crossed.
**Kind:** tooling (programs/cyrius-lsp.cyr; `cbt/manifest.cyr` for the `[lsp] skip` key). `src/` and
`bootstrap/` untouched — cycc stays byte-identical.

## Root cause (measured)

`handle_did_open_or_save` (cyrius-lsp.cyr:1768) → `compile_and_capture` (1276) → in a project `_compile_via_wrapper_run`
(1080): `cyrius check --with-deps --no-redirect <the open file>` from the project root. The open file is always the
unit. cycc already names errors in included files by their include path (`error:src/frontend/parse_ctrl.cyr:50:32: …`),
and `_lsp_parse_diag` (1523) / `_lsp_resolve_file` (1424) already publish per file — only the choice of unit is wrong.

| compiled | result |
|---|---|
| `parse_ctrl.cyr` alone | 199 false diagnostics (11,163 B of stderr), 28 ms |
| `src/main.cyr` (deps prepend) | 1.39 s, one location-less warning (`large static data`) |
| `lib/string.cyr` with the prepend / alone | a duplicate-fn warning per fn / 0 |
| `lib/syscalls_windows.cyr` with the prepend / alone | 82 duplicate-fn warnings / 0 |
| peers alone (`fs_win`, `process_win`, `process_agnos`) | 7 / 15 / 47 false; their roots under `CYRIUS_TARGET_WIN` / `AGNOS`: 0 |
| `bootstrap/cybs.cyr` | 3 errors — it is assembly for `bootstrap/asm`, not cycc input |

Also measured: the server keeps only the first 8,191 B of stderr (1128-1135, 1339-1346) — a unit compile could push the
open file's own error past the cut.

## Design (the plan; full text in the 2026-10-19 session)

**Units and modes.** A unit is (entry E, target T, deps mode D). Each file gets SELF (its own entry), FRAGMENT (through
another entry, host target), PEER (through another entry under a target selector), NOTE (reachable only on a target this
host cannot select — no compile, one Information note) or SKIP (never compiled).

**Include graph** (cached per root): column-0 `include "x"` edges resolved as cycc resolves them from the root; each edge
carries a target mask from its `#ifdef` stack (host / WIN / AGNOS / MACOS / EFI predefines). Freshness by mtime + size
per closure file, re-walk on an unknown file.

**Entries**: the manifest's `[build] entry` (read through the CLI's own `--print-config`), then discovered entries (a
`.cyr` no other non-test `.cyr` includes; excluding `lib/**`, hidden dirs, `build/`, `dist/`, sub-projects with their
own manifest); test files' includes never make their subject a fragment. Ranking: the manifest entry first, then fewest
hops, then path order.

**Lib rule** (the contract `stdlib_modules_self_sufficient.sh` pins): a public module (its `# Usage: include` names
itself, or no lib/ file includes it) is SELF and checked STANDALONE (no prepend — ends the duplicate-fn noise); a peer is
checked through its nearest public ancestor under the target that includes it (`syscalls_windows` → `lib/syscalls.cyr`
under WIN; `fs_win` → `lib/fs.cyr` under WIN; `process_agnos` → `lib/process.cyr` under AGNOS; aarch64-only peers →
NOTE).

**Publishing**: SELF and loose files as today; FRAGMENT publishes the open file plus each named file whose own unit is
this same unit (one file, one unit — keeps a fork's warnings off shared files), PEER the open file only; the stale-list
bookkeeping keyed by unit, recording the open file when non-empty; a one-line Information note when the open file is
clean but the unit has errors elsewhere; location-less warnings go to the unit, errors to the open file; `<source>` maps
to the unit.

**Performance**: a per-unit cache keyed on the closure's mtimes / sizes, `lib/**`, the manifest and lock, and the CLI /
cycc binaries — opening N fragments of `cycc` costs one compile; compiles on disk changes only (the server reads from
disk). `_lsp_drain` grows the stderr buffer (cap 64 MiB, named in the log).

**Code**: a "compile units" section (graph, entries, unit choice, signatures, target envp, drain); `_compile_via_wrapper*`
take (unit, root, deps, selector); `parse_and_send_diagnostics` filters by mode; `handle_did_open_or_save` dispatches on
the mode (optionally indexing the unit's entry so go-to-definition from a fragment reaches earlier names).

**Tests**: a new gate `tests/gates/toolchain/lsp_fragment_compiles_its_unit.sh` (the `lsp_diagnostics_file_column.sh`
harness, temp projects, a CLI shim logging argv and `CYRIUS_TARGET_*`): ~20 rows — a fragment / a deep fragment clean, a
real error in a fragment at its own line, the note, an entry's error published on the entry, a standalone file and a loose
file unchanged, stale lists cleared after a fix, one compile for N fragments, a discovered entry, a WIN peer checked under
the selector, an aarch64 peer's note, a skipped file never compiled, a lib module standalone, a test include ignored,
> 8 KB of noise ahead of the real error, a location-less warning on the unit — each with its mutation. The existing LSP
gates (R0–R18, `lsp_reads_whole_document.sh`, `lsp_indexes_every_decl_spelling.sh`, `_lsp_definition_gate`) stay green.

## Decisions (the user's, 2026-10-19)

- **`[lsp] skip`** — TAKEN: a manifest key listing files the server never compiles (here `bootstrap/cybs.cyr`, assembly
  for the seed's `bootstrap/asm`): a `cbt/manifest.cyr` vocabulary row, a `--print-config` row, the guide's manifest
  table, and the row in this repo's `cyrius.cyml`.
- The defaults above stand (entries discovered, not declared; peers compiled under the selector; the note's severity;
  one file one unit; ranking).

## Found in passing

`lsp_index_file` (520-555) resolves includes against the server's working directory, not the project root — go-to-
definition in a project opened from another directory misses its own includes; the graph's root-relative resolver
replaces it (in scope of this issue).

## Acceptance

Opening any include fragment of a project shows only real diagnostics, at their own lines (in this repo: every file
under `src/` and `lib/` clean on a clean tree); the new gate and its mutations; the existing LSP gates green;
`docs/guides/editor-integration.md` describes how a file's unit is chosen and the `[lsp] skip` key.
