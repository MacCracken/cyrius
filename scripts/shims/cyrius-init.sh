#!/bin/sh
# cyrius init — scaffold a new Cyrius project
# Usage: cyrius-init.sh [flags] <project-name | .>
#
# Creates a complete Cyrius project with vendored stdlib,
# build/test scripts, and documentation templates.
#
# v5.6.0: --language=<source-language-posture> selects target shape:
#   none (default) — greenfield scaffold; if target is `.` or already
#                    exists, runs in-place and skips-don't-overwrite
#                    any pre-existing file (safe for git-inited, docs-
#                    only repos).
#   rust           — declines and points at `cyrius port <path>`,
#                    which owns the rust→cyrius migration path.

set -e

DRY_RUN=0
AGENT=""
CMTOOLS=""
LANGUAGE="none"
DESCRIPTION=""
# v5.7.15: --lib emits library-shape scaffold (entry = programs/smoke.cyr,
# [lib] modules, src/main.cyr is a header-only module). --bin emits the
# binary scaffold (existing behavior). Default = bin for backward-compat.
SHAPE="bin"
NAME=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --agent) AGENT="generic" ;;
        --agent=*) AGENT="${arg#--agent=}" ;;
        --cmtools) CMTOOLS="starship" ;;
        --cmtools=*) CMTOOLS="${arg#--cmtools=}" ;;
        --language=*) LANGUAGE="${arg#--language=}" ;;
        --language) echo "error: --language requires a value (none|rust)"; exit 1 ;;
        # v5.6.28: --description=<str> populates cyrius.cyml [package].description
        # so a fresh scaffold doesn't ship with a silently-empty manifest field.
        # When absent, defaults to "<name> — TODO" placeholder (see :PROJ_DESC).
        --description=*) DESCRIPTION="${arg#--description=}" ;;
        --description) echo "error: --description requires a value"; exit 1 ;;
        --lib) SHAPE="lib" ;;
        --bin) SHAPE="bin" ;;
        -*) echo "Unknown flag: $arg"; exit 1 ;;
        *) NAME="$arg" ;;
    esac
done

# --language=rust → rust→cyrius migration is owned by `cyrius port`.
# Don't fork the migration logic into init; route the user to the right
# tool with a clear pointer.
if [ "$LANGUAGE" = "rust" ]; then
    echo "error: --language=rust is for rust→cyrius migration; use:"
    echo "  cyrius port ${NAME:-<path-to-rust-project>}"
    exit 1
fi

if [ "$LANGUAGE" != "none" ]; then
    echo "error: unsupported --language=$LANGUAGE (supported: none, rust)"
    echo "  none — greenfield scaffold (default; in-place safe)"
    echo "  rust — see 'cyrius port <path>'"
    exit 1
fi

if [ -z "$NAME" ]; then
    echo "Usage: cyrius init [flags] <project-name | .>"
    echo ""
    echo "Creates a new Cyrius project with:"
    echo "  cyrius.cyml    project manifest + deps"
    echo "  src/main.cyr   entry point"
    echo "  src/test.cyr   test file"
    echo "  lib/           resolved stdlib (via cyrius deps)"
    echo "  scripts/       build + test"
    echo "  docs, CI, version files"
    echo ""
    echo "Options:"
    echo "  --lib              emit library-shape scaffold (entry=programs/smoke.cyr,"
    echo "                     [lib] modules=[src/main.cyr], src/main.cyr header-only)"
    echo "  --bin              emit binary-shape scaffold (default; existing behavior)"
    echo "  --language=<x>     source-language posture (none|rust); default none"
    echo "                     none — greenfield (in-place safe; skips existing files)"
    echo "                     rust — declines; use 'cyrius port <path>'"
    echo "  --dry-run          show what would be created without writing"
    echo "  --agent            create a CLAUDE.md for generic Cyrius projects"
    echo "  --agent=<preset>   create a CLAUDE.md from a preset (agnos, claude)"
    echo "  --cmtools          install CLI tool integrations (default: starship)"
    echo "  --cmtools=<name>   install specific tool (starship)"
    echo ""
    echo "Targets:"
    echo "  cyrius init my-proj                 → create ./my-proj/ (errors if exists)"
    echo "  cyrius init --language=none .       → scaffold INTO current dir (skip-existing)"
    echo "  cyrius init --language=none my-proj → if my-proj/ exists, scaffold in-place"
    exit 1
fi

CYRIUS="$(cd "$(dirname "$0")/.." && pwd)"

# In-place vs greenfield. v5.6.0: in-place mode is OPT-IN via NAME=`.`
# (always) — never auto-triggered by an existing dir match, since
# `cyrius init my-proj` against an unintentional preexisting `my-proj/`
# should still hard-error rather than silently scaffold over it. The
# in-place path makes every writer below skip-if-exists, so docs-only /
# git-inited repos at the cwd don't get clobbered.
INPLACE=0
if [ "$NAME" = "." ]; then
    INPLACE=1
    NAME="$(pwd)"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$INPLACE" -eq 1 ]; then
        echo "Dry run: cyrius init --language=none $NAME (in-place, skip-existing)"
    else
        echo "Dry run: cyrius init $NAME"
    fi
    echo ""
    # v5.6.28: dry-run listing rebuilt to mirror the real writer set
    # 1:1. Previous list advertised CONTRIBUTING.md / SECURITY.md /
    # CODE_OF_CONDUCT.md / docs/development/ content that no
    # write_if_absent call ever produces under --language=none, and
    # used "${NAME}" (which may be a path) for the test/bench/fuzz
    # filenames instead of the basename. Now drift-free.
    DRY_PROJ="$(basename "$NAME")"
    echo "Would create (skip if exists in in-place mode):"
    echo "  $NAME/"
    echo "  $NAME/.gitignore"
    echo "  $NAME/LICENSE                  (GPL-3.0-only)"
    echo "  $NAME/README.md"
    echo "  $NAME/CHANGELOG.md"
    echo "  $NAME/VERSION                  (0.1.0)"
    echo "  $NAME/cyrius.cyml              (pins Cyrius version, deps, build entry)"
    if [ "$SHAPE" = "lib" ]; then
        echo "  $NAME/src/main.cyr           (library module — header only)"
        echo "  $NAME/programs/smoke.cyr     (compile-link smoke)"
    else
        echo "  $NAME/src/main.cyr"
        echo "  $NAME/src/test.cyr"
    fi
    echo "  $NAME/tests/${DRY_PROJ}.tcyr   (test suite)"
    echo "  $NAME/tests/${DRY_PROJ}.bcyr   (benchmarks)"
    echo "  $NAME/tests/${DRY_PROJ}.fcyr   (fuzz harness)"
    echo "  $NAME/.github/workflows/ci.yml"
    echo "  $NAME/.github/workflows/release.yml"
    if [ -n "$AGENT" ]; then
        echo "  $NAME/CLAUDE.md                (agent preset: $AGENT)"
    fi
    echo ""
    echo "Empty dirs created: src/ lib/ build/ tests/ docs/development/ .github/workflows/"
    echo ""
    if [ "$SHAPE" = "lib" ]; then
        echo "After init, run: cd $NAME && cyrius deps && cyrius build programs/smoke.cyr build/$DRY_PROJ-smoke"
    else
        echo "After init, run: cd $NAME && cyrius deps && cyrius build src/main.cyr build/$DRY_PROJ"
    fi
    exit 0
fi

if [ "$INPLACE" -eq 0 ] && [ -d "$NAME" ]; then
    echo "ERROR: directory '$NAME' already exists"
    # v5.6.28: hint pointed at the same command that just failed
    # (in-place mode requires NAME=`.`, not the existing-dir name).
    # Correct form is to cd into the dir and run with `.` as the
    # target — the actual contract.
    echo "  hint: cd $NAME && cyrius init --language=none ."
    exit 1
fi

PROJ="$(basename "$NAME")"
if [ "$INPLACE" -eq 1 ]; then
    echo "Initializing Cyrius project in-place: $PROJ ($NAME)"
else
    echo "Creating Cyrius project: $PROJ"
fi

# write_if_absent <path> <heredoc-marker>: stdin → file unless file
# already exists. In greenfield mode the file never exists, so this
# is a plain write; in-place mode it preserves any existing file the
# user already authored (README, CHANGELOG, .gitignore, LICENSE, etc).
write_if_absent() {
    if [ -e "$1" ]; then
        echo "  skip: $1 (already exists)"
        cat > /dev/null
        return 0
    fi
    cat > "$1"
}

# Toolchain version detection — must happen BEFORE cyrius.cyml is
# written so the manifest's `cyrius = "X.Y.Z"` pin is correct.
# Cascade: env → install VERSION → live cc5 → install snapshot. NEVER
# hardcode a fallback (stale fallbacks silently seed ancient versions
# into new projects — the v5.4.12 release-lib.sh drift class). The CI
# and release templates below grep this same field out of cyrius.cyml,
# so it is the single source of truth for downstream consumers.
CYRIUS_VER="${CYRIUS_VER:-}"
if [ -z "$CYRIUS_VER" ] && [ -f "$CYRIUS/VERSION" ]; then
    CYRIUS_VER=$(tr -d '[:space:]' < "$CYRIUS/VERSION")
fi
if [ -z "$CYRIUS_VER" ] && command -v cc5 >/dev/null 2>&1; then
    CYRIUS_VER=$(cc5 --version 2>&1 | head -1 | awk '{print $2}')
fi
if [ -z "$CYRIUS_VER" ] && [ -f "$HOME/.cyrius/current" ]; then
    CYRIUS_VER=$(tr -d '[:space:]' < "$HOME/.cyrius/current")
fi
if [ -z "$CYRIUS_VER" ]; then
    echo "  error: no cyrius toolchain detected — install first or set CYRIUS_VER" >&2
    exit 1
fi

# Create structure (mkdir -p is idempotent — safe in both modes).
# v5.6.28: dropped `scripts/` (no writer ever populated it; the
# stale next-steps `sh scripts/build.sh` hint was the only ref —
# also fixed) and `lib/agnosys/` (the stdlib copy loop below dumps
# *.cyr into lib/ flat; the agnosys subdir was a stale carve-out
# from an older AGNOS-namespaced layout). `build/` stays — the
# `cyrius build` invocation in next-steps writes into it.
# v5.7.16: doc-tree per first-party-documentation.md standard.
# adr/ + architecture/ + guides/ + examples/ + development/ are the
# baseline every AGNOS first-party repo carries from day one.
mkdir -p "$NAME/src" "$NAME/lib" "$NAME/build" "$NAME/tests" \
         "$NAME/docs/adr" "$NAME/docs/architecture" "$NAME/docs/guides" \
         "$NAME/docs/examples" "$NAME/docs/development" \
         "$NAME/.github/workflows"

# === VERSION ===
if [ -e "$NAME/VERSION" ]; then
    echo "  skip: $NAME/VERSION (already exists)"
else
    echo "0.1.0" > "$NAME/VERSION"
fi

# === .gitignore ===
write_if_absent "$NAME/.gitignore" << 'GITIGNORE'
/build/
*.core
.claude/
.idea/
.vscode/
*.swp
*.swo
*~
.DS_Store
.env
.env.*
*.pem
*.key
GITIGNORE

# === LICENSE ===
write_if_absent "$NAME/LICENSE" << 'LICENSE'
GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 3 of the License only.

See https://www.gnu.org/licenses/gpl-3.0.html for full text.
LICENSE

# === README.md ===
# v5.7.15: README's build snippet matches scaffold shape.
if [ "$SHAPE" = "lib" ]; then
    write_if_absent "$NAME/README.md" << EOF
# $PROJ

Library written in [Cyrius](https://github.com/MacCracken/cyrius).
Re-exported as \`dist/$PROJ.cyr\` via \`cyrius distlib\`.

## Build

\`\`\`sh
cyrius deps                                              # resolve stdlib deps
cyrius build programs/smoke.cyr build/$PROJ-smoke         # compile-link smoke
cyrius distlib                                           # produce dist/$PROJ.cyr
cyrius test                                              # run tests/*.tcyr
\`\`\`

## License

GPL-3.0-only
EOF
else
    write_if_absent "$NAME/README.md" << EOF
# $PROJ

Written in [Cyrius](https://github.com/MacCracken/cyrius).

## Build

\`\`\`sh
cyrius deps                              # resolve stdlib deps
cyrius build src/main.cyr build/$PROJ    # compile
cyrius test                              # run [build].test + tests/*.tcyr
\`\`\`

## License

GPL-3.0-only
EOF
fi

# === CHANGELOG.md ===
write_if_absent "$NAME/CHANGELOG.md" << 'CHANGELOG'
# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.0]

### Added
- Initial project scaffold
CHANGELOG

# === cyrius.cyml ===
# v5.6.28: PROJ_DESC defaults to "<name> — TODO" placeholder when
# --description wasn't passed, instead of an empty string that
# downstream tooling has to special-case.
PROJ_DESC="${DESCRIPTION:-$PROJ — TODO}"
# v5.7.15: cyrius.cyml [build]/[lib] shape branches on $SHAPE.
# bin: entry=src/main.cyr + test=src/test.cyr + output=<name>
# lib: entry=programs/smoke.cyr + output=build/<name>-smoke + [lib] modules=[src/main.cyr]
if [ "$SHAPE" = "lib" ]; then
    write_if_absent "$NAME/cyrius.cyml" << EOF
[package]
name = "$PROJ"
version = "0.1.0"
description = "$PROJ_DESC"
license = "GPL-3.0-only"
language = "cyrius"
cyrius = "$CYRIUS_VER"

[build]
entry = "programs/smoke.cyr"
output = "build/$PROJ-smoke"

[lib]
modules = ["src/main.cyr"]

[deps]
stdlib = ["string", "fmt", "alloc", "io", "vec", "str", "syscalls", "assert", "bench"]
---
EOF
else
    write_if_absent "$NAME/cyrius.cyml" << EOF
[package]
name = "$PROJ"
version = "0.1.0"
description = "$PROJ_DESC"
license = "GPL-3.0-only"
language = "cyrius"
cyrius = "$CYRIUS_VER"

[build]
entry = "src/main.cyr"
test = "src/test.cyr"
output = "$PROJ"

[deps]
stdlib = ["string", "fmt", "alloc", "io", "vec", "str", "syscalls", "assert", "bench"]
---
EOF
fi

# === src/main.cyr ===
# v5.7.15: lib shape emits a header-only main.cyr — no top-level
# main()/syscall, since src/main.cyr will be `include`d into
# programs/smoke.cyr (and into dist/<name>.cyr via cyrius distlib).
# bin shape emits the existing greenfield entry.
if [ "$SHAPE" = "lib" ]; then
    write_if_absent "$NAME/src/main.cyr" << EOF
# $PROJ — library module. Re-exported via dist/$PROJ.cyr (cyrius distlib).
# Add domain modules below or in sibling files; programs/smoke.cyr proves
# the include chain compiles end-to-end.
EOF
else
    write_if_absent "$NAME/src/main.cyr" << EOF
# $PROJ — main entry point
# Stdlib auto-included via cyrius.cyml

fn main() {
    alloc_init();
    println("hello from $PROJ");
    return 0;
}

var r = main();
syscall(SYS_EXIT, r);
EOF
fi

# === src/test.cyr / programs/smoke.cyr ===
# v5.7.15: bin shape gets src/test.cyr (referenced by [build].test).
# lib shape gets programs/smoke.cyr instead — the compile-link proof
# program matching the mabda / sigil / sankoch convention.
if [ "$SHAPE" = "lib" ]; then
    mkdir -p "$NAME/programs"
    write_if_absent "$NAME/programs/smoke.cyr" << EOF
# $PROJ smoke test — proves the library compiles end-to-end and the
# stdlib include chain resolves. CI builds this to confirm no
# regression in the dist bundle.
#
# Build: cyrius build programs/smoke.cyr build/$PROJ-smoke
# Run:   ./build/$PROJ-smoke   (exit 0 on success)

include "src/main.cyr"

fn main() {
    alloc_init();
    println("$PROJ smoke ok");
    return 0;
}

var r = main();
syscall(SYS_EXIT, r);
EOF
else
    # v5.6.28: src/test.cyr — referenced by cyrius.cyml [build].test +
    # .github/workflows/ci.yml. Pre-v5.6.28 was announced but never
    # written — fresh scaffold failed `cyrius test` with ENOENT.
    write_if_absent "$NAME/src/test.cyr" << EOF
# $PROJ — top-level test entry (referenced by cyrius.cyml [build].test).
# For unit tests, prefer adding cases to tests/${PROJ}.tcyr.

include "lib/syscalls.cyr"

fn main() {
    return 0;
}

var r = main();
syscall(SYS_EXIT, r);
EOF
fi

# === tests/test.tcyr ===
# (tests/ already created by the top-level mkdir block above)
write_if_absent "$NAME/tests/${PROJ}.tcyr" << EOF
# $PROJ test suite
# Stdlib auto-included via cyrius.cyml

fn main() {
    alloc_init();
    test_group("smoke");
    assert(1, "true is true");
    assert_eq(1 + 1, 2, "math works");
    return assert_summary();
}

var exit_code = main();
syscall(60, exit_code);
EOF

# === tests/bench.bcyr ===
write_if_absent "$NAME/tests/${PROJ}.bcyr" << EOF
# $PROJ benchmarks
# Stdlib auto-included via cyrius.cyml
#
# Pattern: bench_new -> bench_batch_start -> tight loop -> bench_batch_stop -> bench_report.
# For sub-1us ops use batch_size >= 1000 to amortize clock_gettime overhead
# (~240 ns per start/stop pair on x86_64 Linux). See lib/bench.cyr header for
# the full overhead-vs-batching guidance.

fn bench_noop(): i64 { return 0; }

fn main(): i64 {
    alloc_init();
    var b = bench_new("noop");
    bench_batch_start(b);
    var i = 0;
    while (i < 1000000) { bench_noop(); i = i + 1; }
    bench_batch_stop(b, 1000000);
    bench_report(b);
    return 0;
}

var r = main();
syscall(60, r);
EOF

# === tests/fuzz.fcyr ===
write_if_absent "$NAME/tests/${PROJ}.fcyr" << EOF
# $PROJ fuzz harness

fn fuzz_main(data, len) {
    if (len == 0) { return 0; }
    return 0;
}

fn main() {
    alloc_init();
    fuzz_main("test", 4);
    println("fuzz: ok");
    return 0;
}

var r = main();
syscall(60, r);
EOF

# === CI ===
write_if_absent "$NAME/.github/workflows/ci.yml" << 'CI'
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-test:
    name: Build & Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4 (pinned 2026-06-19)

      - name: Install Cyrius toolchain
        run: |
          CYRIUS_VERSION="${CYRIUS_VERSION:-$(grep 'cyrius *= *"' cyrius.cyml 2>/dev/null | head -1 | sed 's/.*"\(.*\)"/\1/')}"
          echo "Installing Cyrius $CYRIUS_VERSION"
          TARBALL="cyrius-$CYRIUS_VERSION-x86_64-linux.tar.gz"
          BASE="https://github.com/MacCracken/cyrius/releases/download/$CYRIUS_VERSION"
          curl -sfLO "$BASE/$TARBALL"
          # CVE-21: verify the published .sha256 fail-closed before extracting.
          curl -sfLO "$BASE/$TARBALL.sha256" || { echo "could not fetch $TARBALL.sha256 - refusing unverified toolchain"; exit 1; }
          sha256sum -c "$TARBALL.sha256" || { echo "checksum mismatch for $TARBALL - aborting"; exit 1; }
          tar xzf "$TARBALL"
          CYRIUS_DIR="cyrius-$CYRIUS_VERSION-x86_64-linux"
          mkdir -p "$HOME/.cyrius/bin" "$HOME/.cyrius/lib"
          cp "$CYRIUS_DIR/bin/"* "$HOME/.cyrius/bin/" 2>/dev/null || true
          cp -r "$CYRIUS_DIR/lib/"* "$HOME/.cyrius/lib/" 2>/dev/null || true
          chmod +x "$HOME/.cyrius/bin/"* 2>/dev/null || true
          echo "$HOME/.cyrius/bin" >> $GITHUB_PATH
          echo "CYRIUS_HOME=$HOME/.cyrius" >> $GITHUB_ENV

      - name: Resolve dependencies
        run: cyrius deps

      - name: Build
        run: |
          mkdir -p build
          cyrius build src/main.cyr build/${{ github.event.repository.name }}

      - name: Test
        # v5.6.28: bare `cyrius test` picks up the [build].test entry
        # AND auto-discovers tests/*.tcyr — avoids the previous
        # `cyrius test src/test.cyr` form that hard-failed when the
        # stub didn't exist (Issue 1) and also wouldn't ever exercise
        # tests/${proj}.tcyr.
        run: cyrius test
CI

# === Release workflow ===
write_if_absent "$NAME/.github/workflows/release.yml" << 'RELEASE'
name: Release

on:
  push:
    tags: ['[0-9]*']

permissions:
  contents: write

jobs:
  ci:
    name: CI Gate
    uses: ./.github/workflows/ci.yml

  release:
    name: Build & Release
    needs: [ci]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4 (pinned 2026-06-19)

      - name: Verify version
        run: |
          FILE_VERSION=$(cat VERSION | tr -d '[:space:]')
          TAG_VERSION="${GITHUB_REF_NAME}"
          test "$FILE_VERSION" = "$TAG_VERSION" || { echo "VERSION ($FILE_VERSION) != tag ($TAG_VERSION)"; exit 1; }

      - name: Install Cyrius toolchain
        run: |
          CYRIUS_VERSION="${CYRIUS_VERSION:-$(grep 'cyrius *= *"' cyrius.cyml 2>/dev/null | head -1 | sed 's/.*"\(.*\)"/\1/')}"
          echo "Installing Cyrius $CYRIUS_VERSION"
          TARBALL="cyrius-$CYRIUS_VERSION-x86_64-linux.tar.gz"
          BASE="https://github.com/MacCracken/cyrius/releases/download/$CYRIUS_VERSION"
          curl -sfLO "$BASE/$TARBALL"
          # CVE-21: verify the published .sha256 fail-closed before extracting.
          curl -sfLO "$BASE/$TARBALL.sha256" || { echo "could not fetch $TARBALL.sha256 - refusing unverified toolchain"; exit 1; }
          sha256sum -c "$TARBALL.sha256" || { echo "checksum mismatch for $TARBALL - aborting"; exit 1; }
          tar xzf "$TARBALL"
          CYRIUS_DIR="cyrius-$CYRIUS_VERSION-x86_64-linux"
          mkdir -p "$HOME/.cyrius/bin" "$HOME/.cyrius/lib"
          cp "$CYRIUS_DIR/bin/"* "$HOME/.cyrius/bin/" 2>/dev/null || true
          cp -r "$CYRIUS_DIR/lib/"* "$HOME/.cyrius/lib/" 2>/dev/null || true
          chmod +x "$HOME/.cyrius/bin/"* 2>/dev/null || true
          echo "$HOME/.cyrius/bin" >> $GITHUB_PATH
          echo "CYRIUS_HOME=$HOME/.cyrius" >> $GITHUB_ENV

      - name: Build
        run: |
          cyrius deps
          mkdir -p build
          cyrius build src/main.cyr build/${{ github.event.repository.name }}

      - name: Create release
        uses: softprops/action-gh-release@3bb12739c298aeb8a4eeaf626c5b8d85266b0e65 # v2 (pinned 2026-06-19)
        with:
          generate_release_notes: true
          files: build/*
RELEASE

# v5.7.15: lib-shape projects build programs/smoke.cyr (not src/main.cyr).
# Post-process the CI/release workflows the heredocs hardcoded for binary
# shape. Portable sh form: tempfile + mv, no sed -i.
if [ "$SHAPE" = "lib" ]; then
    for wf in "$NAME/.github/workflows/ci.yml" "$NAME/.github/workflows/release.yml"; do
        if [ -f "$wf" ]; then
            sed "s|cyrius build src/main.cyr build/\${{ github.event.repository.name }}|cyrius build programs/smoke.cyr build/\${{ github.event.repository.name }}-smoke|" "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf"
        fi
    done
fi

# === docs/adr/README.md (v5.7.16) ===
write_if_absent "$NAME/docs/adr/README.md" << EOF
# Architecture Decision Records

Decisions about $PROJ — what we chose, the context, and the consequences we accept. Use these when a future reader would reasonably ask *"why did we do it this way?"*

## Conventions

- **Filename**: \`NNNN-kebab-case-title.md\`, zero-padded to four digits. Never renumber.
- **One decision per ADR.** If a decision supersedes a prior one, add a new ADR and set the old one's status to \`Superseded by NNNN\`.
- **Status lifecycle**: \`Proposed\` → \`Accepted\` → (optionally) \`Superseded\` or \`Deprecated\`.
- Use [\`template.md\`](template.md) as the starting point.

## ADR vs. architecture note vs. guide

| Kind | Lives in | Answers |
|---|---|---|
| ADR | \`docs/adr/\` | *Why did we choose X over Y?* |
| Architecture note | \`docs/architecture/\` | *What non-obvious constraint is true about the code?* |
| Guide | \`docs/guides/\` | *How do I do X?* |

## Index

_No ADRs yet. Add the first as \`0001-kebab-case-title.md\`._
EOF

# === docs/adr/template.md (v5.7.16) ===
write_if_absent "$NAME/docs/adr/template.md" << 'ADREOF'
# NNNN — Title in sentence case

**Status**: Proposed | Accepted | Superseded by NNNN | Deprecated
**Date**: YYYY-MM-DD

## Context

What's the situation that forces a decision? What constraints are in play? What makes this a real choice rather than a default? Keep it factual — the reader wasn't in the room.

## Decision

The one-sentence version of what we're doing, then any elaboration. Be specific about scope — what's in, what's out.

## Consequences

Both directions:

- **Positive** — what this buys us.
- **Negative** — what we give up, what gets harder, what we now own that we didn't before.
- **Neutral** — follow-on work this creates that isn't clearly a win or loss.

## Alternatives considered

The paths we didn't take, and why each lost. Even a brief note is better than silence — "considered and rejected X because Y" is a valuable signal to a future reader asking the same question.
ADREOF

# === docs/architecture/README.md (v5.7.16) ===
write_if_absent "$NAME/docs/architecture/README.md" << 'ARCHEOF'
# Architecture notes

Non-obvious constraints, quirks, and invariants that a reader cannot derive from the code alone. Numbered chronologically — never renumber.

Not decisions (those live in [`../adr/`](../adr/)) and not guides (those live in [`../guides/`](../guides/)). An item here describes *how the world is*, not *what we chose* or *how to do something*.

## Items

_Empty. Add a numbered entry (`001-kebab-case-title.md`) the first time the code has a non-obvious invariant a reader can't derive. Do not write entries for decisions — those are ADRs._
ARCHEOF

# === docs/guides/getting-started.md (v5.7.16) ===
if [ "$SHAPE" = "lib" ]; then
    write_if_absent "$NAME/docs/guides/getting-started.md" << EOF
# Getting started with $PROJ

## Build

\`\`\`sh
cyrius deps                                            # resolve sibling deps
cyrius build programs/smoke.cyr build/$PROJ-smoke       # compile-link smoke
cyrius distlib                                         # produce dist/$PROJ.cyr
cyrius test                                            # run tests/*.tcyr
\`\`\`

## Layout

- \`src/main.cyr\` — library module (header). Add domain modules in sibling \`src/\` files; \`programs/smoke.cyr\` proves the include chain compiles.
- \`programs/smoke.cyr\` — minimal end-to-end smoke. CI builds this on every push.
- \`tests/$PROJ.tcyr\` — test cases. Use \`assert_eq\` / \`assert\` and exit with \`assert_summary()\`.
- \`dist/$PROJ.cyr\` — single-file bundle produced by \`cyrius distlib\`. Consumers \`include\` this from their own \`cyrius.cyml [deps.$PROJ] modules = ["dist/$PROJ.cyr"]\`.

## Adding a feature

1. Edit \`src/main.cyr\` (or add a new module and \`include\` it).
2. Add a test case to \`tests/$PROJ.tcyr\`.
3. Run \`cyrius test\`.
4. \`cyrius distlib\` to regenerate the bundle.
5. Bump \`VERSION\` and add a CHANGELOG entry before tagging.

See [\`../adr/template.md\`](../adr/template.md) when a non-trivial design choice deserves an ADR.
EOF
else
    write_if_absent "$NAME/docs/guides/getting-started.md" << EOF
# Getting started with $PROJ

## Build

\`\`\`sh
cyrius deps                              # resolve dependencies
cyrius build src/main.cyr build/$PROJ    # compile
cyrius test                              # run [build].test + tests/*.tcyr
\`\`\`

## Layout

- \`src/main.cyr\` — entry point. Top-level \`var r = main(); syscall(SYS_EXIT, r);\`.
- \`src/test.cyr\` — top-level test entry referenced by \`cyrius.cyml [build].test\`. Add unit cases here or in \`tests/$PROJ.tcyr\`.
- \`tests/$PROJ.tcyr\` — primary test suite (\`cyrius test\` auto-discovers).
- \`tests/$PROJ.bcyr\` — benchmarks (\`cyrius bench\`).
- \`tests/$PROJ.fcyr\` — fuzz harness (\`cyrius fuzz\`).

## Adding a feature

1. Edit \`src/main.cyr\` (or add a new module and \`include\` it).
2. Add a test case to \`tests/$PROJ.tcyr\`.
3. Run \`cyrius test\`.
4. Bump \`VERSION\` and add a CHANGELOG entry before tagging.

See [\`../adr/template.md\`](../adr/template.md) when a non-trivial design choice deserves an ADR.
EOF
fi

# === docs/examples/.gitkeep (v5.7.16) ===
write_if_absent "$NAME/docs/examples/.gitkeep" << 'EXEOF'
EXEOF

# === docs/development/state.md (v5.7.16) ===
write_if_absent "$NAME/docs/development/state.md" << EOF
# $PROJ — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**0.1.0** — scaffolded $(date +%Y-%m-%d) via \`cyrius init\`. No releases yet.

## Toolchain

- **Cyrius pin**: \`$CYRIUS_VER\` (in \`cyrius.cyml [package].cyrius\`)

## Source

Initial scaffold only.

## Tests

- \`tests/$PROJ.tcyr\` — primary suite (smoke + math; passes on \`cyrius test\`)
- \`tests/$PROJ.bcyr\` — benchmark stub (no-op)
- \`tests/$PROJ.fcyr\` — fuzz stub

## Dependencies

Direct (declared in \`cyrius.cyml\`):

- stdlib — string, fmt, alloc, io, vec, str, syscalls, assert

## Consumers

_None yet._

## Next

See [\`roadmap.md\`](roadmap.md).
EOF

# === docs/development/roadmap.md (v5.7.16) ===
write_if_absent "$NAME/docs/development/roadmap.md" << EOF
# $PROJ — Roadmap

> Milestone plan through v1.0. State lives in [\`state.md\`](state.md);
> this file is the sequencing — what ships, in what order, against
> what dependency gates.

## v1.0 criteria

_Define before tagging v0.1.0:_

- [ ] Public API frozen — every exported symbol documented and tested
- [ ] Test coverage adequate for the surface area
- [ ] Benchmarks captured in \`docs/benchmarks.md\`
- [ ] At least one downstream consumer green
- [ ] CHANGELOG complete from v0.1.0 onward
- [ ] Security audit pass (\`docs/audit/YYYY-MM-DD-audit.md\`)

## Milestones

### M0 — Scaffold (v0.1.0) — ✅ shipped $(date +%Y-%m-%d)

- \`cyrius init\` scaffold landed
- Doc-tree per [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-documentation.md)
- ADRs / architecture notes / guides / examples folders ready

### M1 — _Title_ (v0.2.0)

_Replace this with the first real milestone. Specify the user-visible change, the dep gates, and the acceptance criteria._

### M2 — _Title_ (v0.3.0)

_…_

## Out of scope (for v1.0)

_Capture what's deliberately NOT in scope for v1.0. The list keeps future contributors from adding to v1.0 by accident._

- _e.g. Windows support, GUI front-end, etc._
EOF

# === CLAUDE.md (v5.7.16: default-on, first-party-doc aligned) ===
# v5.7.16: CLAUDE.md is now scaffolded by default per the
# first-party-documentation.md "Required Root Files" list. The
# legacy --agent flag is accepted as a no-op (warns) for
# back-compat with v5.7.15-and-earlier callers; the emitted
# template doesn't vary per preset anymore — durable preferences
# only, with a pointer to docs/development/state.md for volatile
# state.
if [ -n "$AGENT" ]; then
    case "$AGENT" in
        generic|agnos|claude) ;;
        *) echo "  note: --agent=$AGENT — preset is deprecated; the v5.7.16 default CLAUDE.md template applies regardless" ;;
    esac
fi
if [ "$SHAPE" = "lib" ]; then
    BUILD_HINT="cyrius build programs/smoke.cyr build/$PROJ-smoke"
    PROJ_TYPE="Library"
else
    BUILD_HINT="cyrius build src/main.cyr build/$PROJ"
    PROJ_TYPE="Binary"
fi
write_if_absent "$NAME/CLAUDE.md" << EOF
# $PROJ — Claude Code Instructions

> **Core rule**: this file is **preferences, process, and procedures** —
> durable rules that change rarely. Volatile state (current version,
> module line counts, supported backends, test counts, dep-gap status,
> consumers) lives in [\`docs/development/state.md\`](docs/development/state.md).
> Do not inline state here.

## Project Identity

**$PROJ** — $PROJ_DESC

- **Type**: $PROJ_TYPE
- **License**: GPL-3.0-only
- **Language**: Cyrius (toolchain pinned in \`cyrius.cyml [package].cyrius\`)
- **Version**: \`VERSION\` at the project root is the source of truth — do not inline the number here
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-standards.md) · [First-Party Documentation](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-documentation.md)

## Goal

_TODO: one-or-two-sentence mission statement. What does $PROJ OWN in the stack? Durable — doesn't change per release._

## Current State

> Volatile state lives in [\`docs/development/state.md\`](docs/development/state.md) —
> current version, surface area, in-flight work, consumers, dep gaps.
> Refreshed every release.

This file (\`CLAUDE.md\`) is durable rules.

## Scaffolding

Project was scaffolded with \`cyrius init\` (greenfield) or \`cyrius port\` (Rust → Cyrius migration). **Do not manually create project structure** — use the tools. If a tool is missing something, fix the tool.

## Quick Start

\`\`\`sh
cyrius deps                          # resolve sibling deps
$BUILD_HINT
cyrius test                          # run [build].test + tests/*.tcyr
\`\`\`

## Key Principles

- **Correctness over cleverness** — if it's wrong, the bugs own you
- Test after every change, not after the feature is "done"
- ONE change at a time — never bundle unrelated changes
- Research before implementation — check vidya / existing patterns
- Build with \`cyrius build\`, not raw \`cat file | cc5\` — the manifest auto-resolves deps and prepends includes
- Source files only need project includes — stdlib / external deps auto-resolve from \`cyrius.cyml\`
- Every buffer declaration is a contract: \`var buf[N]\` = N **bytes**, not N entries
- \`&&\` / \`||\` short-circuit; mixed expressions require explicit parens

## Rules (Hard Constraints)

- **Do not commit or push** — the user handles all git operations
- **Never use \`gh\` CLI** — use \`curl\` to the GitHub API if needed
- Do not skip tests before claiming changes work
- Do not use \`sys_system()\` with unsanitized input — command injection
- Do not trust external data (file / network / args) without validation
- Do not modify \`lib/\` files (vendored stdlib / dep symlinks)
- Do not hardcode toolchain versions in CI YAML — \`cyrius = "X.Y.Z"\` in \`cyrius.cyml\` is the source of truth

## Documentation

- [\`docs/adr/\`](docs/adr/) — Architecture Decision Records (*why X over Y?*)
- [\`docs/architecture/\`](docs/architecture/) — Non-obvious constraints (*what's true about the code?*)
- [\`docs/guides/\`](docs/guides/) — Task-oriented how-tos
- [\`docs/examples/\`](docs/examples/) — Runnable examples
- [\`docs/development/state.md\`](docs/development/state.md) — Live state snapshot
- [\`docs/development/roadmap.md\`](docs/development/roadmap.md) — Milestones through v1.0

## Process

1. **Work phase** — features, roadmap items, bug fixes
2. **Build check** — \`cyrius build\`
3. **Test + benchmark additions** for new code
4. **Internal review** — performance, memory, correctness, edge cases
5. **Documentation** — update CHANGELOG, \`docs/development/state.md\`, any ADR the change earned
6. **Version sync** — \`VERSION\`, \`cyrius.cyml\`, CHANGELOG header

EOF

# === CLI tool integrations ===
if [ -n "$CMTOOLS" ]; then
    case "$CMTOOLS" in
        starship|all)
            STARSHIP_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
            if [ -f "$STARSHIP_CONF" ]; then
                if ! grep -q 'custom.cyrius' "$STARSHIP_CONF" 2>/dev/null; then
                    cat >> "$STARSHIP_CONF" << 'STARSHIP'

[custom.cyrius]
command = "cyrius version 2>/dev/null | awk '{print $2}'"
when = "test -f cyrius.cyml -o -f cyrius.toml"
symbol = "𝕮"
style = "bg:teal"
format = '[[ $symbol( $output) ](fg:base bg:teal)]($style)'
detect_files = ["cyrius.cyml", "cyrius.toml"]
STARSHIP
                    echo "  starship: added Cyrius segment to $STARSHIP_CONF"
                else
                    echo "  starship: Cyrius segment already configured"
                fi
            else
                echo "  starship: no config found at $STARSHIP_CONF (skipped)"
            fi
            ;;
        *)
            echo "  note: unknown cmtools preset '$CMTOOLS', available: starship"
            ;;
    esac
fi

# === Vendor stdlib ===
echo "Vendoring Cyrius stdlib..."
CYRIUS_HOME="${CYRIUS_HOME:-$HOME/.cyrius}"
CYRIUS_VER=$(cat "$CYRIUS_HOME/current" 2>/dev/null)
CYRIUS_LIB=""
if [ -n "$CYRIUS_VER" ] && [ -d "$CYRIUS_HOME/versions/$CYRIUS_VER/lib" ]; then
    CYRIUS_LIB="$CYRIUS_HOME/versions/$CYRIUS_VER/lib"
elif [ -d "$CYRIUS/lib" ]; then
    CYRIUS_LIB="$CYRIUS/lib"
fi
if [ -n "$CYRIUS_LIB" ]; then
    # In-place: don't overwrite anything the user authored under lib/.
    # Greenfield: clobber-OK (lib/ is empty by definition).
    if [ "$INPLACE" -eq 1 ]; then
        CP_FLAGS="-n"
    else
        CP_FLAGS=""
    fi
    for f in "$CYRIUS_LIB"/*.cyr; do
        [ -f "$f" ] && cp $CP_FLAGS "$f" "$NAME/lib/" 2>/dev/null || true
    done
else
    echo "  warn: Cyrius stdlib not found, lib/ will be empty"
fi

# === Done ===
LIB_COUNT=$(find "$NAME/lib" -name '*.cyr' 2>/dev/null | wc -l)
echo ""
if [ "$INPLACE" -eq 1 ]; then
    echo "Initialized $NAME (in-place, --language=none)"
else
    echo "Created $NAME/"
fi
echo "  $LIB_COUNT stdlib modules vendored"
if [ "$SHAPE" = "lib" ]; then
    echo "  src/main.cyr — library module (header)"
    echo "  programs/smoke.cyr — compile-link smoke"
else
    echo "  src/main.cyr — entry point"
    echo "  src/test.cyr — test file"
fi
echo ""
echo "Next steps:"
# v5.6.28: previously suggested `sh scripts/build.sh` and
# `sh scripts/test.sh` for greenfield projects, but no
# write_if_absent call ever creates those scripts. The `scripts/`
# dir is mkdir'd empty by `mkdir -p` above. Use `cyrius` commands
# directly — the same as the in-place branch.
if [ "$INPLACE" -eq 0 ]; then
    echo "  cd $NAME"
fi
echo "  cyrius deps"
if [ "$SHAPE" = "lib" ]; then
    echo "  cyrius build programs/smoke.cyr build/$PROJ-smoke"
    echo "  cyrius distlib    # produce dist/$PROJ.cyr"
else
    echo "  cyrius build src/main.cyr build/$PROJ"
fi
echo "  cyrius test"
