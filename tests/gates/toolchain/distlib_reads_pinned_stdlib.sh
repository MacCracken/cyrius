#!/bin/sh
# distlib_reads_pinned_stdlib.sh — 6.7.14: `cyrius distlib`'s sidecar verify AND its bundle
# self-check read the stdlib the manifest PINS (`cyrius = "<pin>"`, versions/<pin>/lib), not the
# CLI's own version slot (issues/2026-10-15-distlib-bundle-compile-ignores-pinned-stdlib.md).
#
# THE DEFECT. cycc resolves `lib/<leaf>.cyr` against CYRIUS_LIB_OVERLAY, then the CWD, then ONE
# store slot — CYRIUS_HOME/versions/<cycc's OWN version>/lib — and only then the entry's own
# directory (`#@incdir`, src/frontend/lex.cyr READFILE). The verify mirrored the pinned snapshot
# into `dist/.dlverify-<pid>/lib` and reached it only through `#@incdir`, AFTER the CLI's slot; the
# self-check had no mirror at all. With CYRIUS_RESOLVED=1 (no re-exec into the pin's own CLI) and a
# pin other than the CLI's version: a home holding only the pinned slot failed the self-check
# ("cannot open include file: lib/vec.cyr", rc 1), and a home holding both slots verified the
# bundle against the CLI's slot (a parse error in it failed the verify; one in the pinned slot
# passed). Now the mirror — the pinned snapshot MINUS what the project's ./lib holds, with an overlay
# this run already set (--locked with no vendored lib/) laid over it — IS the compiler's lib/
# overlay for both checks, restored afterwards.
#
# AXES (a throwaway CYRIUS_HOME, HOME pointed away, CYRIUS_RESOLVED=1, the CLI and cycc built
# from this tree, PIN = a version other than this tree's):
#   P1  the filed repro: the home holds ONLY versions/PIN/lib, the bundle calls vec_new: rc 0, the
#       sidecar names vec, no dist/.dlverify-* left
#   P2  the ws variant (`return WS_OPEN;`): rc 0, the sidecar names ws
#   P3  both slots, a parse error appended to the CLI-version slot's vec.cyr only: rc 0 (neither
#       check reads it)
#   P4  both slots, the PINNED slot's vec.cyr broken (its error 5 lines past the file's end): rc 1,
#       the error names lib/vec.cyr at THAT line
#   P5  control: PIN == this tree's VERSION, the home holds that slot only: rc 0, sidecar vec
#   P6  a leaf the project vendors in ./lib still resolves there (CWD first, as in its own build):
#       the pinned slot's vec.cyr broken, ./lib/vec.cyr intact: rc 0
#   P7  …and ./lib/vec.cyr broken (3 lines past its end), the pinned slot intact: rc 1 naming that
#       line — ./lib is what was read
#   P8  `distlib --locked` with no vendored lib/: the proven resolution (build/locked-deps/lib, the
#       overlay this run set) still wins — its named dep's module lib/sib.cyr, which no stdlib slot
#       holds, compiles in both checks: rc 0, the sidecar names vec and not sib
#
# MUTATION LEDGER (measured 2026-10-17, each in a scratch copy of cbt/, one at a time; the tree is
# 8/8 green):
#   M1  _distlib_mirror_make does not set the overlay (the mirror is only the `#@incdir`
#       fallback again) ........................................ P1 P2 P3 P4 P6 red
#   M2  the self-check makes no mirror (compiles as before) .... P1 P2 P3 P6 red
#   M3  the mirror does not leave out what ./lib holds .......... P6 P7 red
#   M4  the overlay this run set is not laid over the mirror .... P8 red
#   M5  _distlib_mirror_drop does not restore the previous overlay  P8 red
#   (the CLI before the fix: P1 P2 P3 P4 P6 red — P6 because ./lib's vec.cyr includes leaves ./lib
#   lacks, which the self-check could not open)
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=distlib_reads_pinned_stdlib
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "SKIP: $G: git not found (P8's named dep is a file:// origin)"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
unset CYRIUS_LOCAL CYRIUS_LOCKED CYRIUS_LIB_OVERLAY
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
ulimit -c 0 2>/dev/null

# The sidecar verify compiles for every target: cycc and cycc_aarch64 beside the CLI.
mkdir -p "$W/bin" "$W/tmp" "$W/nohome"
if [ -n "${CYRIUS_BIN:-}" ]; then cp "$CYRIUS_BIN" "$W/bin/cyrius"
else "$CC" < cbt/cyrius.cyr > "$W/bin/cyrius" 2> "$W/cli.err" && [ -s "$W/bin/cyrius" ] \
  || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
fi
cp "$CC" "$W/bin/cycc" && "$CC" < src/main_aarch64.cyr > "$W/bin/cycc_aarch64" 2> /dev/null \
  && chmod +x "$W/bin/cyrius" "$W/bin/cycc" "$W/bin/cycc_aarch64" \
  || { echo "SKIP: $G: could not stage cycc + cycc_aarch64 beside the CLI"; exit 77; }
V=$(tr -d '[:space:]' < VERSION)
PIN=6.7.11
[ "$PIN" = "$V" ] && PIN=6.7.10
N=$(wc -l < lib/vec.cyr | tr -d ' ')
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_ALLOW_PROTOCOL=file
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"

# _home <dir> <version>...: a throwaway home holding exactly these version slots (this tree's lib/)
_home() {
    _h=$1; shift
    rm -rf "$_h"; mkdir -p "$_h"
    for _v in "$@"; do mkdir -p "$_h/versions/$_v" && cp -r lib "$_h/versions/$_v/lib" || bad "setup: home $_h/$_v"; done
}
# _proj <dir> <pin> <src/lib.cyr body>: the filed repro's project
_proj() {
    rm -rf "$1"; mkdir -p "$1/src"
    printf '[package]\nname = "orp"\nversion = "0.1.0"\ncyrius = "%s"\n\n[lib]\nmodules = ["src/lib.cyr"]\n' "$2" > "$1/cyrius.cyml"
    printf '%s\n' "$3" > "$1/src/lib.cyr"
}
# dl <tag> <project> <home> [args…]: `cyrius distlib` there; rc in $rc, output in $W/<tag>.out
dl() {
    _t=$1; _p=$2; _hh=$3; shift 3
    rc=0
    ( cd "$_p" && HOME="$W/nohome" CYRIUS_HOME="$_hh" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 \
        TMPDIR="$W/tmp" "$W/bin/cyrius" distlib "$@" ) > "$W/$_t.out" 2>&1 || rc=$?
}
deps_has() { grep -qx "$2" "$1/dist/orp.deps" 2> /dev/null; }
no_mirror() { [ -z "$(ls -d "$1"/dist/.dlverify-* 2> /dev/null)" ]; }
VEC='fn orp_v(): i64 { var v = vec_new(); return v; }'
said() { sed -n '1,6p' "$W/$1.out" | sed 's/^/      /'; }

# ── P1: the filed repro, the home holding only the pinned slot ──
_home "$W/h1" "$PIN"
_proj "$W/p1" "$PIN" "$VEC"
dl p1 "$W/p1" "$W/h1"
if [ "$rc" -eq 0 ] && deps_has "$W/p1" vec && no_mirror "$W/p1"; then ok "P1 only versions/$PIN: rc 0, sidecar vec, no mirror left"
else bad "P1 only versions/$PIN (rc=$rc)"; said p1; fi

# ── P2: the ws variant ──
_proj "$W/p2" "$PIN" 'fn orp_v(): i64 { return WS_OPEN; }'
dl p2 "$W/p2" "$W/h1"
if [ "$rc" -eq 0 ] && deps_has "$W/p2" ws; then ok "P2 the ws variant: rc 0, sidecar ws"
else bad "P2 the ws variant (rc=$rc)"; said p2; fi

# ── P3: both slots, the CLI-version slot broken ──
_home "$W/h3" "$PIN" "$V"
printf 'fn {\n' >> "$W/h3/versions/$V/lib/vec.cyr"
_proj "$W/p3" "$PIN" "$VEC"
dl p3 "$W/p3" "$W/h3"
if [ "$rc" -eq 0 ] && deps_has "$W/p3" vec; then ok "P3 both slots, versions/$V/lib/vec.cyr broken: rc 0 (the pin is read)"
else bad "P3 both slots, the CLI's slot broken (rc=$rc)"; said p3; fi

# ── P4: both slots, the pinned slot broken ──
_home "$W/h4" "$PIN" "$V"
printf '\n\n\n\nfn {\n' >> "$W/h4/versions/$PIN/lib/vec.cyr"
_proj "$W/p4" "$PIN" "$VEC"
dl p4 "$W/p4" "$W/h4"
L4=$((N + 5))
if [ "$rc" -eq 1 ] && grep -q "lib/vec.cyr:$L4:" "$W/p4.out"; then ok "P4 both slots, versions/$PIN/lib/vec.cyr broken: rc 1 naming its line $L4"
else bad "P4 both slots, the pinned slot broken (rc=$rc, want 1 and lib/vec.cyr:$L4)"; said p4; fi

# ── P5: control, the pin is the CLI's version ──
_home "$W/h5" "$V"
_proj "$W/p5" "$V" "$VEC"
dl p5 "$W/p5" "$W/h5"
if [ "$rc" -eq 0 ] && deps_has "$W/p5" vec; then ok "P5 control: pin == $V: rc 0, sidecar vec"
else bad "P5 control, pin == $V (rc=$rc)"; said p5; fi

# ── P6 / P7: a leaf ./lib vendors resolves from ./lib ──
_home "$W/h6" "$PIN"
printf '\n\n\n\nfn {\n' >> "$W/h6/versions/$PIN/lib/vec.cyr"
_proj "$W/p6" "$PIN" "$VEC"
mkdir -p "$W/p6/lib" && cp lib/vec.cyr "$W/p6/lib/vec.cyr"
dl p6 "$W/p6" "$W/h6"
if [ "$rc" -eq 0 ] && deps_has "$W/p6" vec; then ok "P6 ./lib/vec.cyr intact, the pinned one broken: rc 0 (./lib first)"
else bad "P6 ./lib/vec.cyr intact, the pinned one broken (rc=$rc)"; said p6; fi
_home "$W/h7" "$PIN"
_proj "$W/p7" "$PIN" "$VEC"
mkdir -p "$W/p7/lib" && cp lib/vec.cyr "$W/p7/lib/vec.cyr" && printf '\n\nfn {\n' >> "$W/p7/lib/vec.cyr"
dl p7 "$W/p7" "$W/h7"
L7=$((N + 3))
if [ "$rc" -eq 1 ] && grep -q "lib/vec.cyr:$L7:" "$W/p7.out"; then ok "P7 ./lib/vec.cyr broken, the pinned one intact: rc 1 naming its line $L7"
else bad "P7 ./lib/vec.cyr broken (rc=$rc, want 1 and lib/vec.cyr:$L7)"; said p7; fi

# ── P8: --locked with no vendored lib/ — the overlay this run set still wins ──
O="$W/o/sib"
mkdir -p "$O/dist" && printf 'fn sib_v(): i64 { return 1; }\n' > "$O/dist/sib.cyr" \
  && ( cd "$O" && git init -q . && git add -A && git commit -qm v1 && git tag v1 ) || bad "P8 setup: the sib origin"
_home "$W/h8" "$PIN"
P8="$W/p8"; rm -rf "$P8"; mkdir -p "$P8/src"
printf '[package]\nname = "orp"\nversion = "0.1.0"\ncyrius = "%s"\n\n[lib]\nmodules = ["src/lib.cyr"]\n\n[deps]\nstdlib = ["vec"]\n\n[deps.sib]\ngit = "file://%s"\ntag = "v1"\nmodules = ["dist/sib.cyr"]\n' \
    "$PIN" "$O" > "$P8/cyrius.cyml"
printf 'fn orp_v(): i64 { var v = vec_new(); return v + sib_v(); }\n' > "$P8/src/lib.cyr"
rc=0
( cd "$P8" && HOME="$W/nohome" CYRIUS_HOME="$W/h8" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 TMPDIR="$W/tmp" \
    "$W/bin/cyrius" deps ) > "$W/p8deps.out" 2>&1 || rc=$?
rm -rf "$P8/lib"
if [ "$rc" -ne 0 ] || [ ! -f "$P8/cyrius.lock" ]; then bad "P8 setup: cyrius deps (rc=$rc)"; said p8deps
else
    dl p8 "$P8" "$W/h8" --locked
    if [ "$rc" -eq 0 ] && deps_has "$P8" vec && ! deps_has "$P8" sib && [ ! -e "$P8/lib" ]; then
        ok "P8 distlib --locked, no vendored lib/: rc 0, sidecar vec (sib a named dep), lib/ still absent"
    else bad "P8 distlib --locked, no vendored lib/ (rc=$rc)"; said p8; fi
fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && [ "$pass" -eq 8 ] || exit 1
exit 0
