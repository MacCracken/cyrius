#!/bin/sh
# v6.5.28 — a `[deps].stdlib` entry must get its top-level `include` prepended even when an
# EARLIER entry already pulled it in transitively.
#
# THE BUG. `_dep_copy_stdlib_recursive` does two jobs — COPY the file, and PUSH
# `include "lib/<mod>.cyr"` for top-level entries — and its seen-guard `return 0` ran before
# the push. So once a module was pulled transitively (is_top=0) it was marked seen, and the
# resolver reaching that module's own `[deps].stdlib` entry short-circuited without ever
# pushing its include. `lib/X.cyr` sat on disk, `cyrius deps` reported success, the lockfile
# listed it, and every symbol in X was an undefined function with nothing naming X.
#
# ⚠ PURELY AN ORDERING ARTIFACT — which is what made it expensive. The SAME declared module
# set builds or fails depending only on which entry comes first; the manifest looks correct
# because it IS correct. Filed from kavach 3.11.14 (whole tree stopped building on a pin move).
# ⛔ Not confined to `[deps].stdlib`: `_dep_pull_leaves` calls the same fn with is_top=1 for
# the `requires` key and `dist/<pkg>.deps`, so a bundle whose sidecar lists leaves in an
# unlucky order handed the identical failure to every consumer of that bundle.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
command -v cyrius >/dev/null 2>&1 || { echo "SKIP: cyrius CLI not on PATH"; exit 0; }
R="docs/development/issues/repros/2026-08-17-stdlib-transitive-pull-drops-top-level-include.sh"
[ -f "$R" ] || { echo "SKIP: repro script $R missing"; exit 0; }
fail=0

OUT=$(sh "$R" "$(cat VERSION)" 2>&1 || true)

# The repro prints, per case, "'undefined clock_now_ns': N" and "binary emitted : YES|NO".
und=$(printf '%s\n' "$OUT" | grep -c "undefined clock_now_ns': [1-9]" || true)
emitted=$(printf '%s\n' "$OUT" | grep -c "binary emitted          : YES" || true)
cases=$(printf '%s\n' "$OUT" | grep -c "^CASE " || true)

# axis 0 — anti-vacuous: the repro must actually have run BOTH cases. A script that printed
# nothing would otherwise score a clean pass.
if [ "$cases" -ne 2 ]; then
    echo "  FAIL axis 0 (anti-vacuous): repro emitted $cases CASE blocks, expected 2 — it did not run, so nothing below is evidence"
    printf '%s\n' "$OUT" | head -6 | sed 's/^/      /'
    exit 1
fi
echo "  ok axis 0: repro ran both ordering cases"

# axis 1 — BOTH orderings must build. This is the defect: same module set, order-dependent.
if [ "$emitted" -ne 2 ]; then
    echo "  FAIL axis 1: only $emitted of 2 orderings produced a binary — the include push is still order-dependent"
    printf '%s\n' "$OUT" | sed 's/^/      /'
    fail=1
else
    echo "  ok axis 1: both orderings emit a binary"
fi

# axis 2 — and neither may report the undefined symbol.
if [ "$und" -ne 0 ]; then
    echo "  FAIL axis 2: $und case(s) still report 'undefined clock_now_ns' — the transitive module's include is missing"
    fail=1
else
    echo "  ok axis 2: neither ordering reports an undefined symbol"
fi

# axis 3 — the top-level-ONLY push must survive. Pushing transitive includes too would make
# axes 1-2 pass while re-opening a PRIOR bug: an explicit include overrides the
# `#ifdef CYRIUS_TARGET_*` arch dispatchers, so both syscall peers parse at once (duplicate
# fns, wrong-arch syscall numbers). The fix must service the seen-path push WITHOUT dropping
# the is_top condition.
if grep -q 'if (is_top == 1) { vec_push(_dep_includes, dst_full); }' cbt/deps.cyr \
   && grep -q 'if (is_top == 1) { _dep_push_include_once(mod_name); }' cbt/deps.cyr; then
    echo "  ok axis 3: both push sites remain gated on is_top (arch dispatchers preserved)"
else
    echo "  FAIL axis 3: a push site lost its is_top gate — transitive includes would override the #ifdef arch dispatchers"
    fail=1
fi

[ "$fail" -eq 0 ] || { echo "FAIL: stdlib-transitive-include-pushed"; exit 1; }
echo "PASS: stdlib-transitive-include-pushed — a transitively-pulled module still gets its top-level include, order-independently"
