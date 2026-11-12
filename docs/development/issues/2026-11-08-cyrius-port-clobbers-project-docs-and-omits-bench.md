# `cyrius port` overwrites an existing CLAUDE.md, roadmap and state.md, pins `version = "0.1.0"`, leaves `bench` out of `[test] stdlib`, and scaffolds stubs that fail `cyrius audit` — open

**Status:** 🟡 **OPEN** — verified with the installed 6.7.18 `cyrius port`, on a copy of tanmatra and then on tanmatra itself, 2026-11-08.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-08, M0 of the tanmatra Rust → Cyrius port (`tanmatra/docs/development/tanmatra-port-plan.md` §2)
**Reporter:** tanmatra 1.3.0 → 2.0.0 port
**Cyrius version at time of report:** 6.7.18
**Affected:** `programs/cyrius-init.cyr` (port driver, `_rw` calls at :1402, :1410–1412, :1452–1457; the dry-run report at :1196–1200), `programs/cyrius-init-templates/cyrius-cyml-port`
**Severity:** **Medium**. No data is lost while the project is under git, but a port of a mature project silently replaces its working documents. A freshly ported project also fails `cyrius bench` and `cyrius audit`, and its first release tag fails its own release workflow.

## Summary

`cyrius port` is meant for projects that already exist, but it writes several files unconditionally (`_rw`, not the skip-if-exists
`_rw_wia` that in-place `cyrius init` uses):

1. **It overwrites project documents.** These are replaced with templates:
   - `CLAUDE.md` (:1412);
   - `docs/development/roadmap.md` (:1411): tanmatra's 123-line roadmap became the 36-line template;
   - `docs/development/state.md` (:1410);
   - `.github/workflows/ci.yml` and `release.yml` (:1452, :1455).

   `.gitignore` and `.gitattributes` are handled correctly: they are appended to.
2. **The manifest ignores `VERSION`.** The `cyrius-cyml-port` template writes `version = "0.1.0"`, and `state.md` says 0.1.0, even
   when the project has a `VERSION` file (tanmatra: 1.3.0). The `release.yml` that the same command writes expects
   `version = "${file:VERSION}"`. With `0.1.0` in the manifest, the first release tag fails *Verify version consistency*.
3. **`bench` is missing from `[test] stdlib`.** The `cyrius-cyml-port` template has `stdlib = ["assert"]`, while
   `cyrius-cyml-lib` and `cyrius-cyml-bin` both have `["assert", "bench"]`. The scaffold's own `tests/<name>.bcyr` then fails to
   compile, so `cyrius bench` and `cyrius audit` fail on a project that was just scaffolded. `cyrius build` and `cyrius test` pass.
4. **The scaffold's own stubs fail `cyrius audit`.** Its `── docs ──` step reports `6 undocumented public fns` and exits 1, even
   with item 3 fixed. The six are `main` in `src/main.cyr` and in `tests/<name>.tcyr`, `bench_noop` and `main` in `.bcyr`, and
   `fuzz_main` and `main` in `.fcyr`. None of the templates has a doc comment, so a port is never `audit`-clean out of the box.
   (A side note: piping `cyrius audit` through `tail` hides this, because the exit status seen is `tail`'s. That cost one wrong
   "audit passes" in the tanmatra session.)
5. **`--dry-run` under-reports.** It prints "src/, project manifests, tests/, benches/ etc." for the move. It doesn't list the files
   it will overwrite, and it doesn't mention that `target/` (2.4 GB here) moves too. A reviewer can't see item 1 before it happens.

## Reproduction

```sh
cp -r <any Rust project with CLAUDE.md, docs/development/roadmap.md, VERSION> /tmp/p && cd /tmp/p
git init -q && git add -A && git commit -qm base
cyrius port --dry-run .        # no mention of CLAUDE.md / roadmap / workflows
cyrius port .
git diff --stat                # CLAUDE.md, docs/development/roadmap.md, .github/workflows/* rewritten
grep '^version' cyrius.cyml    # version = "0.1.0", VERSION says otherwise
cyrius bench                   # fails: bench_new / bench_report undefined
cyrius audit; echo $?          # 1 — "6 undocumented public fns" (and the bench failure)
```

## Proposed fix

- **Item 1.** Use `_rw_wia` (skip if the file exists, and print the skip) for `CLAUDE.md`, `roadmap.md`, `state.md` and the two
  workflows. Alternatively, write the template beside the existing file, e.g. `CLAUDE.md.port`, and say so.
- **Item 2.** When `VERSION` exists, write `version = "${file:VERSION}"`, and substitute the `VERSION` contents into `state.md`.
- **Item 3.** Change the port template's `[test] stdlib` to `["assert", "bench"]`, matching the lib and bin templates.
- **Item 4.** Give each `fn` in `main-cyr-port`, `proj-tcyr` and the bench and fuzz templates a one-line `#` doc comment, and
  add a gate row that runs `cyrius audit` on a freshly ported fixture.
- **Item 5.** Have `--dry-run` list every path it moves, and mark every path it overwrites, as opposed to creating it.

## Consumer-side workaround

tanmatra restored `CLAUDE.md` and the roadmap from git and merged in the scaffold's Cyrius rules. It set
`version = "${file:VERSION}"`, added `bench` to `[test] stdlib` by hand, documented the six stub functions, and kept the scaffold's CI and release workflows,
extended with `test --bounds`, `deps --locked` and `audit` steps.

## Seen again: pravash (2026-11-11, cyrius 6.7.18)

pravash's port hit items 1–3 again. `CLAUDE.md`, `docs/development/roadmap.md` and both workflows were overwritten,
the manifest got `version = "0.1.0"`, and `[test] stdlib` had no `bench`. It also found three more, smaller:

- **The `.gitignore` message is wrong.** The scaffold reports "Appended /rust-old/ and /build/" but appends
  `/rust-old/target/` (and `/rust-old/**/__pycache__/`). The behaviour is the useful one, since `rust-old/` stays
  tracked, but the message says the opposite. impetus noted the same.
- **A library crate's ignored `Cargo.lock` isn't handled.** A Rust library usually ignores `Cargo.lock`. For a port,
  the frozen crate is the parity oracle, and its bits depend on the exact dependency versions. The scaffold moves the
  (untracked) lock to `rust-old/Cargo.lock` but leaves the `Cargo.lock` line in `.gitignore`, so the oracle has no
  committed lock unless the porter notices. pravash tracked it by hand before the scaffold. A note in the dry run, or a
  `!rust-old/Cargo.lock` line, would cover it.
- **`target/` moves too, unannounced.** It was 4.1 GB here. `--dry-run` doesn't mention it (item 5); a
  `cargo clean` first avoids moving it.

## Seen again: ushma (2026-11-11, cyrius 6.7.18)

ushma's port (a Rust library with CLAUDE.md, roadmap.md, state.md and `VERSION` 1.4.0) hit items 1–4 again:
- the documents and both workflows were overwritten;
- the manifest got `version = "0.1.0"` and `[test] stdlib = ["assert"]`;
- the scaffold's stubs failed `cyrius doc --check` until they were documented.

It also hit pravash's `Cargo.lock` point: the library's `.gitignore` still ignored `Cargo.lock` after the move, so
`rust-old/Cargo.lock`, which the parity oracle must rebuild against, was untracked until the `.gitignore` was
rewritten. Nothing new beyond pravash's list; one more reproduction.
