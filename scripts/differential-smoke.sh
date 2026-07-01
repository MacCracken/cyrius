#!/bin/sh
# scripts/differential-smoke.sh — check.sh rot-guard for the differential gate.
#
# Runs scripts/differential.sh on its tiny SMOKE corpus (git-extract OLD cycc +
# compile a few inputs with OLD & NEW in default + CYRIUS_DCE=1 modes + cmp +
# report). Asserts only that the HARNESS works end-to-end (exit 0), independent
# of working-tree diffs — so the otherwise manual-trigger differential gate
# cannot silently ROT the way the macOS self-host CI did (a gate that never runs
# is a placebo). The REAL logic-preserving verification is the full
#   sh scripts/differential.sh <old-ref>
# run by hand before a codegen refactor (the v6.3.2x perf arc).
exec sh "$(dirname "$0")/differential.sh" --smoke
