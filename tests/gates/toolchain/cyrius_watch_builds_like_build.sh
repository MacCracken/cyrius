#!/bin/sh
# Gate: scripts/cyrius-watch.sh builds through `cyrius build` (6.7.14).
#
# THE DEFECT. The watcher (a [release] script: every POSIX tarball and the source install ship it)
# compiled with the bare compiler, `cat "$SRC" | "$CC" > "$OUT" 2>/dev/null`. That build gets none
# of the work `cyrius build` does: on Apple Silicon its unsigned output was SIGKILLed at launch
# (measured on ecb: exit 137, "code object is not signed at all"); on every OS an `include`
# relative to the entry file failed ("cannot open include file") and so did the manifest's [deps];
# the `2>/dev/null` hid the compiler's diagnostic behind "COMPILE ERROR"; and the `>` redirect left
# an empty output where a working one had been. The user's decision D60 (2026-10-16): the watcher
# runs the same build as `cyrius build`, and CYRIUS_CC no longer picks the compiler.
#
# AXES (a scratch project: src/main.cyr includes "helper.cyr" from its own directory and takes
# `strlen` from cyrius.cyml's [deps] stdlib; the CLI is built from cbt/ with the tree's cycc beside
# it; a throwaway CYRIUS_HOME holds the stdlib; CYRIUS_CC names /bin/false throughout)
#   1  first pass: the watcher prints "built", its output is byte-identical to what
#      `cyrius build` writes for the same project, and it exits 42.
#   2  a failed build: with that output in place and the source broken, the watcher prints
#      "COMPILE ERROR" after the compiler's own diagnostic ("unexpected"), and the output is
#      unchanged.
#   3  the rebuild loop (the script's second build line): with the watcher running, a fixed source
#      is rebuilt ("rebuilt") to a program exiting 43.
#   Each watcher is stopped by its PID; nothing it made is left in TMPDIR (its stamp directory).
#   Darwin's signature is not checkable here (Linux): `cyrius build` signs, measured on ecb.
#
# MUTATION LEDGER (measured 6.7.14, each applied to scripts/cyrius-watch.sh alone):
#   a. the 6.7.13 watcher verbatim (bare cycc via CYRIUS_CC)  -> RED: axes 1, 2 and 3
#   b. only the loop's build line back to the bare compiler     -> RED: axis 3
#   c. `2>&1 >/dev/null`-style silencing: `2>/dev/null` added  -> RED: axis 2 (no diagnostic)
#      to both build lines
set -u
NAME=cyrius_watch_builds_like_build
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
WATCH="$ROOT/scripts/cyrius-watch.sh"
[ -x "$CC" ] || { echo "FAIL: $NAME: $CC missing"; exit 1; }
[ -f "$WATCH" ] || { echo "FAIL: $NAME: $WATCH missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
WPID=""
cleanup() {
    if [ -n "$WPID" ]; then kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null; fi
    rm -rf "$W"
}
trap cleanup EXIT
trap 'exit 1' INT TERM
FAIL=0
bad() { echo "  FAIL: $1"; FAIL=1; }
VER=$(tr -d '[:space:]' < "$ROOT/VERSION")

# ── the CLI (from this tree, with the tree's cycc beside it) and a throwaway home ──────────
mkdir -p "$W/tools" "$W/home/versions/$VER/lib" "$W/tmp"
if [ -n "${CYRIUS_BIN:-}" ]; then cp "$CYRIUS_BIN" "$W/tools/cyrius"
else ( cd "$ROOT" && "$CC" < cbt/cyrius.cyr > "$W/tools/cyrius" 2>/dev/null ) || { echo "FAIL: $NAME: cbt/cyrius.cyr did not build"; exit 1; }
fi
cp "$CC" "$W/tools/cycc" && chmod +x "$W/tools/cyrius" "$W/tools/cycc"
cp -R "$ROOT/lib/." "$W/home/versions/$VER/lib/"
printf '%s\n' "$VER" > "$W/home/current"
CLI="$W/tools/cyrius"

# ── the project ────────────────────────────────────────────────────────────────────────────
P="$W/proj"
mkdir -p "$P/src"
printf '[package]\nname = "wp"\nversion = "0.1.0"\ncyrius = "%s"\n\n[deps]\nstdlib = ["string", "syscalls"]\n' "$VER" > "$P/cyrius.cyml"
printf 'fn helper() { return 40 + strlen("ab"); }\n' > "$P/src/helper.cyr"
good_src() { printf 'include "helper.cyr"\nfn main() { return helper() + %s; }\nvar r = main();\nsyscall(SYS_EXIT, r);\n' "$1" > "$P/src/main.cyr"; }
good_src 0

# The reference: `cyrius build` itself.
rc=0; ( cd "$P" && CYRIUS_HOME="$W/home" TMPDIR="$W/tmp" "$CLI" build src/main.cyr ref.out ) > "$W/ref.log" 2>&1 || rc=$?
[ "$rc" = 0 ] || { echo "FAIL: $NAME: premise: \`cyrius build\` of the project exited $rc: $(tail -3 "$W/ref.log" | tr '\n' ' ')"; exit 1; }
rc=0; "$P/ref.out" || rc=$?
[ "$rc" = 42 ] || { echo "FAIL: $NAME: premise: the \`cyrius build\` output exits $rc, not 42"; exit 1; }
# Anti-vacuous: the bare compiler cannot build this project (the entry-relative include).
rc=0; ( cd "$P" && "$CC" < src/main.cyr > "$W/bare.out" 2> "$W/bare.err" ) || rc=$?
[ "$rc" != 0 ] || { echo "FAIL: $NAME: premise: the bare compiler built the project, so the axes cannot tell the recipes apart"; exit 1; }

# start_watch <log>: the watcher in the project, in the background; its PID in WPID.
start_watch() {
    ( cd "$P" && exec env CYRIUS_BIN="$CLI" CYRIUS_CC=/bin/false CYRIUS_HOME="$W/home" TMPDIR="$W/tmp" \
        CYRIUS_WATCH_INTERVAL=1 sh "$WATCH" src/main.cyr out/app ) > "$1" 2>&1 &
    WPID=$!
}
stop_watch() { kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null; WPID=""; }
# wait_for <log> <pattern>: up to 60 s for <pattern> in <log>; non-zero on timeout.
wait_for() {
    i=0
    while [ "$i" -lt 300 ]; do
        grep -q "$2" "$1" 2>/dev/null && return 0
        sleep 0.2; i=$((i + 1))
    done
    return 1
}
outhead() { sed 's/\x1b\[[0-9;]*m//g' "$1" | tail -6 | LC_ALL=C tr -c '[:print:]\n' '?' | tr '\n' '|'; }

# ── axis 1: the first pass ─────────────────────────────────────────────────────────────────
start_watch "$W/a1.log"
if ! wait_for "$W/a1.log" '\] \(built\|COMPILE ERROR\)'; then bad "axis 1: no build result within 60 s: $(outhead "$W/a1.log")"
elif ! grep -q '\] built ' "$W/a1.log"; then bad "axis 1: the first pass did not build: $(outhead "$W/a1.log")"
elif ! cmp -s "$P/out/app" "$P/ref.out"; then bad "axis 1: the watcher's output differs from \`cyrius build\`'s"
else
    rc=0; "$P/out/app" || rc=$?
    if [ "$rc" = 42 ]; then echo "  ok axis 1: the first pass prints \"built\", byte-identical to \`cyrius build\`, exits 42"
    else bad "axis 1: the watcher's output exits $rc, not 42"; fi
fi
stop_watch

# ── axis 2: a failed build keeps the output and shows the diagnostic ───────────────────────
if [ -s "$P/out/app" ]; then cp "$P/out/app" "$W/prior"; else cp "$P/ref.out" "$P/out/app"; cp "$P/ref.out" "$W/prior"; fi
printf 'include "helper.cyr"\nfn main() { return helper( }\n' > "$P/src/main.cyr"
start_watch "$W/a2.log"
if ! wait_for "$W/a2.log" '\] \(built\|COMPILE ERROR\)'; then bad "axis 2: no build result within 60 s: $(outhead "$W/a2.log")"
elif ! grep -q '\] COMPILE ERROR' "$W/a2.log"; then bad "axis 2: a broken source did not report COMPILE ERROR: $(outhead "$W/a2.log")"
elif ! grep -q 'unexpected' "$W/a2.log"; then bad "axis 2: the compiler's diagnostic was not shown: $(outhead "$W/a2.log")"
elif ! cmp -s "$P/out/app" "$W/prior"; then bad "axis 2: the failed build changed the previous output ($(wc -c < "$P/out/app") bytes now)"
else echo "  ok axis 2: a broken source -> the compiler's diagnostic, COMPILE ERROR, the previous output unchanged"; fi

# ── axis 3: the rebuild loop ───────────────────────────────────────────────────────────────
# The watcher of axis 2 is still running; a fixed source newer than its stamp is rebuilt.
sleep 1
good_src 1
if ! wait_for "$W/a2.log" '\] rebuilt '; then bad "axis 3: no rebuild within 60 s: $(outhead "$W/a2.log")"
else
    rc=0; "$P/out/app" || rc=$?
    if [ "$rc" = 43 ]; then echo "  ok axis 3: an edited source is rebuilt (\"rebuilt\") through the same build, exits 43"
    else bad "axis 3: the rebuilt output exits $rc, not 43"; fi
fi
stop_watch

# Nothing the watchers made is left behind (each removes its stamp directory on TERM).
left=$(ls -A "$W/tmp" 2>/dev/null || true)
[ -z "$left" ] || bad "the watcher left $(echo "$left" | tr '\n' ' ')in TMPDIR"

if [ "$FAIL" != 0 ]; then echo "FAIL: $NAME"; exit 1; fi
echo "PASS: $NAME (the watcher builds through \`cyrius build\`: entry-relative include and [deps] built byte-identically, a failure shows the diagnostic and keeps the old output, the loop rebuilds)"
