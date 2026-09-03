#!/bin/sh
# Gate: a wrapper resolves the cycc SITTING BESIDE IT, so a version pin binds the compiler too
# (v6.5.42).
#
# THE DEFECT. `find_tools()` derived `cycc` from `$CYRIUS_HOME`/`$HOME` and NOTHING else, so
# `~/.cyrius/versions/6.5.32/bin/cyrius` resolved `~/.cyrius/bin/cycc` — the CURRENT compiler —
# while its own sibling `versions/6.5.32/bin/cycc` sat right there. A versioned toolchain
# therefore compiled with whatever cycc happened to be installed, and a manifest pin was not
# binding on the compiler at all. Proven semantically rather than cosmetically: a program built
# through the 6.5.32 wrapper produced output byte-identical to cycc 6.5.39's and exercised
# 6.5.39 semantics on a discriminator built from the v6.5.36 enum Critical.
#
# ⚠ v6.5.37 made this STRICTLY WORSE rather than adjacent. It fixed `_try_redirect_to_pinned`
# so the pin redirect fires for essentially every consumer — meaning consumers reliably got the
# pinned WRAPPER and the CURRENT COMPILER. The mismatch became the default path, not a corner.
#
# ⛔ AXIS 2 IS THE ONE THAT MATTERS MOST and it guards a fix in the opposite direction. v6.5.37
# also made `./build/cycc` win INSIDE the cyrius source repo, because otherwise every
# wrapper-driven gate compiles the corpus with the last RELEASED compiler and a compiler change
# cannot be tested through the wrapper at all. The sibling branch is ordered deliberately AFTER
# that one; put it first and this repo's own test suite silently stops testing the new compiler.
#
# ⚠ AXIS 3: invoked bare off $PATH there is no path in argv(0) and therefore nothing to be
# relative to. It must fall through to the installed toolchain, NOT guess from the CWD.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: wrapper_resolves_sibling_cycc: build/cycc missing"; exit 1; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: wrapper_resolves_sibling_cycc: $1"; exit 1; }

# Build the wrapper from source against build/cycc directly — never the installed `cyrius`,
# which in a scratch dir is the LAST RELEASE and would test the wrong binary (a mistake made
# four separate times during v6.5.37).
( cd "$ROOT" && cat cbt/cyrius.cyr | "$CC" > "$WORK/cyrius" ) 2>/dev/null \
    || fail "could not build cbt/cyrius.cyr"
chmod +x "$WORK/cyrius"

mkdir -p "$WORK/versions/9.9.9/bin" "$WORK/home/bin" "$WORK/proj" "$WORK/pathdir"
cp "$WORK/cyrius" "$WORK/versions/9.9.9/bin/cyrius"
cp "$CC" "$WORK/versions/9.9.9/bin/cycc"      # the sibling
cp "$CC" "$WORK/home/bin/cycc"                # the "installed" one
cp "$WORK/cyrius" "$WORK/pathdir/cyrius"

# ── anti-vacuous: the two candidate paths must be DISTINGUISHABLE ──────────────────
# If `which` could only ever print one path, axes 1 and 3 would agree for the wrong reason.
[ "$WORK/versions/9.9.9/bin/cycc" != "$WORK/home/bin/cycc" ] || fail "fixture paths collapsed"

# ── axis 1: a versioned wrapper picks its SIBLING, not $CYRIUS_HOME/bin ────────────
W1=$( cd "$WORK/proj" && CYRIUS_HOME="$WORK/home" "$WORK/versions/9.9.9/bin/cyrius" which 2>&1 | head -1 )
[ "$W1" = "$WORK/versions/9.9.9/bin/cycc" ] \
    || fail "axis 1: a versioned wrapper resolved '$W1', expected its sibling '$WORK/versions/9.9.9/bin/cycc' — a version pin still does not bind the compiler"

# ── axis 2: REGRESSION GUARD — in the cyrius source repo, ./build/cycc still wins ──
W2=$( cd "$ROOT" && CYRIUS_HOME="$WORK/home" "$WORK/versions/9.9.9/bin/cyrius" which 2>&1 | head -1 )
[ "$W2" = "./build/cycc" ] \
    || fail "axis 2: inside the cyrius source repo the wrapper resolved '$W2', expected './build/cycc' — v6.5.37's in-repo fix has been re-broken and this repo's wrapper-driven gates are now testing the last RELEASED compiler"

# ── axis 3: bare-name off $PATH falls through rather than guessing ─────────────────
W3=$( cd "$WORK/proj" && PATH="$WORK/pathdir:$PATH" CYRIUS_HOME="$WORK/home" cyrius which 2>&1 | head -1 )
[ "$W3" = "$WORK/home/bin/cycc" ] \
    || fail "axis 3: invoked bare off \$PATH the wrapper resolved '$W3', expected the installed '$WORK/home/bin/cycc' — with no path in argv(0) there is nothing to be relative to and it must not guess"

echo "PASS: wrapper_resolves_sibling_cycc (sibling wins for a versioned wrapper, ./build/cycc still wins in-repo, bare-name falls through)"
