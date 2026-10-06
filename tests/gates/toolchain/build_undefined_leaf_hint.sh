#!/bin/sh
# Gate: a build that fails on undefined names says WHICH stdlib leaf defines each one and how to
# fix the manifest (6.6.18, the D4 consumer-impact review).
#
# ⛔ WHY. After P4 option 2 a sidecar names only what its bundle needs, so a consumer that relied
# on a producer's OVER-reported sidecar loses a leaf it never declared. takumi declares stdlib
# `sandhi`; lib/sandhi.cyr includes nothing and needs `sakshi`, which only sigil's old sidecar
# vendored. Its build then printed `undefined function 'sakshi_span_enter' ... refusing to emit
# binary with 2 reachable undefined function(s)` — the symbols, not the cause, not the remedy.
# compile() now captures the compiler's stderr (when no caller does), relays it whole, and for
# a failed compile looks every undefined name up in the stdlib snapshot index (distlib's: family
# directories, the dispatcher rule, folds only when nothing else declares the name).
#
# Axes
#   1  a consumer calling clock_now_ns() with only `string` declared FAILS, the compiler's own
#      `undefined function 'clock_now_ns'` is still printed, and a `hint:` names leaf `chrono`
#      and `[deps] stdlib` (old: no hint)
#   2  a peer's symbol is credited to its DISPATCHER: SYS_MMAP -> `syscalls`, never a per-arch peer
#   3  no false advice: a name no stdlib leaf defines gets no hint
#   4  anti-vacuous: with `chrono` declared the same build succeeds and prints no hint
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: build_undefined_leaf_hint: no compiler at $CC"; exit 77; }
HOMEDIR=${CYRIUS_HOME:-"$HOME/.cyrius"}
VER=$(cat "$ROOT/VERSION")
[ -d "$HOMEDIR/versions/$VER/lib" ] || [ -d "$HOMEDIR/lib" ] || { echo "SKIP: build_undefined_leaf_hint: no stdlib snapshot under $HOMEDIR"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: build_undefined_leaf_hint: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
fail() { echo "FAIL: build_undefined_leaf_hint: $1"; exit 1; }
CLI=${CYRIUS_BIN:-}
mkdir -p "$W/tools"
if [ -z "$CLI" ]; then
    ( cd "$ROOT" && "$CC" < cbt/cyrius.cyr > "$W/tools/cyrius" 2>/dev/null ) || { echo "SKIP: build_undefined_leaf_hint: cbt/cyrius.cyr did not build"; exit 77; }
else
    cp "$CLI" "$W/tools/cyrius"
fi
cp "$CC" "$W/tools/cycc" && chmod +x "$W/tools/cyrius" "$W/tools/cycc"
CLI="$W/tools/cyrius"

mkproj() {  # mkproj <dir> <stdlib list> <main body>
    d="$W/$1"; mkdir -p "$d/src"
    printf '[package]\nname = "hp"\nversion = "0.1.0"\ncyrius = "%s"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/hp"\n\n[deps]\nstdlib = [%s]\n' "$VER" "$2" > "$d/cyrius.cyml"
    printf '%s\nvar r = main();\nsyscall(60, r);\n' "$3" > "$d/src/main.cyr"
    echo "$d"
}
build() { ( cd "$1" && CYRIUS_HOME="$HOMEDIR" CYRIUS_RESOLVED=1 "$CLI" build 2>&1 ); }

# ── axis 1 ───────────────────────────────────────────────────────────────────────────
A=$(mkproj a '"string"' 'fn main(): i64 { return clock_now_ns() & 1; }')
rc=0; OA=$(build "$A") || rc=$?
[ "$rc" -ne 0 ] || fail "axis 1 premise: the build succeeded without chrono"
echo "$OA" | grep -q "undefined function 'clock_now_ns'" || fail "axis 1: the compiler's own diagnostic was lost: $(echo "$OA" | head -4)"
echo "$OA" | grep -q "^hint: 'clock_now_ns' is defined by stdlib leaf 'chrono' — add it to \[deps\] stdlib in cyrius.cyml$" \
    || fail "axis 1: no hint naming leaf 'chrono' for clock_now_ns: $(echo "$OA" | grep -i 'hint\|undefined' | head -4)"

# ── axis 2 ───────────────────────────────────────────────────────────────────────────
B=$(mkproj b '"string"' 'fn main(): i64 { return SYS_MMAP & 0; }')
rc=0; OB=$(build "$B") || rc=$?
[ "$rc" -ne 0 ] || fail "axis 2 premise: the build succeeded without syscalls"
echo "$OB" | grep -q "^hint: 'SYS_MMAP' is defined by stdlib leaf 'syscalls' " \
    || fail "axis 2: SYS_MMAP was not credited to the dispatcher 'syscalls': $(echo "$OB" | grep -i 'hint\|undefined' | head -3)"

# ── axis 3 ───────────────────────────────────────────────────────────────────────────
C=$(mkproj c '"string"' 'fn main(): i64 { return _hint_no_such_fn_anywhere(); }')
rc=0; OC=$(build "$C") || rc=$?
[ "$rc" -ne 0 ] || fail "axis 3 premise: the build succeeded"
echo "$OC" | grep -q "^hint:" && fail "axis 3: a name no stdlib leaf defines got advice: $(echo "$OC" | grep '^hint:')"

# ── axis 4 ───────────────────────────────────────────────────────────────────────────
D=$(mkproj d '"string", "chrono"' 'fn main(): i64 { return clock_now_ns() & 0; }')
rc=0; OD=$(build "$D") || rc=$?
[ "$rc" -eq 0 ] || fail "axis 4: the build with chrono declared failed (rc $rc): $(echo "$OD" | tail -4)"
echo "$OD" | grep -q "^hint:" && fail "axis 4: a successful build printed a hint"

echo "PASS: build_undefined_leaf_hint (a failed build names the stdlib leaf for each undefined name, dispatcher not peer, no advice for unknown names, silent on success)"
exit 0
