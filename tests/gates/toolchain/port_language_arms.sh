#!/bin/sh
# Gate: `cyrius port --language=<lang>` scaffolds for the language it was given.
#
# THE GAP (filed by agnostic 2026-08-20, closed v6.5.34). `cyrius port` advertised
# `rust (future: go, python, …)` and declined everything but rust with a message naming a
# milestone the toolchain had passed a major line earlier ("planned for future v5.6.x", at
# 6.5.31). Meanwhile agnosticos's first-party standard mandates the tool:
#   "Always use Cyrius tooling to scaffold and port… If the tools are missing something,
#    fix the tools — don't work around them."
# So a consumer doing a real Python→Cyrius port was told to use a tool that refused the job.
#
# ⚠ THE HALF-FIX THIS GATE EXISTS TO FORBID. The language-specific surface is NOT just the
# flag, the marker file and the destination directory — the port TEMPLATES hardcoded "Rust"
# and "rust-old/" in 17 places across 7 files. Adding a python arm without them produces a
# project whose CLAUDE.md, roadmap, state and getting-started all say "ported from Rust,
# reference oracle at rust-old/" while the tree on disk is python-old/. That scaffolds a lie
# into every new port, so axis 3 asserts the absence of the word rather than trusting that
# the arm "works". Templates now take {SRC_LANG} / {OLD_DIR} / {SRC_LOC}.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CYRIUS="$ROOT/build/cyrius"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

if [ ! -x "$CYRIUS" ]; then
    echo "FAIL: port-language-arms — $CYRIUS not built"
    exit 1
fi

mkpy() {
    mkdir -p "$1/src/pkg"
    printf '[project]\nname = "demo"\nversion = "0.1.0"\n' > "$1/pyproject.toml"
    printf 'def a():\n    return 1\n\ndef b():\n    return 2\n' > "$1/src/pkg/core.py"
    printf 'import sys\nprint("hi")\n' > "$1/src/pkg/cli.py"
}
mkrs() {
    mkdir -p "$1/src"
    printf '[package]\nname = "demo"\n' > "$1/Cargo.toml"
    printf 'fn main() {\n    println!("hi");\n}\n' > "$1/src/main.rs"
}

# ── AXIS 1: the python arm exists and preserves the source under python-old/.
echo "axis 1 — --language=python scaffolds a Python port:"
mkpy "$D/py"
( cd "$ROOT" && "$CYRIUS" port --language=python "$D/py" ) > "$D/py.log" 2>&1
check "exits 0" 0 "$?"
if [ -d "$D/py/python-old" ]; then check "python-old/ exists" "yes" "yes"
else check "python-old/ exists" "yes" "no"; fi
if [ -f "$D/py/python-old/pyproject.toml" ]; then check "the marker moved with it" "yes" "yes"
else check "the marker moved with it" "yes" "no"; fi
if [ -f "$D/py/src/main.cyr" ]; then check "a Cyrius entry point was created" "yes" "yes"
else check "a Cyrius entry point was created" "yes" "no"; fi
# LOC must be counted from .py, not .rs — a stale extension silently reports 0 lines.
check "counted Python lines (not 0)" "1" "$(grep -c 'Python source: 7 lines' "$D/py.log" || true)"

# ── AXIS 2: the rust arm is unchanged. Mutation: point the rust branch at python-old/ or
# ".py" and this axis goes red while axis 1 stays green.
echo "axis 2 — --language=rust (the default) still behaves exactly as before:"
mkrs "$D/rs"
( cd "$ROOT" && "$CYRIUS" port "$D/rs" ) > "$D/rs.log" 2>&1
check "exits 0" 0 "$?"
if [ -d "$D/rs/rust-old" ]; then check "rust-old/ exists" "yes" "yes"
else check "rust-old/ exists" "yes" "no"; fi
check "counted Rust lines" "1" "$(grep -c 'Rust source: 3 lines' "$D/rs.log" || true)"

# ── AXIS 3: no Rust vocabulary leaks into a Python scaffold.
# This is the assertion that catches a flag-only half-fix: the arm can "work" — right
# directory, right LOC — while every generated document still tells the reader to consult
# rust-old/ as the parity oracle.
echo "axis 3 — a Python scaffold contains no Rust vocabulary:"
leaked=$(grep -rli 'rust' "$D/py" 2>/dev/null | grep -v '/python-old/' | wc -l | tr -d ' ')
if [ "$leaked" != "0" ]; then
    echo "    leaked in: $(grep -rli 'rust' "$D/py" 2>/dev/null | grep -v '/python-old/' | sed "s|$D/py/||" | tr '\n' ' ')"
fi
check "generated files mentioning Rust" 0 "$leaked"
# ANTI-VACUOUS: the same grep must FIND the word in a Rust scaffold, or axis 3 would pass
# on a scaffold that generated no documents at all.
found=$(grep -rli 'rust' "$D/rs" 2>/dev/null | grep -v '/rust-old/' | wc -l | tr -d ' ')
if [ "$found" -gt 0 ]; then check "anti-vacuous: a Rust scaffold does mention Rust" "yes" "yes"
else check "anti-vacuous: a Rust scaffold does mention Rust" "yes" "no"; fi

# ── AXIS 4: preconditions and declines are honest.
echo "axis 4 — preconditions and declines:"
mkdir -p "$D/bare"
( cd "$ROOT" && "$CYRIUS" port --language=python "$D/bare" ) > "$D/bare.log" 2>&1
check "a directory with no Python marker is refused" 1 "$?"
check "and says which markers it looked for" "1" "$(grep -c 'pyproject.toml, setup.py or setup.cfg' "$D/bare.log" || true)"
( cd "$ROOT" && "$CYRIUS" port --language=go "$D/rs" ) > "$D/go.log" 2>&1
check "an unsupported language is still declined" 1 "$?"
# The old decline cited "planned for future v5.6.x" while shipping 6.5.x. A message naming
# a milestone already passed is worse than none: it reads as "coming soon" indefinitely.
check "the decline does not cite a stale milestone" 0 "$(grep -c 'v5.6.x' "$D/go.log" || true)"
check "and names what IS supported" "1" "$(grep -c 'rust, python' "$D/go.log" || true)"
# Re-porting an already-ported tree must refuse rather than nest.
( cd "$ROOT" && "$CYRIUS" port --language=python "$D/py" ) > "$D/re.log" 2>&1
check "re-porting an already-ported tree is refused" 1 "$?"

# ── AXIS 5: setuptools-only projects count too. Requiring pyproject.toml alone would
# decline the older half of the ecosystem — the same shape of gap as declining python.
echo "axis 5 — setup.py / setup.cfg projects are accepted, not just PEP 621:"
mkdir -p "$D/legacy/src"
printf 'from setuptools import setup\nsetup(name="demo")\n' > "$D/legacy/setup.py"
printf 'def z():\n    return 3\n' > "$D/legacy/src/z.py"
( cd "$ROOT" && "$CYRIUS" port --language=python "$D/legacy" ) > "$D/legacy.log" 2>&1
check "setup.py alone is enough" 0 "$?"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: port-language-arms — rust + python arms, no cross-language vocabulary leak"
    exit 0
fi
echo "FAIL: port-language-arms — $fails assertion(s) failed"
exit 1
