#!/bin/sh
# 2026-10-10 — scripts that build the compiler from src/ but do not scrub an inherited
# CYRIUS_POISON / CYRIUS_BOUNDS, and what an inherited value does to the build. Read-only: the
# probes go to a mktemp directory. Run from the repo root: sh <this file>
# Expected: no script listed (each unsets both before its first build, as check.sh, release-gate.sh,
#           seed-derive-cycc.sh, version-bump.sh and bootstrap/bootstrap.sh do).
# Actual (the merged 6.7.8 tip): 11 scripts listed; the two env builds differ from build/cycc.
set -u
for s in scripts/*.sh; do
    case "$s" in scripts/cyrius-watch.sh) continue ;; esac   # a project watcher, not a self-build
    b=$(grep -nE 'src/main[a-z_0-9]*\.cyr' "$s" | grep -v '^[0-9]*:[[:space:]]*#' | head -1 | cut -d: -f1)
    [ -n "$b" ] || continue
    if ! grep -qE 'unset([[:space:]]+[A-Z_]+)*[[:space:]]+CYRIUS_POISON|-u CYRIUS_POISON|unset CYRIUS_POISON' "$s"; then
        echo "no CYRIUS_POISON / CYRIUS_BOUNDS scrub: $s (first src/ build at line $b)"
    fi
done
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
env -u CYRIUS_POISON -u CYRIUS_BOUNDS build/cycc < src/main.cyr > "$T/plain" 2>/dev/null
env -u CYRIUS_BOUNDS CYRIUS_POISON=1 build/cycc < src/main.cyr > "$T/poison" 2>/dev/null
env -u CYRIUS_POISON CYRIUS_BOUNDS=1 build/cycc < src/main.cyr > "$T/bounds" 2>/dev/null
cmp -s "$T/plain" build/cycc && echo "plain build == build/cycc"
cmp -s "$T/poison" build/cycc || echo "CYRIUS_POISON=1 build differs from build/cycc ($(wc -c < "$T/poison") B)"
cmp -s "$T/bounds" build/cycc || echo "CYRIUS_BOUNDS=1 build differs from build/cycc ($(wc -c < "$T/bounds") B)"
