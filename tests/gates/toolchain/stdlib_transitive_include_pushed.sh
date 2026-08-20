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
# ⚠ v6.5.31 — checks the INVARIANT, not the formatting. This used to grep for two literal
# one-liners; when the seen-path push grew a multi-line directory-family guard the assertion
# went RED against correct code, which is a structural axis failing for the one reason a
# structural axis must not. Now: every push call site must have an `is_top == 1` guard within
# the preceding few lines. Proximity-based because these guards are always tight, and a push
# that drifts away from its guard is exactly the regression worth failing on.
# ⚠ SCOPE: only the two STDLIB-leaf push sites inside `_dep_copy_stdlib_recursive` — the
# `_dep_push_include_once(mod_name)` call on the seen path and the `vec_push(..., dst_full)` on
# the copy path. The other `vec_push(_dep_includes, ...)` sites in this file push NAMED-DEP
# modules, which are not arch dispatchers and are deliberately ungated; a first draft of this
# check swept them in and went red against correct code.
# Scoped by ENCLOSING FUNCTION, not by regex on the call text. Two earlier drafts of this
# check matched the wrong lines — the `fn _dep_push_include_once(mod_name)` DEFINITION, and a
# named-dep `vec_push(_dep_includes, dst_full)` elsewhere in the file that happens to reuse
# the variable name — and went red against correct code both times. Only pushes inside
# `_dep_copy_stdlib_recursive` are arch-dispatcher-sensitive.
scan=$(awk '
    /^fn _dep_copy_stdlib_recursive\(/ { infn = 1; next }
    /^fn / { infn = 0 }
    infn && /is_top == 1/ { lastguard = NR }
    infn && /_dep_push_include_once\(|vec_push\(_dep_includes,/ {
        sites++
        if (lastguard == 0 || NR - lastguard > 12) { print "UNGUARDED " NR ": " $0 }
    }
    END { print "SITES " sites+0 }
' cbt/deps.cyr)
unguarded=$(echo "$scan" | grep '^UNGUARDED' || true)
nsites=$(echo "$scan" | awk '/^SITES/{print $2}')
if [ -n "$unguarded" ]; then
    echo "  FAIL axis 3: a push site lost its is_top gate — transitive includes would override the #ifdef arch dispatchers"
    echo "$unguarded" | sed 's/^/      /'
    fail=1
elif [ "$nsites" -lt 2 ]; then
    echo "  FAIL axis 3 (premise): only $nsites push site(s) found — the search is wrong, not the tree"
    fail=1
else
    echo "  ok axis 3: all $nsites push sites remain gated on is_top (arch dispatchers preserved)"
fi

# --- axis 4 (v6.5.31): a package-DIRECTORY leaf declared in BOTH places must still build ---
#
# ⛔ `unicode` is the one stdlib module that is a package DIRECTORY (`lib/unicode/*.cyr`) with
# no flat `lib/unicode.cyr`. The expansion that handles it sits BELOW the seen-guard, so when
# `unicode` arrived via a dep's `.deps` sidecar AND the consumer's own `[deps].stdlib`, the
# first route expanded the family and the second landed on the seen path and pushed a flat
# `include "lib/unicode.cyr"` — a file that legitimately does not exist. Hard build failure,
# with an error naming a missing stdlib module rather than the double declaration, while
# `lib/unicode/` sat fully populated. Filed from agnostic 2.0.1 consuming agnosai 2.0.2.
#
# ⚠ Introduced by the axis-1/2 fix above (v6.5.28), which was written for FLAT leaves — so
# this axis and those share one code path and must be read together: axis 1-2 require the
# seen path to push, axis 4 requires it not to push a family name.
D4=$(mktemp -d); FD=$(mktemp -d)
mkdir -p "$FD/dist" "$D4/src"
printf 'fn fakedep_ping(): i64 { return 7; }\n' > "$FD/dist/fakedep.cyr"
printf '# sidecar\nstr\nunicode\n' > "$FD/dist/fakedep.deps"
cat > "$D4/cyrius.cyml" <<EOF
[package]
name = "uni3"
version = "0.1.0"

[deps]
stdlib = ["syscalls", "alloc", "str", "string", "vec", "unicode"]

[deps.fakedep]
path = "$FD"
modules = ["dist/fakedep.cyr"]
EOF
printf 'fn main(): i64 { return fakedep_ping() * 6; }\nvar f = main();\nsyscall(60, f);\n' > "$D4/src/main.cyr"
( cd "$D4" && cyrius build src/main.cyr build/uni3 ) > "$D4/log" 2>&1 || true
if [ ! -s "$D4/build/uni3" ]; then
    echo "  FAIL axis 4: a directory-family leaf declared in BOTH [deps].stdlib and a dep sidecar failed to build"
    grep -m2 'error' "$D4/log" | sed 's/^/      /' || true
    fail=1
else
    e4=0
    "$D4/build/uni3" >/dev/null 2>&1 || e4=$?
    if [ "$e4" -ne 42 ]; then
        echo "  FAIL axis 4: built but ran wrong (exit $e4, expected 42) — the dep did not link correctly"
        fail=1
    else
        echo "  ok axis 4: a package-directory leaf declared in both places builds and runs"
    fi
fi
rm -rf "$D4" "$FD"

[ "$fail" -eq 0 ] || { echo "FAIL: stdlib-transitive-include-pushed"; exit 1; }
echo "PASS: stdlib-transitive-include-pushed — a transitively-pulled module still gets its top-level include, order-independently"
