#!/bin/sh
# lib_overlay_include.sh — 6.7.6 (lane C). The compiler's local-development overlay,
# CYRIUS_LIB_OVERLAY: an include of `lib/<rest>` tries `<overlay>/<rest>` FIRST, then resolves as it
# always did (src/frontend/lex.cyr `_rf_ov_open`, called from READFILE).
#
# WHY IT EXISTS. `cyrius` in local mode (CYRIUS_LOCAL / --local) builds a [deps.X] `path` beside
# git/tag from the sibling working tree and vendors that resolution into build/local-deps/lib/,
# leaving lib/ — the tag resolution, which is tracked — alone. The include list could simply name
# build/local-deps/lib/x.cyr, but include-once is keyed on the path STRING: a source's own
# `include "lib/sigil.cyr"` then compiled the tag copy BESIDE the override and the later one won
# ("last definition wins") — the developer tested the tag while the build said `local:`. 11 of the
# 21 consumers that declare a path override hand-include it (measured 2026-10-08). With the overlay
# every include string stays `lib/<file>`, so include-once dedups and the overlay's copy is read.
#
# THE CONFINEMENT is `#@incdir`'s: a RELATIVE directory with no `..`, at most 480 bytes, composed
# with an include name that already passed the traversal / absolute guards — so the open stays in
# the CWD subtree. Anything else is ignored (the include resolves as without the overlay). It is an
# environment value, never an in-band marker, so no source can set it.
#
# AXES
#   O1  overlay set: `include "lib/a.cyr"` reads build/local-deps/lib/a.cyr (exit 7, not 1)
#   O2  a file the overlay does not hold falls through to lib/ (b.cyr -> exit 3)
#   O3  the same include twice, and a hand include beside it, compile ONE definition (no
#       `duplicate fn` warning) — include-once still dedups on the string
#   O4  unset / empty: lib/ (anti-vacuity — the fixture differs between the two dirs)
#   O5  refused values are IGNORED, never followed: an absolute dir, a `..` dir, a drive `C:x`,
#       a 481-byte dir — each reads lib/ (exit 1), and the absolute one holds a copy returning 9
#   O6  a non-`lib/` include is never overlaid (`src/c.cyr` -> exit 4 with an overlay copy at 8)
#
# MUTATION LEDGER (measured 2026-10-08, each in a SCRATCH copy of the tree with cycc rebuilt from the
# mutated src, one at a time; real tree 6/6 green):
#   M1  READFILE no longer calls _rf_ov_open (CWD open only) ......... O1 O3 red
#   M2  overlay opened AFTER the CWD open fails (fallback, not first)  O1 O3 red
#   M3  _rf_ov_load accepts an absolute directory ..................... O5 red
#   M4  _rf_ov_load accepts a `..` directory .......................... O5 red
#   M5  _rf_ov_open drops the `lib/` prefix test ...................... O6 red
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=lib_overlay_include
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
unset CYRIUS_LIB_OVERLAY
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
P="$W/p"
mkdir -p "$P/lib" "$P/src" "$P/build/local-deps/lib" "$P/build/local-deps/src" "$W/absov"
printf 'fn av(): i64 { return 1; }\n' > "$P/lib/a.cyr"
printf 'fn av(): i64 { return 7; }\n' > "$P/build/local-deps/lib/a.cyr"
printf 'fn av(): i64 { return 9; }\n' > "$W/absov/a.cyr"
printf 'fn bv(): i64 { return 3; }\n' > "$P/lib/b.cyr"
printf 'fn cv(): i64 { return 4; }\n' > "$P/src/c.cyr"
printf 'fn cv(): i64 { return 8; }\n' > "$P/build/local-deps/src/c.cyr"
printf 'fn cv(): i64 { return 8; }\n' > "$P/build/local-deps/c.cyr"   # what an overlay of `src/c.cyr` would name
printf 'include "lib/a.cyr"\nsyscall(60, av());\n' > "$P/a.cyr"
printf 'include "lib/b.cyr"\nsyscall(60, bv());\n' > "$P/b.cyr"
printf 'include "lib/a.cyr"\ninclude "lib/a.cyr"\nfn twice(): i64 { return av(); }\nsyscall(60, twice());\n' > "$P/twice.cyr"
printf 'include "src/c.cyr"\nsyscall(60, cv());\n' > "$P/c.cyr"
# run <src> [overlay] — compile in $P with the overlay (if given) and run; sets $rc, $err
run() {
    _s=$1; shift
    if [ "$#" -gt 0 ]; then
        ( cd "$P" && CYRIUS_LIB_OVERLAY="$1" "$CC" < "$_s" > "$W/bin" 2> "$W/err" )
    else
        ( cd "$P" && "$CC" < "$_s" > "$W/bin" 2> "$W/err" )
    fi
    chmod +x "$W/bin" 2>/dev/null
    rc=0; "$W/bin" > /dev/null 2>&1 || rc=$?
}
OV=build/local-deps/lib

run a.cyr "$OV"
[ "$rc" -eq 7 ] && ok "O1 overlay set: include \"lib/a.cyr\" read build/local-deps/lib/a.cyr (exit 7)" || bad "O1 (exit $rc, want 7): $(head -2 "$W/err")"
run b.cyr "$OV"
[ "$rc" -eq 3 ] && ok "O2 a file the overlay lacks falls through to lib/ (exit 3)" || bad "O2 (exit $rc, want 3): $(head -2 "$W/err")"
run twice.cyr "$OV"
if [ "$rc" -eq 7 ] && ! grep -q 'duplicate' "$W/err"; then ok "O3 the same lib/ include twice under the overlay: one definition, the overlay's (exit 7), no duplicate warning"
else bad "O3 (exit $rc, want 7): $(head -2 "$W/err")"; fi
run a.cyr
r1=$rc
run a.cyr ""
if [ "$r1" -eq 1 ] && [ "$rc" -eq 1 ]; then ok "O4 unset or empty: lib/a.cyr (exit 1) — the fixture tells the two apart"
else bad "O4 (unset exit $r1, empty exit $rc, want 1 and 1)"; fi
o5=0
for v in "$W/absov" "../p/$OV" "x/../$OV" "C:$OV" "$(printf '%0481d' 0)"; do
    run a.cyr "$v"
    if [ "$rc" -eq 1 ]; then o5=$((o5+1)); else echo "    O5 overlay '$(printf '%s' "$v" | cut -c1-40)': exit $rc (want 1)"; fi
done
[ "$o5" -eq 5 ] && ok "O5 an absolute, a \`..\`, a drive and a 481-byte overlay are IGNORED (lib/ read, exit 1 each; the absolute dir holds a copy returning 9)" || bad "O5 ($o5 of 5 ignored)"
run c.cyr "build/local-deps"
[ "$rc" -eq 4 ] && ok "O6 a non-lib/ include is never overlaid (src/c.cyr, exit 4)" || bad "O6 (exit $rc, want 4)"

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
