#!/bin/sh
# deps_locked_writes_nothing.sh — 6.7.6 (lane C, part L). `--locked` (and CYRIUS_LOCKED=1) on
# `cyrius deps` and every resolving verb: resolve from the TAGS into a private scratch, verify every
# commit pin against its clone, compare the would-be lib/ and cyrius.lock with the committed ones,
# WRITE NOTHING, and fail naming each difference. The lock always records the tag resolution — a
# `path` override never reaches it (local mode writes no lock), so this is what CI runs.
#
# WHAT IT REPLACES. Consumers hand-rolled the check: `git diff --exit-code cyrius.lock` (abaco, hisab,
# rekha), lock-check.sh (commandress, agnostic), kybernet's verify-lock.sh, stiva's inline Python,
# aethersafha's check-dep-tags.sh — and the CI sequence `cyrius deps && cyrius deps --verify`
# checked a lock the first step had just REWRITTEN (a stale pin or a stale lib/ file passed).
#
# AXES (file:// origins, a throwaway CYRIUS_HOME, its own TMPDIR):
#   K1  a clean tree: rc 0, says so, and NOTHING under the project is newer than a stamp taken
#       before the run; the CLI's private temp dir is gone afterwards
#   K2  a stale vendored file in lib/: rc 1, named, the file left as it was
#   K3  a lock hash line that disagrees with the tag: named with both hashes
#   K4  a tag with no commit pin in the lock: named with the commit the tag resolves to
#   K5  a lock line for a file neither lib/ nor the tags hold: named
#   K6  a lib/ file the lock does not cover: named
#   K7  a file the tags resolve that lib/ lacks: named, and NOT created
#   K8  a lock whose stdlib pin line names another version: named
#   K9  no cyrius.lock: refused by name, rc 1, nothing created
#   K10 CYRIUS_LOCKED=1 is --locked (the K2 difference, rc 1); CYRIUS_LOCKED=yes is refused by name
#   K11 `cyrius build --locked`: clean -> builds (exit 1, the tag); stale -> rc 1 BEFORE any compile
#       (no binary)
#   K12 the sibling checkout present and CYRIUS_LOCAL=1: --locked notes it and resolves the TAG
#   K13 --locked with --relock, --verify, --lock or --local (deps, and build for --local): refused
#       by name
#   K14 a repointed tag: refused by the commit pin, rc 1, lib/ and the lock untouched
#   K15 NO VENDORED lib/ (a fresh checkout of a project that ignores lib/ — 68 of 126 consumers; the
#       lock is their committed artifact): `deps --locked` checks the resolve against cyrius.lock
#       alone, says so in one line, rc 0, writes nothing (no lib/, no build/, the lock as it was);
#       an EMPTY lib/ directory is the same case
#   K16 no vendored lib/ and a lock hash the tag disagrees with: named, rc 1, the summary names the
#       lock (not lib/), nothing written
#   K17 no vendored lib/: `build --locked` builds the tag from the proven resolution (exit 1, lib/
#       still absent, the lock as it was) and `test --locked` passes; with a stale lock it fails
#       BEFORE any compile and leaves no resolution behind
#   K18 CYRIUS_LOCKED=1 writes nothing in ANY verb: `update`, `deps --lock`, `deps --relock` and
#       `lib sync` are refused by name, rc 1, nothing under the project newer than a stamp (update
#       wrote ~100 files into lib/ and then said "nothing was written"; deps --lock rewrote the
#       lock); `deps --verify` and `lib sync --dry-run` (no writes) still run
#
# MUTATION LEDGER (measured 2026-10-08, each in a SCRATCH copy of the tree, one at a time; real
# tree 14/14 green):
#   M1  the compare skips "lib/ holds the bytes the tags resolve" ........ K2 K7 K10 K11 red
#   M2  the compare skips the lock hash of a resolved file ............... K3 red
#   M3  no "tag with no commit pin" difference ........................... K4 red
#   M4  the compare skips lock lines naming nothing ...................... K5 red
#   M5  the compare skips lib/ files the resolution does not produce ..... K6 red
#   M6  the compare skips the stdlib pin line ............................ K8 red
#   M7  --locked falls through to the default lock write ................. K1-K8 K10 K11 red
#   M8  the scratch is not removed ....................................... K1 red
#   (6.7.6 FXCL-1, the no-lib/ rows, measured the same way; real tree 17/17 green)
#   M9  _dep_lib_unvendored always 0 (lib/ required, the pre-fix shape) .. K15 K16 K17 red
#   M10 _dep_lib_unvendored always 1 (lib/ never compared) ............... K1 K2 K7 K10 K11 red
#   M11 the proven resolution is removed before the compile ............. K17 red
#   (6.7.6 FXCL-4, the same way; real tree 18/18 green)
#   M12 `update` not refused under CYRIUS_LOCKED=1 ...................... K18 red
#   M13 `deps --lock` / `--relock` not refused under CYRIUS_LOCKED=1 ..... K18 red
#   M14 `lib sync` not refused under CYRIUS_LOCKED=1 ..................... K18 red
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=deps_locked_writes_nothing
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "SKIP: $G: git not found"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
unset CYRIUS_LOCAL CYRIUS_LOCKED CYRIUS_LIB_OVERLAY
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
ulimit -c 0 2>/dev/null

"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/cli.err" && [ -s "$W/cyrius" ] \
  || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
V=$(tr -d '[:space:]' < VERSION)
H="$W/home"
mkdir -p "$H/versions/$V/bin" "$H/deps" "$W/tmp" && cp -r lib "$H/versions/$V/lib" \
  && cp "$W/cyrius" "$H/versions/$V/bin/cyrius" && cp "$CC" "$H/versions/$V/bin/cycc" \
  && chmod +x "$H/versions/$V/bin/cyrius" "$H/versions/$V/bin/cycc" && printf '%s\n' "$V" > "$H/current" \
  || { echo "FAIL: $G: cannot stage the throwaway home"; exit 1; }
CY="$H/versions/$V/bin/cyrius"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_ALLOW_PROTOCOL=file
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"
TAB=$(printf '\t')
mkdir -p "$W/o/sib/dist" && printf 'fn sib_v(): i64 { return 1; }\n' > "$W/o/sib/dist/sib.cyr"
( cd "$W/o/sib" && git init -q . && git add -A && git commit -qm v1 && git tag v1 ) || { echo "FAIL: $G: origin"; exit 1; }
SIBV1=$(git -C "$W/o/sib" rev-parse 'v1^{commit}')
mkdir -p "$W/ws" && git clone -q "$W/o/sib" "$W/ws/sib" && ( cd "$W/ws/sib" && printf 'fn sib_v(): i64 { return 2; }\n' > dist/sib.cyr && git commit -qam dev )
P="$W/ws/app"; mkdir -p "$P/src"
cat > "$P/cyrius.cyml" <<EOF
[package]
name = "app"
version = "0.1.0"
language = "cyrius"
cyrius = "$V"

[build]
entry = "src/main.cyr"
output = "build/app"

[deps]
stdlib = ["syscalls"]

[deps.sib]
git = "file://$W/o/sib"
tag = "v1"
path = "../sib"
modules = ["dist/sib.cyr"]
EOF
printf 'fn main(): i64 { return sib_v(); }\nvar r = main();\nsyscall(SYS_EXIT, r);\n' > "$P/src/main.cyr"
LCL=""; LCK=""
cy() { ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 TMPDIR="$W/tmp" \
         CYRIUS_LOCAL="$LCL" CYRIUS_LOCKED="$LCK" exec "$CY" "$@" ); }
rc=0; cy deps > "$W/setup.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && grep -q "^commit$TAB$SIBV1${TAB}sib$TAB" "$P/cyrius.lock" || { echo "FAIL: $G: setup resolve (rc=$rc): $(tail -2 "$W/setup.out")"; exit 1; }
cp "$P/cyrius.lock" "$W/lock0"; rm -rf "$W/lib0"; cp -r "$P/lib" "$W/lib0"
reset_tree() { cp "$W/lock0" "$P/cyrius.lock"; rm -rf "$P/lib"; cp -r "$W/lib0" "$P/lib"; }
# locked <tag> [args…]: `deps --locked`, rc in $rc, output in $W/<tag>.out
locked() { _t=$1; shift; rc=0; cy deps --locked "$@" > "$W/$_t.out" 2>&1 || rc=$?; }
untouched() { cmp -s "$P/cyrius.lock" "$1" && diff -r "$P/lib" "$2" > /dev/null; }

# ── K1 ──
sleep 1; touch "$W/stamp"; sleep 1
locked k1
newer=$(find "$P" -newer "$W/stamp" | head -3 | tr '\n' ' ')
left=$(ls -A "$W/tmp" | tr '\n' ' ')
if [ "$rc" -eq 0 ] && grep -q '^--locked: lib/ and cyrius.lock are exactly what the tags resolve$' "$W/k1.out" && [ -z "$newer" ] && [ -z "$left" ]; then
    ok "K1 a clean tree: rc 0, said so; nothing under the project newer than the stamp; no temp left"
else bad "K1 (rc=$rc newer=[$newer] tmp=[$left]): $(tail -2 "$W/k1.out")"; fi
# ── K2 ──
printf 'fn sib_v(): i64 { return 9; }\n' > "$P/lib/sib.cyr"; cp "$P/lib/sib.cyr" "$W/stale"; cp -r "$P/lib" "$W/lib2"
locked k2
if [ "$rc" -eq 1 ] && grep -qxF '  differs: lib/sib.cyr: lib/ holds other bytes than the tags resolve (stale)' "$W/k2.out" \
   && grep -q '^error: --locked: 1 difference(s) between what the tags resolve and the committed lib/ + cyrius.lock' "$W/k2.out" \
   && untouched "$W/lock0" "$W/lib2"; then
    ok "K2 a stale lib/sib.cyr: named, rc 1, left as it was (lock untouched)"
else bad "K2 (rc=$rc): $(grep -m2 'differs\|error' "$W/k2.out")"; fi
reset_tree
# ── K3 ──
sed -i "s|^[0-9a-f]\{64\}  lib/sib.cyr\$|$(printf '%064d' 0)  lib/sib.cyr|" "$P/cyrius.lock"; cp "$P/cyrius.lock" "$W/lock3"
locked k3
if [ "$rc" -eq 1 ] && grep -q "^  differs: lib/sib.cyr: cyrius.lock records $(printf '%064d' 0), the tags resolve [0-9a-f]\{64\}$" "$W/k3.out" && untouched "$W/lock3" "$W/lib0"; then
    ok "K3 a lock hash that disagrees with the tag: named with both hashes, nothing written"
else bad "K3 (rc=$rc): $(grep -m2 'differs\|error' "$W/k3.out")"; fi
reset_tree
# ── K4 ──
grep -v "^commit$TAB" "$W/lock0" > "$P/cyrius.lock"; cp "$P/cyrius.lock" "$W/lock4"
locked k4
if [ "$rc" -eq 1 ] && grep -qxF "  differs: cyrius.lock has no commit pin for sib tag v1 (the tag resolves to $SIBV1)" "$W/k4.out" && untouched "$W/lock4" "$W/lib0"; then
    ok "K4 a tag with no commit pin in the lock: named with the commit the tag resolves to; the lock not re-pinned"
else bad "K4 (rc=$rc): $(grep -m2 'differs\|error' "$W/k4.out")"; fi
reset_tree
# ── K5 ──
printf '%064d  lib/ghost.cyr\n' 0 >> "$P/cyrius.lock"; cp "$P/cyrius.lock" "$W/lock5"
locked k5
if [ "$rc" -eq 1 ] && grep -qxF '  differs: cyrius.lock lists lib/ghost.cyr, which neither lib/ nor the tags hold' "$W/k5.out" && untouched "$W/lock5" "$W/lib0"; then
    ok "K5 a lock line for a file that exists nowhere: named"
else bad "K5 (rc=$rc): $(grep -m2 'differs\|error' "$W/k5.out")"; fi
reset_tree
# ── K6 ──
printf 'fn extra(): i64 { return 0; }\n' > "$P/lib/extra.cyr"; cp -r "$P/lib" "$W/lib6"
locked k6
if [ "$rc" -eq 1 ] && grep -qxF '  differs: lib/extra.cyr: in lib/ but not in cyrius.lock' "$W/k6.out" && untouched "$W/lock0" "$W/lib6"; then
    ok "K6 a lib/ file the lock does not cover: named"
else bad "K6 (rc=$rc): $(grep -m2 'differs\|error' "$W/k6.out")"; fi
reset_tree
# ── K7 ──
rm "$P/lib/sib.cyr"
locked k7
if [ "$rc" -eq 1 ] && grep -qxF '  differs: lib/sib.cyr: missing from lib/ (the tags resolve it)' "$W/k7.out" && [ ! -e "$P/lib/sib.cyr" ]; then
    ok "K7 a file the tags resolve that lib/ lacks: named, and not created"
else bad "K7 (rc=$rc): $(grep -m2 'differs\|error' "$W/k7.out")"; fi
reset_tree
# ── K8 ──
sed -i "s/^cyrius$TAB.*\$/cyrius${TAB}0.0.1/" "$P/cyrius.lock"; cp "$P/cyrius.lock" "$W/lock8"
locked k8
if [ "$rc" -eq 1 ] && grep -qxF "  differs: cyrius.lock records another stdlib pin than $V" "$W/k8.out" && untouched "$W/lock8" "$W/lib0"; then
    ok "K8 a lock recording another stdlib pin: named"
else bad "K8 (rc=$rc): $(grep -m2 'differs\|error' "$W/k8.out")"; fi
reset_tree
# ── K9 ──
rm "$P/cyrius.lock"
locked k9
if [ "$rc" -eq 1 ] && grep -q '^error: --locked: there is no cyrius.lock to hold this resolve to' "$W/k9.out" && [ ! -e "$P/cyrius.lock" ]; then
    ok "K9 no cyrius.lock: refused by name, nothing created"
else bad "K9 (rc=$rc): $(head -2 "$W/k9.out")"; fi
reset_tree
# ── K10 ──
printf 'fn sib_v(): i64 { return 9; }\n' > "$P/lib/sib.cyr"
LCK=1; rc=0; cy deps > "$W/k10a.out" 2>&1 || rc=$?; r10a=$rc
LCK=yes; rc=0; cy deps > "$W/k10b.out" 2>&1 || rc=$?; r10b=$rc; LCK=""
if [ "$r10a" -eq 1 ] && grep -qxF '  differs: lib/sib.cyr: lib/ holds other bytes than the tags resolve (stale)' "$W/k10a.out" \
   && [ "$r10b" -eq 1 ] && grep -q '^error: CYRIUS_LOCKED must be 0 or 1 (or unset): yes$' "$W/k10b.out"; then
    ok "K10 CYRIUS_LOCKED=1 is --locked; CYRIUS_LOCKED=yes is refused by name"
else bad "K10 (one rc=$r10a yes rc=$r10b): $(grep -m1 'differs\|error' "$W/k10a.out") / $(head -1 "$W/k10b.out")"; fi
reset_tree
# ── K11 ──
rm -rf "$P/build"
rc=0; cy build --locked > "$W/k11a.out" 2>&1 || rc=$?; r11a=$rc
ex=-1; [ -x "$P/build/app" ] && { ex=0; "$P/build/app" > /dev/null 2>&1 || ex=$?; }
rm -rf "$P/build"; printf 'fn sib_v(): i64 { return 9; }\n' > "$P/lib/sib.cyr"
rc=0; cy build --locked > "$W/k11b.out" 2>&1 || rc=$?
if [ "$r11a" -eq 0 ] && [ "$ex" -eq 1 ] && [ "$rc" -eq 1 ] && [ ! -e "$P/build/app" ] && ! grep -q '^compile ' "$W/k11b.out"; then
    ok "K11 build --locked: a clean tree builds the tag (exit 1); a stale one fails before any compile"
else bad "K11 (clean rc=$r11a exit=$ex; stale rc=$rc): $(grep -m2 'differs\|compile' "$W/k11b.out")"; fi
reset_tree
# ── K12 ──
LCL=1; locked k12; LCL=""
if [ "$rc" -eq 0 ] && grep -qxF 'note: CYRIUS_LOCAL is ignored here — --locked resolves the tags' "$W/k12.out" && ! grep -q '^local: ' "$W/k12.out"; then
    ok "K12 ../sib present and CYRIUS_LOCAL=1: --locked notes it and checks the TAG (rc 0)"
else bad "K12 (rc=$rc): $(grep -m2 'note\|local\|differs' "$W/k12.out")"; fi
# ── K13 ──
k13=0
for f in --relock --verify --lock; do
    rc=0; cy deps --locked "$f" > "$W/k13.out" 2>&1 || rc=$?
    if [ "$rc" -eq 1 ] && grep -q '^error: deps: --locked writes nothing and checks the resolve; it does not combine with --verify, --lock or --relock$' "$W/k13.out"; then k13=$((k13+1)); fi
done
rc=0; cy deps --locked --local > "$W/k13l.out" 2>&1 || rc=$?
if [ "$rc" -eq 1 ] && grep -q '^error: --local and --locked contradict each other' "$W/k13l.out"; then k13=$((k13+1)); fi
rc=0; cy build --local --locked > "$W/k13b.out" 2>&1 || rc=$?
if [ "$rc" -eq 1 ] && grep -q '^error: --local and --locked contradict each other' "$W/k13b.out" && ! grep -q '^compile ' "$W/k13b.out"; then k13=$((k13+1)); fi
[ "$k13" -eq 5 ] && ok "K13 --locked with --relock / --verify / --lock / --local (deps and build): refused by name" || bad "K13 ($k13 of 5 refused)"
# ── K15 ── (before K14, which repoints the tag)
reset_tree; rm -rf "$P/lib" "$P/build"
sleep 1; touch "$W/stamp15"; sleep 1
locked k15; r15=$rc
newer=$(find "$P" -newer "$W/stamp15" | head -3 | tr '\n' ' ')
left=$(ls -A "$W/tmp" | tr '\n' ' ')
nl=$(grep -c '^note: --locked: no vendored lib/ here — the resolve is checked against cyrius.lock alone$' "$W/k15.out")
mkdir "$P/lib"; locked k15e; r15e=$rc; rmdir "$P/lib"
if [ "$r15" -eq 0 ] && [ "$nl" = 1 ] && grep -q '^--locked: cyrius.lock is exactly what the tags resolve (no vendored lib/ to compare)$' "$W/k15.out" \
   && ! grep -q 'differs' "$W/k15.out" && [ -z "$newer" ] && [ -z "$left" ] && [ ! -e "$P/lib" ] && [ ! -e "$P/build" ] \
   && cmp -s "$P/cyrius.lock" "$W/lock0" && [ "$r15e" -eq 0 ] && grep -q '^--locked: cyrius.lock is exactly what the tags resolve' "$W/k15e.out"; then
    ok "K15 no vendored lib/ (absent, or an empty directory): checked against cyrius.lock alone, said once, rc 0, nothing written"
else bad "K15 (rc=$r15 note=$nl newer=[$newer] tmp=[$left] empty-lib rc=$r15e): $(grep -m2 'differs\|error\|locked' "$W/k15.out")"; fi
# ── K16 ──
sed -i "s|^[0-9a-f]\{64\}  lib/sib.cyr\$|$(printf '%064d' 0)  lib/sib.cyr|" "$P/cyrius.lock"
printf '%064d  lib/ghost.cyr\n' 0 >> "$P/cyrius.lock"; cp "$P/cyrius.lock" "$W/lock16"
locked k16
if [ "$rc" -eq 1 ] && grep -q "^  differs: lib/sib.cyr: cyrius.lock records $(printf '%064d' 0), the tags resolve [0-9a-f]\{64\}$" "$W/k16.out" \
   && grep -qxF '  differs: cyrius.lock lists lib/ghost.cyr, which neither lib/ nor the tags hold' "$W/k16.out" \
   && ! grep -q 'missing from lib/' "$W/k16.out" \
   && grep -q '^error: --locked: 2 difference(s) between what the tags resolve and the committed cyrius.lock (named above)' "$W/k16.out" \
   && cmp -s "$P/cyrius.lock" "$W/lock16" && [ ! -e "$P/lib" ]; then
    ok "K16 no vendored lib/: a lock hash the tag disagrees with and a lock line for nothing are named against the lock; nothing written"
else bad "K16 (rc=$rc): $(grep -m3 'differs\|error' "$W/k16.out")"; fi
# ── K17 ──
cp "$W/lock0" "$P/cyrius.lock"; rm -rf "$P/lib" "$P/build"
rc=0; cy build --locked > "$W/k17a.out" 2>&1 || rc=$?; r17a=$rc
ex=-1; [ -x "$P/build/app" ] && { ex=0; "$P/build/app" > /dev/null 2>&1 || ex=$?; }
mkdir -p "$P/tests"; printf 'syscall(SYS_EXIT, sib_v() - 1);\n' > "$P/tests/t.tcyr"
rc=0; cy test --locked > "$W/k17t.out" 2>&1 || rc=$?; r17t=$rc
rm -rf "$P/tests"
kept=0; [ ! -e "$P/lib" ] && cmp -s "$P/cyrius.lock" "$W/lock0" && kept=1
rm -rf "$P/build"; sed -i "s|^[0-9a-f]\{64\}  lib/sib.cyr\$|$(printf '%064d' 0)  lib/sib.cyr|" "$P/cyrius.lock"
rc=0; cy build --locked > "$W/k17b.out" 2>&1 || rc=$?
if [ "$r17a" -eq 0 ] && [ "$ex" -eq 1 ] && [ "$r17t" -eq 0 ] && grep -q '^1 passed, 0 failed$' "$W/k17t.out" && [ "$kept" = 1 ] \
   && [ "$rc" -eq 1 ] && [ ! -e "$P/build/app" ] && [ ! -e "$P/build/locked-deps" ] && ! grep -q '^compile ' "$W/k17b.out"; then
    ok "K17 no vendored lib/: build --locked builds the tag (exit 1) and test --locked passes, lib/ never written; a stale lock fails before any compile"
else bad "K17 (build rc=$r17a exit=$ex; test rc=$r17t; lib/lock as they were=$kept; stale rc=$rc): $(grep -m2 'differs\|error\|compile' "$W/k17b.out" "$W/k17a.out")"; fi
reset_tree; rm -rf "$P/build"
# ── K18 ──
k18=0; k18w=""
for v in "update" "deps --lock" "deps --relock" "lib sync"; do
    sleep 1; touch "$W/stamp18"; sleep 1
    LCK=1; rc=0; cy $v > "$W/k18.out" 2>&1 || rc=$?; LCK=""
    newer=$(find "$P" -newer "$W/stamp18" | head -3 | tr '\n' ' ')
    if [ "$rc" -eq 1 ] && grep -q "^error: cyrius $v writes .*, and CYRIUS_LOCKED=1 means nothing is written — refused" "$W/k18.out" && [ -z "$newer" ]; then
        k18=$((k18+1))
    else k18w="$k18w [$v rc=$rc newer=$newer: $(grep -m1 -v unreachable "$W/k18.out")]"; fi
    reset_tree
done
LCK=1; rc=0; cy deps --verify > "$W/k18v.out" 2>&1 || rc=$?; r18v=$rc
rc=0; cy lib sync --dry-run > "$W/k18d.out" 2>&1 || rc=$?; LCK=""
if [ "$k18" -eq 4 ] && [ "$r18v" -eq 0 ] && [ "$rc" -eq 0 ]; then
    ok "K18 CYRIUS_LOCKED=1: update, deps --lock, deps --relock and lib sync refused by name, nothing written; --verify and a dry run still run"
else bad "K18 ($k18 of 4 refused;$k18w verify rc=$r18v dry-run rc=$rc)"; fi
# ── K14 ──
( cd "$W/o/sib" && printf 'fn sib_v(): i64 { return 5; }\n' > dist/sib.cyr && git commit -qam evil && git tag -f v1 > /dev/null 2>&1 )
rm -rf "$H/deps/sib"
locked k14
if [ "$rc" -eq 1 ] && grep -q "^error: commit-pin mismatch for dep 'sib' tag 'v1'" "$W/k14.out" && untouched "$W/lock0" "$W/lib0"; then
    ok "K14 a repointed tag: refused by the commit pin, lib/ and the lock untouched"
else bad "K14 (rc=$rc): $(grep -m2 'error' "$W/k14.out")"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
