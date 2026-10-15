#!/bin/sh
# Gate: both macOS release tarballs ship every cyrius.cyml `[release] scripts` entry (6.7.12).
#
# THE DEFECT. scripts/build-macos-x86-tarball.sh and build-macos-arm64-tarball.sh hand-copied
# scripts/cyrius-prompt-info and scripts/shims/cyrius-repl.sh, so cyrius-watch.sh (listed in
# [release] scripts and shipped by the source install and the x86_64 Linux tarball) was in no
# macOS tarball. The user's decision D4 (2026-10-15) was to ship every entry. Both builders now
# stage the list through scripts/release-scripts.sh. It reads the manifest and fails on an entry
# it cannot find, before anything compiles.
#
# AXES
#   1  static: each macOS builder runs `sh scripts/release-scripts.sh "$WORK/$STAGE/bin"` exactly
#      once in code, before its first compile. Its code names no [release] scripts entry itself:
#      a hand-copy is how the subset drifted.
#   2  the helper on the real manifest: every entry lands, executable and byte-identical to its
#      source (scripts/shims/ first, then scripts/), and nothing else lands. Floor: 3 entries,
#      cyrius-watch.sh among them. The expected list is parsed here with sed/grep, not the
#      helper's awk.
#   3  the helper refuses: (a) a manifest copy with a fake entry exits non-zero, names it, and
#      copies nothing; (b) a manifest with no `scripts =` line exits non-zero.
#   4  each BUILDER, run with CYRIUS_CYML=<the fake-entry copy>, exits non-zero, names the entry
#      and writes no tarball.
#   5  end to end: each builder on the real manifest produces a tarball whose bin/ holds every
#      entry, executable and byte-identical to its source, and bin/cyriusly (the shell script).
#      It needs xxd, tar and sha256sum, as the builders do. Without them it says so by name and
#      exits 77 (a SKIP, never a pass).
#
# MUTATION LEDGER (measured 6.7.12):
#   a. the slot-open (7f57e532) builders restored              -> RED: axis 1 (no helper call,
#      the hand-copied cyrius-prompt-info / cyrius-repl.sh named), axis 4 (both builders
#      built a tarball over the fake entry), axis 5 (bin/cyrius-watch.sh missing from both)
#   b. the helper's found-nowhere check dropped (copy errors    -> RED: axes 3a and 4
#      ignored)
#   c. the helper looks in scripts/ only (the 6.7.9 bug shape)  -> RED: axes 2 and 5
#      (cyrius-repl.sh is in scripts/shims/)
#   d. the x86 builder's helper call moved after its first      -> RED: axis 1 (order)
#      compile
#   e. the helper's empty-list check dropped                   -> RED: axis 3b
set -u

NAME=macos_tarball_ships_release_scripts
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
# What ships is the tree's manifest: an inherited override would test a different list.
unset CYRIUS_CYML

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

FAIL=0
bad() { echo "  FAIL: $1"; FAIL=1; }

BUILDERS="scripts/build-macos-x86-tarball.sh scripts/build-macos-arm64-tarball.sh"
HELPER=scripts/release-scripts.sh
[ -f "$HELPER" ] || { echo "FAIL: $NAME: $HELPER is missing"; exit 1; }

# The expected list, parsed independently of the helper's awk.
EXPECT=$(sed -n '/^\[release\]/,/^\[/p' cyrius.cyml | grep -E '^scripts[[:space:]]*=' | grep -oE '"[^"]+"' | tr -d '"' | tr '\n' ' ' | sed 's/ $//' || true)
n=0
for s in $EXPECT; do n=$((n + 1)); done
[ "$n" -ge 3 ] || { echo "FAIL: $NAME: read $n [release] scripts entries from cyrius.cyml (floor 3), so the parse is blind"; exit 1; }
case " $EXPECT " in *" cyrius-watch.sh "*) ;; *) echo "FAIL: $NAME: cyrius-watch.sh is not in [release] scripts ($EXPECT)"; exit 1 ;; esac
src_of() {
    if [ -f "scripts/shims/$1" ]; then echo "scripts/shims/$1"
    elif [ -f "scripts/$1" ]; then echo "scripts/$1"
    fi
}
for s in $EXPECT; do
    [ -n "$(src_of "$s")" ] || { echo "FAIL: $NAME: premise: [release] scripts lists $s, in neither scripts/shims/ nor scripts/"; exit 1; }
done

# check_bin <dir> <label>: every entry in <dir>, executable, byte-identical to its source.
check_bin() {
    for s in $EXPECT; do
        f="$1/$s"
        if [ ! -f "$f" ]; then bad "$2: $s is missing"; continue; fi
        [ -x "$f" ] || bad "$2: $s is not executable"
        cmp -s "$f" "$(src_of "$s")" || bad "$2: $s differs from $(src_of "$s")"
    done
}

# ── axis 1: static wiring ────────────────────────────────────────────────────────────────
a1=0
for b in $BUILDERS; do
    code=$(sed 's/^[[:space:]]*#.*$//' "$b")
    nh=$(printf '%s\n' "$code" | grep -c '^sh scripts/release-scripts\.sh "\$WORK/\$STAGE/bin"$' || true)
    lh=$(printf '%s\n' "$code" | grep -n '^sh scripts/release-scripts\.sh ' | head -1 | cut -d: -f1 || true)
    lc=$(printf '%s\n' "$code" | grep -nE '\| *([A-Z_]+=[^ ]+ +)*(\./build/cycc|"\$WORK/cc_[lx]")' | head -1 | cut -d: -f1 || true)
    if [ "$nh" != 1 ]; then bad "axis 1: $b runs scripts/release-scripts.sh \"\$WORK/\$STAGE/bin\" $nh times in code (want 1)"; a1=1
    elif [ -z "$lc" ]; then bad "axis 1: $b: found no compile line, so the order check reads nothing"; a1=1
    elif [ "$lh" -gt "$lc" ]; then bad "axis 1: $b stages the scripts at line $lh, after its first compile at line $lc (a bad entry must fail before anything compiles)"; a1=1
    fi
    for s in $EXPECT; do
        h=$(printf '%s\n' "$code" | grep -nF "$s" | head -1 || true)
        [ -z "$h" ] || { bad "axis 1: $b names [release] scripts entry $s itself (line ${h%%:*}); the helper ships it"; a1=1; }
    done
done
[ "$a1" = 0 ] && echo "  ok axis 1: both macOS builders stage [release] scripts through $HELPER before compiling, and hand-copy none"

# ── axis 2: the helper on the real manifest ──────────────────────────────────────────────
mkdir -p "$T/a2"
rc=0; sh "$HELPER" "$T/a2/bin" > "$T/a2.out" 2>&1 || rc=$?
if [ "$rc" != 0 ]; then
    bad "axis 2: $HELPER exited $rc on the tree's manifest: $(head -2 "$T/a2.out")"
else
    a2f=$FAIL; FAIL=0
    check_bin "$T/a2/bin" "axis 2"
    extra=$(ls -A "$T/a2/bin" | while read -r f; do case " $EXPECT " in *" $f "*) ;; *) printf '%s ' "$f" ;; esac; done)
    [ -z "$extra" ] || bad "axis 2: $HELPER staged files the manifest does not list: $extra"
    [ "$FAIL" = 0 ] && echo "  ok axis 2: $HELPER stages all $n entries ($EXPECT), executable and byte-identical, and nothing else"
    [ "$a2f" = 1 ] && FAIL=1
fi

# ── axis 3: the helper refuses a missing entry and an empty list ─────────────────────────
sed 's/^scripts = \[/scripts = ["cyrius-nope-6712.sh", /' cyrius.cyml > "$T/fake.cyml"
grep -q '^scripts = \["cyrius-nope-6712.sh", ' "$T/fake.cyml" || { echo "FAIL: $NAME: the fake-entry manifest was not made (cyrius.cyml has no '^scripts = [' line?)"; exit 1; }
sed '/^scripts = \[/d' cyrius.cyml > "$T/empty.cyml"
grep -q '^scripts' "$T/empty.cyml" && { echo "FAIL: $NAME: the empty-list manifest still has a scripts line"; exit 1; }
rc=0; CYRIUS_CYML="$T/fake.cyml" sh "$HELPER" "$T/a3a/bin" > "$T/a3a.out" 2>&1 || rc=$?
if [ "$rc" = 0 ]; then bad "axis 3a: $HELPER exited 0 over a manifest listing cyrius-nope-6712.sh"
elif ! grep -q 'cyrius-nope-6712\.sh' "$T/a3a.out"; then bad "axis 3a: $HELPER exited $rc without naming the missing entry: $(head -1 "$T/a3a.out")"
elif [ -n "$(ls -A "$T/a3a/bin" 2>/dev/null)" ]; then bad "axis 3a: $HELPER refused, but copied $(ls -A "$T/a3a/bin" | tr '\n' ' ')first"
else echo "  ok axis 3a: a listed entry found nowhere -> exit $rc, named, nothing copied"; fi
rc=0; CYRIUS_CYML="$T/empty.cyml" sh "$HELPER" "$T/a3b/bin" > "$T/a3b.out" 2>&1 || rc=$?
if [ "$rc" = 0 ]; then bad "axis 3b: $HELPER exited 0 over a manifest with no [release] scripts list"
else echo "  ok axis 3b: no [release] scripts list -> exit $rc ($(head -1 "$T/a3b.out"))"; fi

# ── axis 4: each builder fails on the fake entry ─────────────────────────────────────────
for b in $BUILDERS; do
    k=$(basename "$b" .sh)
    rc=0; CYRIUS_CYML="$T/fake.cyml" sh "$b" "$T/a4_$k" > "$T/a4_$k.out" 2>&1 || rc=$?
    if [ "$rc" = 0 ]; then bad "axis 4: $b exited 0 over a manifest listing cyrius-nope-6712.sh"
    elif ! grep -q 'cyrius-nope-6712\.sh' "$T/a4_$k.out"; then bad "axis 4: $b exited $rc without naming the missing entry: $(tail -1 "$T/a4_$k.out")"
    elif ls "$T/a4_$k"/*.tar.gz > /dev/null 2>&1; then bad "axis 4: $b refused, but wrote a tarball"
    else echo "  ok axis 4: $(basename "$b") over the fake entry -> exit $rc, named, no tarball"; fi
done

# ── axis 5: end to end ───────────────────────────────────────────────────────────────────
missing_tool=""
for tool in xxd tar sha256sum; do command -v "$tool" > /dev/null 2>&1 || missing_tool="$missing_tool $tool"; done
if [ -n "$missing_tool" ]; then
    echo "  SKIP axis 5: the builders need$missing_tool, not found on PATH"
else
    [ -x build/cycc ] || { echo "FAIL: $NAME: build/cycc missing (the builders compile with it)"; exit 1; }
    VER=$(tr -d '[:space:]' < VERSION)
    for b in $BUILDERS; do
        case "$b" in *x86*) st="cyrius-$VER-x86_64-macos" ;; *) st="cyrius-$VER-aarch64-macos" ;; esac
        k=$(basename "$b" .sh)
        rc=0; sh "$b" "$T/a5_$k" > "$T/a5_$k.out" 2>&1 || rc=$?
        [ "$rc" = 0 ] || { bad "axis 5: $b exited $rc: $(tail -2 "$T/a5_$k.out" | tr '\n' ' ')"; continue; }
        mkdir -p "$T/u_$k"
        tar xzf "$T/a5_$k/$st.tar.gz" -C "$T/u_$k" || { bad "axis 5: $st.tar.gz does not unpack"; continue; }
        a5f=$FAIL; FAIL=0
        check_bin "$T/u_$k/$st/bin" "axis 5 ($st)"
        cmp -s "$T/u_$k/$st/bin/cyriusly" scripts/cyriusly || bad "axis 5 ($st): bin/cyriusly is not scripts/cyriusly"
        [ "$FAIL" = 0 ] && echo "  ok axis 5: $st.tar.gz bin/ holds every [release] scripts entry and cyriusly"
        [ "$a5f" = 1 ] && FAIL=1
    done
fi

if [ "$FAIL" != 0 ]; then echo "FAIL: $NAME"; exit 1; fi
if [ -n "$missing_tool" ]; then echo "SKIP: $NAME (axes 1-4 green; axis 5 could not run:$missing_tool missing)"; exit 77; fi
echo "PASS: $NAME (both macOS tarballs ship all $n [release] scripts entries through $HELPER, which refuses an entry it cannot find before anything compiles)"
