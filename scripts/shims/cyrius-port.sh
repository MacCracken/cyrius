#!/bin/sh
# cyrius port — prepare a non-Cyrius project for Cyrius porting.
# Moves source code to <lang>-old/, scaffolds Cyrius project structure,
# generates cyrius.cyml with deps, CI/release workflows.
#
# Usage: cyrius port [--language=<lang>] [--dry-run] <path-to-project>
#
# v5.6.0: --language=<x> selects the source language. Default `rust`
# (current behavior, made explicit). Future: `go`, `python`, etc.

set -e

DRY_RUN=0
LANGUAGE="rust"
TARGET=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --language=*) LANGUAGE="${arg#--language=}" ;;
        --language) echo "error: --language requires a value (rust)"; exit 1 ;;
        -*) echo "Unknown flag: $arg"; exit 1 ;;
        *) TARGET="$arg" ;;
    esac
done

if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
    echo "Usage: cyrius port [--language=<lang>] [--dry-run] <path-to-project>"
    echo ""
    echo "Options:"
    echo "  --language=<x>  source language being ported FROM (default: rust)"
    echo "                  supported: rust  (future: go, python, …)"
    echo "  --dry-run       show what would be moved/created without writing"
    echo ""
    echo "Greenfield (no source to port) → use 'cyrius init [--language=none] <name>'"
    exit 1
fi

case "$LANGUAGE" in
    rust) ;;
    none)
        echo "error: --language=none has no source to port"
        echo "  hint: use 'cyrius init --language=none $TARGET' for greenfield scaffold"
        exit 1
        ;;
    go|python|c|cpp|zig|ocaml|haskell)
        echo "error: --language=$LANGUAGE not yet supported (planned for future v5.6.x)"
        echo "  currently supported: rust"
        exit 1
        ;;
    *)
        echo "error: unsupported --language=$LANGUAGE (supported: rust)"
        exit 1
        ;;
esac

cd "$TARGET"
NAME=$(basename "$(pwd)")

if [ ! -f "Cargo.toml" ]; then
    echo "error: no Cargo.toml found in $TARGET (--language=rust expects a Rust project)"
    exit 1
fi

if [ -d "rust-old" ]; then
    echo "error: rust-old/ already exists — project may already be ported"
    exit 1
fi

# Count Rust LOC
RUST_LOC=$(find src -name "*.rs" 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run: cyrius port $NAME"
    echo ""
    echo "Would move to rust-old/:"
    echo "  src/, Cargo.toml, Cargo.lock, tests/, benches/ etc."
    echo "  Rust source: ${RUST_LOC:-0} lines"
    echo ""
    echo "Would create:"
    echo "  src/main.cyr              (entry point skeleton)"
    echo "  cyrius.cyml               ([package] + [build] + [deps])"
    echo "  cyrius.cyml [package].cyrius = \"$CYRIUS_VER\"  (pins toolchain version)"
    echo "  .github/workflows/ci.yml"
    echo "  .github/workflows/release.yml"
    echo ""
    echo "After port: cyrius build src/main.cyr build/$NAME"
    exit 0
fi

echo "=== Porting $NAME to Cyrius ==="
echo "  Rust source: ${RUST_LOC:-0} lines"

# Move Rust code
mkdir -p rust-old
for item in src benches examples fuzz tests supply-chain include py \
    Cargo.toml Cargo.lock rust-toolchain.toml deny.toml codecov.yml \
    Makefile bench-history.csv benchmarks.md target rust_out; do
    if [ -e "$item" ]; then
        mv "$item" rust-old/
    fi
done
echo "  Moved Rust to rust-old/"
echo "${RUST_LOC:-0}" > rust-old/LINES_OF_RUST.txt

# Create structure
# v5.7.16: doc-tree per first-party-documentation.md standard. Same
# layout cyrius-init.sh emits — adr/architecture/guides/examples/development.
mkdir -p src tests build \
         docs/adr docs/architecture docs/guides docs/examples docs/development \
         .github/workflows

# Detect current toolchain version (cascade: env → cc5 binary → install snapshot)
# NEVER hardcode a fallback here — stale fallbacks silently seed ancient versions
# into freshly-ported projects (the v5.4.12 release-lib.sh drift class).
CYRIUS_VER="${CYRIUS_VER:-}"
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
# Toolchain version is pinned in cyrius.cyml as `cyrius = "X.Y.Z"` —
# the manifest is the single source of truth. Legacy `.cyrius-toolchain`
# is no longer written or read; CI/release workflows below grep the
# manifest directly.

# Generate source skeleton (no manual includes — auto-included via cyrius.cyml)
cat > src/main.cyr << CYRSRC
# $NAME — Cyrius port
# Ported from ${RUST_LOC:-0} lines of Rust

# Stdlib auto-included via cyrius.cyml

fn main() {
    alloc_init();
    println("$NAME ready");
    return 0;
}

var r = main();
syscall(SYS_EXIT, r);
CYRSRC
echo "  Created src/main.cyr"

# Generate cyrius.cyml
cat > cyrius.cyml << TOML
[package]
name = "$NAME"
version = "0.1.0"
description = "$NAME — Cyrius port (from ${RUST_LOC:-0} lines of Rust)"
license = "GPL-3.0-only"
language = "cyrius"
cyrius = "$CYRIUS_VER"

[build]
entry = "src/main.cyr"
output = "$NAME"

[deps]
stdlib = ["string", "fmt", "alloc", "vec", "str", "syscalls", "io", "args", "assert"]
TOML
echo "  Created cyrius.cyml"

# === v5.7.16: doc-tree per first-party-documentation.md ===
# Mirror of the cyrius-init.sh emission (adr README + template,
# architecture README, guides/getting-started, examples/.gitkeep,
# development/state + roadmap, root CLAUDE.md).
cat > docs/adr/README.md << ADREO
# Architecture Decision Records

Decisions about $NAME — what we chose, the context, and the consequences we accept. Use these when a future reader would reasonably ask *"why did we do it this way?"*

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
ADREO

cat > docs/adr/template.md << 'ADRTPL'
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
ADRTPL

cat > docs/architecture/README.md << 'ARCHRD'
# Architecture notes

Non-obvious constraints, quirks, and invariants that a reader cannot derive from the code alone. Numbered chronologically — never renumber.

Not decisions (those live in [`../adr/`](../adr/)) and not guides (those live in [`../guides/`](../guides/)). An item here describes *how the world is*, not *what we chose* or *how to do something*.

## Items

_Empty. Add a numbered entry (`001-kebab-case-title.md`) the first time the code has a non-obvious invariant a reader can't derive. Do not write entries for decisions — those are ADRs._
ARCHRD

cat > docs/guides/getting-started.md << GSEOF
# Getting started with $NAME

## Build

\`\`\`sh
cyrius deps                              # resolve dependencies
cyrius build src/main.cyr build/$NAME    # compile
cyrius test                              # run tests/*.tcyr
\`\`\`

## Layout

- \`src/main.cyr\` — entry point. Top-level \`var r = main(); syscall(SYS_EXIT, r);\`.
- \`tests/\` — test suite (\`.tcyr\` files, auto-discovered by \`cyrius test\`).
- \`rust-old/\` — original Rust source preserved for parity checks. Do not modify; it's the reference oracle.

## Adding a feature

1. Edit \`src/main.cyr\` (or add a new module and \`include\` it).
2. Cross-check parity against \`rust-old/\`.
3. Add a test case to \`tests/$NAME.tcyr\`.
4. Run \`cyrius test\`.
5. Bump \`VERSION\` and add a CHANGELOG entry before tagging.

See [\`../adr/template.md\`](../adr/template.md) when a non-trivial design choice deserves an ADR.
GSEOF

# docs/examples/ — empty placeholder so the dir survives git.
: > docs/examples/.gitkeep

cat > docs/development/state.md << STEOF
# $NAME — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**0.1.0** — ported from Rust ($(date +%Y-%m-%d)) via \`cyrius port\`. ${RUST_LOC:-0} lines of Rust preserved at \`rust-old/\` for parity reference.

## Toolchain

- **Cyrius pin**: \`$CYRIUS_VER\` (in \`cyrius.cyml [package].cyrius\`)

## Source

- Rust reference: ${RUST_LOC:-0} lines at \`rust-old/\` (frozen, do not edit).
- Cyrius port: scaffold only — \`src/main.cyr\` stub.

## Tests

_Replace with parity test status once tests land._

## Dependencies

Direct (declared in \`cyrius.cyml\`):

- stdlib — string, fmt, alloc, vec, str, syscalls, io, args, assert

## Consumers

_None yet._

## Next

See [\`roadmap.md\`](roadmap.md). The first milestone is typically Rust→Cyrius surface parity for the ${RUST_LOC:-0}-line subset.
STEOF

cat > docs/development/roadmap.md << RMEOF
# $NAME — Roadmap

> Milestone plan through v1.0. State lives in [\`state.md\`](state.md);
> this file is the sequencing — what ships, in what order, against
> what dependency gates.

## v1.0 criteria

_Define before tagging v0.1.0:_

- [ ] Rust → Cyrius surface parity verified (function-level diff against \`rust-old/\`)
- [ ] Test coverage adequate for the surface area
- [ ] Benchmarks captured in \`docs/benchmarks.md\`
- [ ] At least one downstream consumer green
- [ ] CHANGELOG complete from v0.1.0 onward
- [ ] Security audit pass (\`docs/audit/YYYY-MM-DD-audit.md\`)

## Milestones

### M0 — Port scaffold (v0.1.0) — ✅ shipped $(date +%Y-%m-%d)

- \`cyrius port\` scaffold landed
- Rust source moved to \`rust-old/\`
- Doc-tree per [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-documentation.md)

### M1 — Surface parity (v0.2.0)

_Pick a parseable Rust subset and verify the Cyrius port matches it function-for-function. Specify the dep gates and the acceptance criteria._

### M2 — _Title_ (v0.3.0)

_…_

## Out of scope (for v1.0)

_Capture what's deliberately NOT in scope for v1.0._
RMEOF

# Default CLAUDE.md (v5.7.16 first-party-doc standard).
cat > CLAUDE.md << CLEOF
# $NAME — Claude Code Instructions

> **Core rule**: this file is **preferences, process, and procedures** —
> durable rules that change rarely. Volatile state (current version,
> module line counts, port progress, test counts, consumers) lives in
> [\`docs/development/state.md\`](docs/development/state.md).
> Do not inline state here.

## Project Identity

**$NAME** — Cyrius port of a Rust project (${RUST_LOC:-0} lines preserved at \`rust-old/\`).

- **Type**: Port (Rust → Cyrius)
- **License**: GPL-3.0-only
- **Language**: Cyrius (toolchain pinned in \`cyrius.cyml [package].cyrius\`)
- **Version**: \`VERSION\` at the project root is the source of truth — do not inline the number here
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-standards.md) · [First-Party Documentation](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-documentation.md)

## Goal

_TODO: one-or-two-sentence mission statement. What does $NAME OWN in the stack? Durable — doesn't change per release._

## Current State

> Volatile state lives in [\`docs/development/state.md\`](docs/development/state.md) —
> port progress, surface parity, in-flight work. Refreshed every release.

This file (\`CLAUDE.md\`) is durable rules.

## Scaffolding

Project was scaffolded with \`cyrius port\`. Original Rust at \`rust-old/\` is the reference oracle — do not modify it; cross-check the port against it.

## Quick Start

\`\`\`sh
cyrius deps                              # resolve dependencies
cyrius build src/main.cyr build/$NAME    # compile
cyrius test                              # run tests/*.tcyr
\`\`\`

## Key Principles

- **Cross-check against \`rust-old/\`** — the port's correctness bar is "matches what Rust did". Diverge only with an ADR.
- **Correctness over cleverness** — if the Cyrius behavior diverges silently from Rust, the bugs win
- Test after every change, not after the feature is "done"
- ONE change at a time — never bundle unrelated changes
- Build with \`cyrius build\`, not raw \`cat file | cc5\` — the manifest auto-resolves deps
- Source files only need project includes — stdlib auto-resolves from \`cyrius.cyml\`
- \`var buf[N]\` = N **bytes**, not N entries

## Rules (Hard Constraints)

- **Do not commit or push** — the user handles all git operations
- **Never use \`gh\` CLI** — use \`curl\` to the GitHub API if needed
- Do not modify \`rust-old/\` — it's the parity oracle
- Do not skip tests before claiming changes work
- Do not modify \`lib/\` files (vendored stdlib / dep symlinks)
- Do not hardcode toolchain versions in CI YAML — \`cyrius = "X.Y.Z"\` in \`cyrius.cyml\` is the source of truth

## Documentation

- [\`docs/adr/\`](docs/adr/) — Architecture Decision Records (*why X over Y?*)
- [\`docs/architecture/\`](docs/architecture/) — Non-obvious constraints
- [\`docs/guides/\`](docs/guides/) — Task-oriented how-tos
- [\`docs/examples/\`](docs/examples/) — Runnable examples
- [\`docs/development/state.md\`](docs/development/state.md) — Live state
- [\`docs/development/roadmap.md\`](docs/development/roadmap.md) — Milestones through v1.0

CLEOF

echo "  Created docs/ tree (adr/architecture/guides/examples/development) + CLAUDE.md"

# Generate .gitignore — mirrors cyrius-init.sh plus /rust-old/target/ so a
# local `cargo build` in rust-old/ (for parity checks against the port) does
# not drop hundreds of MB of build artifacts into git.
if [ ! -f .gitignore ]; then
    cat > .gitignore << 'GITIGNORE'
# Build output
/build/
/rust-old/target/

# IDE
.idea/
.vscode/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Claude Code
.claude/

# Core dumps
*.core

# Environment / secrets
.env
.env.*
*.pem
*.key

# Coverage
/coverage/
*.profraw
*.profdata
GITIGNORE
    echo "  Created .gitignore"
else
    # .gitignore exists (carried over from Rust project) — ensure rust-old/target/ is covered
    if ! grep -qE '^/?rust-old/target/?' .gitignore; then
        printf "\n# Cyrius port\n/rust-old/target/\n/build/\n" >> .gitignore
        echo "  Appended /rust-old/target/ and /build/ to existing .gitignore"
    fi
fi

# Generate CI workflow
cat > .github/workflows/ci.yml << 'CI'
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_call:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    name: Build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Cyrius toolchain
        run: |
          CYRIUS_VERSION="${CYRIUS_VERSION:-$(grep 'cyrius *= *"' cyrius.cyml 2>/dev/null | head -1 | sed 's/.*"\(.*\)"/\1/')}"
          echo "Installing Cyrius $CYRIUS_VERSION"
          curl -sLO "https://github.com/MacCracken/cyrius/releases/download/$CYRIUS_VERSION/cyrius-$CYRIUS_VERSION-x86_64-linux.tar.gz"
          tar xzf "cyrius-$CYRIUS_VERSION-x86_64-linux.tar.gz"
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

  docs:
    name: Documentation
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check required docs
        run: |
          for doc in README.md CHANGELOG.md VERSION LICENSE cyrius.cyml; do
            test -f "$doc" && echo "OK: $doc" || { echo "MISSING: $doc"; exit 1; }
          done
CI
echo "  Created .github/workflows/ci.yml"

# Generate release workflow
cat > .github/workflows/release.yml << 'RELEASE'
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
      - uses: actions/checkout@v4

      - name: Verify version
        run: |
          FILE_VERSION=$(cat VERSION | tr -d '[:space:]')
          TAG_VERSION="${GITHUB_REF_NAME}"
          test "$FILE_VERSION" = "$TAG_VERSION" || { echo "VERSION ($FILE_VERSION) != tag ($TAG_VERSION)"; exit 1; }

      - name: Install Cyrius toolchain
        run: |
          CYRIUS_VERSION="${CYRIUS_VERSION:-$(grep 'cyrius *= *"' cyrius.cyml 2>/dev/null | head -1 | sed 's/.*"\(.*\)"/\1/')}"
          echo "Installing Cyrius $CYRIUS_VERSION"
          curl -sLO "https://github.com/MacCracken/cyrius/releases/download/$CYRIUS_VERSION/cyrius-$CYRIUS_VERSION-x86_64-linux.tar.gz"
          tar xzf "cyrius-$CYRIUS_VERSION-x86_64-linux.tar.gz"
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
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
          files: build/*
RELEASE
echo "  Created .github/workflows/release.yml"

# Generate test file
cat > tests/${NAME}.tcyr << TCYR
# ${NAME} test suite

fn main() {
    alloc_init();
    test_group("smoke");
    assert(1, "true is true");
    assert_eq(1 + 1, 2, "math works");
    return assert_summary();
}

var exit_code = main();
syscall(60, exit_code);
TCYR
echo "  Created tests/${NAME}.tcyr"

# Generate bench file
cat > tests/${NAME}.bcyr << BCYR
# ${NAME} benchmarks

fn bench_noop() { return 0; }

fn main() {
    alloc_init();
    bench("noop", &bench_noop, 1000000);
    return 0;
}

var r = main();
syscall(60, r);
BCYR
echo "  Created tests/${NAME}.bcyr"

# Generate fuzz harness
cat > tests/${NAME}.fcyr << FCYR
# ${NAME} fuzz harness

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
FCYR
echo "  Created tests/${NAME}.fcyr"

echo ""
echo "=== $NAME ready for porting ==="
echo "  Rust (rust-old/): ${RUST_LOC:-0} lines"
echo "  Cyrius (src/):    skeleton + test + bench + fuzz"
echo "  Toolchain:        $CYRIUS_VER (cyrius.cyml)"
echo ""
echo "Next steps:"
echo "  1. Read rust-old/src/ to understand the API"
echo "  2. Port module by module into src/main.cyr"
echo "  3. Add deps to cyrius.cyml as needed"
echo "  4. Build: cyrius build src/main.cyr build/$NAME"
echo "  5. Test:  cyrius test tests/${NAME}.tcyr"
echo "  6. Bench: cyrius bench tests/${NAME}.bcyr"
