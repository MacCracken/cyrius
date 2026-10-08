#!/bin/sh
# deps_git_first_local_switch.sh — 6.7.6 (lane C, user 2026-10-08): GIT FIRST, LOCAL DEVELOPMENT BY
# AN EXPLICIT SWITCH.
#
# THE RULE. A `[deps.X] path` beside `git` / `tag` is a DEV OVERRIDE, read only in LOCAL MODE —
# `--local[=a,b]` > `--no-local` > CYRIUS_LOCAL (1, 0, or a name list) > off; the manifest never
# switches it on. With no switch every machine builds the TAG (its commit pin checked) and prints
# ONE hint line naming the local checkouts it did not use. In local mode each override prints one
# `local:` line (path, sha, commits past the tag, dirty, what CI builds), and the resolution is
# vendored into build/local-deps/lib/ — lib/ and cyrius.lock are never written, so switching modes
# churns nothing tracked; the compiler reads lib/ through CYRIUS_LIB_OVERLAY, so a source's own
# `include "lib/x.cyr"` reads the override too. A dependency resolved from its tag has its own
# `path` entries ignored and a path-only / local-git / absolute entry REFUSED by name; a dependency
# that is itself a local checkout has its overrides followed for the selected names. A path-only
# dep in the ROOT manifest keeps working exactly as before (no tag to prefer).
#
# THE DEFECT IT REPLACES. Until 6.7.6 a path beside git/tag won whenever the directory existed —
# silently, no clone, no commit pin — so a dev box and CI built different code from one manifest
# (48 of 52 ecosystem overrides sat past their tag), and the ecosystem toggled path lines by hand
# (166 commits in 47 repos; 9 repos ran their own CI guards against a committed path).
#
# AXES (every origin a local file:// repo; a throwaway CYRIUS_HOME; no network):
#   L1  no switch, the sibling checkout present: the TAG is vendored (lib/sib.cyr = v1, the binary
#       exits 1), cyrius.lock pins v1's commit, ONE `hint:` line names sib, no `local:` line
#   L2  CYRIUS_LOCAL=1: one `local: sib <- ../sib @<sha>, 1 commit past v1 — CI builds v1` line,
#       the binary exits 2, build/local-deps/lib/sib.cyr is the checkout's, lib/ and cyrius.lock
#       BYTE-IDENTICAL to L1's
#   L3  a hand-written `include "lib/sib.cyr"`: local mode compiles the override ONCE (exit 2, no
#       `duplicate` warning); with no switch the tag (exit 1)
#   L4  CYRIUS_LOCAL=sib selects it (exit 2); CYRIUS_LOCAL=other builds the tag and WARNS that no
#       [deps.other] declares a path
#   L5  precedence: --no-local beats CYRIUS_LOCAL=1 (exit 1); --local (exit 2); --local=sib (exit 2);
#       --local= (empty) is refused by name
#   L6  a ROOT path-only dep resolves from its path with no switch, writes lib/ + the lock, prints
#       no `local` line (unchanged behaviour)
#   L7  a TAG-RESOLVED dep's own manifest: (a) its path beside a remote git is DROPPED even where
#       that path exists — its tag resolves; (b) a path-only entry, (c) an absolute path and
#       (d) a local-git entry are each REFUSED by name, rc 1
#   L8  a local checkout's own override is followed when its name is selected (CYRIUS_LOCAL=1: two
#       `local:` lines, leaf via mid), and not when only the parent is (CYRIUS_LOCAL=mid: leaf's tag)
#   L9  a local checkout's path-only entry with its name unselected is refused, naming the switch
#       that builds it; with CYRIUS_LOCAL=1 it resolves
#   L10 `--local --no-local` and `publish --local` are refused by name; CYRIUS_LOCAL=1 under
#       `cyrius package` (a release verb) is ignored with one note and the tag is packaged
#   L11 CYRIUS_LOCAL=1 with NO override in use resolves exactly as the default: lib/ + the lock
#       written, no build/local-deps
#   L12 a CYRIUS_LIB_OVERLAY left in the shell never reaches a default-mode compile (exit 1 with
#       L2's build/local-deps still holding the override)
#   L13 each local-mode resolve starts from an EMPTY build/local-deps/lib (a planted file is gone)
#   L14 R12: a path dep's missing module is "not found in the local path …", never "at tag"
#
# MUTATION LEDGER (measured 2026-10-08, each in a SCRATCH copy of the tree — never the worktree —
# one at a time; the real tree is 14/14 green):
#   M1  root `_dep_pick`: a path that is a directory wins without the switch (the old precedence)
#                                                                  L1 L3 L4 L5 L10 L12 red
#   M2  `_dep_local_begin` leaves `_dep_vroot` at lib/ (local mode writes lib/)  L2 L12 red
#   M3  local mode falls through to the lock write (same bytes, rewritten) L2 red
#   M4  `_dep_local_begin` sets no overlay ................... L2 L3 L4 L5 L8 L9 L13 red
#   M5  main() no longer strips an inherited CYRIUS_LIB_OVERLAY ............ L12 red
#   M6  a tag-resolved dep's path-only entry is followed .................. L7 red
#   M7  a tag-resolved dep's path beside a remote git is followed ......... L7 red
#   M8  a local checkout follows an UNSELECTED override ................... L8 red
#   M9  the prescan never finds an override in use (vendors into lib/) .... L2 L12 red
#   M10 `_dep_local_begin` does not clear build/local-deps/lib ............ L13 red
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=deps_git_first_local_switch
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
mkdir -p "$H/versions/$V/bin" "$H/deps" && cp -r lib "$H/versions/$V/lib" \
  && cp "$W/cyrius" "$H/versions/$V/bin/cyrius" && cp "$CC" "$H/versions/$V/bin/cycc" \
  && chmod +x "$H/versions/$V/bin/cyrius" "$H/versions/$V/bin/cycc" && printf '%s\n' "$V" > "$H/current" \
  || { echo "FAIL: $G: cannot stage the throwaway home"; exit 1; }
CY="$H/versions/$V/bin/cyrius"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_ALLOW_PROTOCOL=file
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"
TAB=$(printf '\t')

# ── origins ────────────────────────────────────────────────────────────────────────────────
mkorigin() {   # $1 name, $2 return value, $3 optional cyrius.cyml body (printf %b)
    _o="$W/o/$1"; mkdir -p "$_o/dist"
    printf 'fn %s_v(): i64 { return %s; }\n' "$1" "$2" > "$_o/dist/$1.cyr"
    [ -n "$3" ] && printf '%b' "$3" > "$_o/cyrius.cyml"
    ( cd "$_o" && git init -q . && git add -A && git commit -qm v1 && git tag v1 ) || { echo "FAIL: $G: cannot build origin $1"; exit 1; }
}
mkorigin sib 1
mkorigin leaf 10
mkorigin mid 3 "[package]\nname = \"mid\"\n\n[deps.leaf]\ngit = \"file://$W/o/leaf\"\ntag = \"v1\"\npath = \"../leaf\"\nmodules = [\"dist/leaf.cyr\"]\n"
mkorigin midpo 4 "[package]\nname = \"midpo\"\n\n[deps.leaf]\npath = \"../leaf\"\nmodules = [\"dist/leaf.cyr\"]\n"
mkorigin midabs 5 "[package]\nname = \"midabs\"\n\n[deps.leaf]\ngit = \"file://$W/o/leaf\"\ntag = \"v1\"\npath = \"$W/ws/leaf\"\nmodules = [\"dist/leaf.cyr\"]\n"
mkorigin midlg 6 "[package]\nname = \"midlg\"\n\n[deps.leaf]\ngit = \"../leaf\"\ntag = \"v1\"\nmodules = [\"dist/leaf.cyr\"]\n"
# ── the developer's workspace: sibling checkouts beside the projects ────────────────────────
WS="$W/ws"; mkdir -p "$WS"
git clone -q "$W/o/sib" "$WS/sib" && ( cd "$WS/sib" && printf 'fn sib_v(): i64 { return 2; }\n' > dist/sib.cyr && git commit -qam dev ) \
  || { echo "FAIL: $G: cannot stage ws/sib"; exit 1; }
git clone -q "$W/o/leaf" "$WS/leaf" && printf 'fn leaf_v(): i64 { return 99; }\n' > "$WS/leaf/dist/leaf.cyr"   # dirty
git clone -q "$W/o/mid" "$WS/mid"
git clone -q "$W/o/midpo" "$WS/midpo"

# LCL / LOV: CYRIUS_LOCAL / CYRIUS_LIB_OVERLAY for the next call (empty = unset: the CLI reads an
# empty value as no value)
LCL=""; LOV=""
cy() { ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 \
         CYRIUS_LOCAL="$LCL" CYRIUS_LIB_OVERLAY="$LOV" exec "$CY" "$@" ); }
# mkp <name>: a project under ws/ whose [deps] tables come from stdin
mkp() {
    P="$WS/$1"; rm -rf "$P"; mkdir -p "$P/src"
    { printf '[package]\nname = "%s"\nversion = "0.1.0"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/app"\n\n[deps]\nstdlib = ["syscalls"]\n\n' "$1" "$V"; cat; } > "$P/cyrius.cyml"
    printf 'build/\n' > "$P/.gitignore"
}
main_calls() { printf '%bfn main(): i64 { return %s(); }\nvar r = main();\nsyscall(SYS_EXIT, r);\n' "$2" "$1" > "$P/src/main.cyr"; }
# b <tag> [args…] — `cyrius build`, then run the binary; sets $rc (build) and $ex (program exit)
b() {
    _t=$1; shift
    rc=0; cy build "$@" > "$W/$_t.out" 2>&1 || rc=$?
    ex=-1; if [ "$rc" -eq 0 ] && [ -x "$P/build/app" ]; then ex=0; "$P/build/app" > /dev/null 2>&1 || ex=$?; fi
}
SIBREF="$W/o/sib/dist/sib.cyr"
SIBV1=$(git -C "$W/o/sib" rev-parse 'v1^{commit}')

mkp app <<EOF
[deps.sib]
git = "file://$W/o/sib"
tag = "v1"
path = "../sib"
modules = ["dist/sib.cyr"]
EOF
main_calls sib_v ""
# ── L1 ──
b l1
pin=$(tr -d '\r' < "$P/cyrius.lock" 2>/dev/null | awk -F"$TAB" '$1 == "commit" && $3 == "sib" { print $2 }')
nh=$(grep -c '^hint: ' "$W/l1.out")
if [ "$rc" -eq 0 ] && [ "$ex" -eq 1 ] && cmp -s "$P/lib/sib.cyr" "$SIBREF" && [ "$pin" = "$SIBV1" ] && [ "$nh" -eq 1 ] \
   && grep -q '^hint: 1 dep has a local checkout not in use (sib); CYRIUS_LOCAL=1 builds it' "$W/l1.out" \
   && ! grep -q '^local' "$W/l1.out" && [ ! -d "$P/build/local-deps" ]; then
    ok "L1 no switch, ../sib present: the TAG is vendored and pinned (exit 1), one hint line names sib"
else bad "L1 (rc=$rc exit=$ex pin=$pin hints=$nh): $(grep -m3 'hint\|local\|error' "$W/l1.out")"; fi
cp "$P/cyrius.lock" "$W/l1.lock"; cp -r "$P/lib" "$W/l1.lib"
# ── L2 ── (the stamp catches a rewrite to the same bytes — the lock is not WRITTEN, not merely unchanged)
sleep 1; touch "$W/l2.stamp"; sleep 1
LCL=1; b l2; LCL=""
wrote=$(find "$P/cyrius.lock" "$P/lib" -newer "$W/l2.stamp" | head -2 | tr '\n' ' ')
if [ "$rc" -eq 0 ] && [ "$ex" -eq 2 ] && grep -Eq '^local: sib <- \.\./sib @[0-9a-f]{7}, 1 commit past v1 — CI builds v1$' "$W/l2.out" \
   && [ "$(grep -c '^local: ' "$W/l2.out")" -eq 1 ] && ! grep -q '^hint: ' "$W/l2.out" \
   && cmp -s "$P/build/local-deps/lib/sib.cyr" "$WS/sib/dist/sib.cyr" \
   && cmp -s "$P/cyrius.lock" "$W/l1.lock" && diff -r "$P/lib" "$W/l1.lib" > /dev/null && [ -z "$wrote" ]; then
    ok "L2 CYRIUS_LOCAL=1: one local: line (sha, 1 commit past v1, CI builds v1), the checkout built (exit 2), lib/ and cyrius.lock not written"
else bad "L2 (rc=$rc exit=$ex written=[$wrote]): $(grep -m3 'local\|hint\|error' "$W/l2.out")"; fi
# ── L3 ──
main_calls sib_v 'include "lib/sib.cyr"\n'
LCL=1; b l3; LCL=""
r3=$rc; e3=$ex
b l3d
if [ "$r3" -eq 0 ] && [ "$e3" -eq 2 ] && ! grep -qi 'duplicate' "$W/l3.out" && [ "$rc" -eq 0 ] && [ "$ex" -eq 1 ]; then
    ok "L3 a hand-written include \"lib/sib.cyr\": local mode compiles the override once (exit 2, no duplicate), no switch the tag (exit 1)"
else bad "L3 (local rc=$r3 exit=$e3; default rc=$rc exit=$ex): $(grep -m2 -i 'duplicate\|error' "$W/l3.out")"; fi
main_calls sib_v ""
# ── L4 ──
LCL=sib; b l4a; LCL=""; e4a=$ex
LCL=other; b l4b; LCL=""; e4b=$ex
if [ "$e4a" -eq 2 ] && [ "$e4b" -eq 1 ] && grep -q "^warning: CYRIUS_LOCAL selects 'other', but no \[deps.other\] in this resolve declares a path$" "$W/l4b.out"; then
    ok "L4 CYRIUS_LOCAL=sib builds the checkout (exit 2); CYRIUS_LOCAL=other builds the tag (exit 1) and warns by name"
else bad "L4 (sib exit=$e4a other exit=$e4b): $(grep -m2 'warning\|local' "$W/l4b.out")"; fi
# ── L5 ──
LCL=1; b l5a --no-local; LCL=""; e5a=$ex
b l5b --local; e5b=$ex
b l5c --local=sib; e5c=$ex
rc=0; cy deps --local= > "$W/l5d.out" 2>&1 || rc=$?
if [ "$e5a" -eq 1 ] && [ "$e5b" -eq 2 ] && [ "$e5c" -eq 2 ] && [ "$rc" -eq 1 ] && grep -q '^error: --local= names no dependency' "$W/l5d.out"; then
    ok "L5 --no-local beats CYRIUS_LOCAL=1 (exit 1); --local and --local=sib build the checkout (exit 2); --local= is refused by name"
else bad "L5 (no-local=$e5a local=$e5b local=sib=$e5c empty rc=$rc): $(head -1 "$W/l5d.out")"; fi
# ── L6: a ROOT path-only dep, unchanged ──
mkp app6 <<EOF
[deps.leaf]
path = "../leaf"
modules = ["dist/leaf.cyr"]
EOF
main_calls leaf_v ""
b l6
if [ "$rc" -eq 0 ] && [ "$ex" -eq 99 ] && cmp -s "$P/lib/leaf.cyr" "$WS/leaf/dist/leaf.cyr" && [ -f "$P/cyrius.lock" ] \
   && ! grep -q '^local' "$W/l6.out" && ! grep -q '^hint' "$W/l6.out"; then
    ok "L6 a root path-only dep: resolved from its path with no switch (exit 99), lib/ + lock written, no local/hint line"
else bad "L6 (rc=$rc exit=$ex): $(grep -m2 'local\|error\|hint' "$W/l6.out")"; fi
# ── L7: a tag-resolved dep's own manifest ──
mkp app7a <<EOF
[deps.mid]
git = "file://$W/o/mid"
tag = "v1"
modules = ["dist/mid.cyr"]
EOF
main_calls leaf_v ""
# the path mid's manifest names, relative to mid's clone — present, and poisoned
mkdir -p "$H/deps/mid/leaf/dist" && printf 'fn leaf_v(): i64 { return 66; }\n' > "$H/deps/mid/leaf/dist/leaf.cyr"
b l7a
a7=0
if [ "$rc" -eq 0 ] && [ "$ex" -eq 10 ] && cmp -s "$P/lib/leaf.cyr" "$W/o/leaf/dist/leaf.cyr"; then a7=1; fi
mk7() {   # $1 project, $2 dep
    mkp "$1" <<EOF
[deps.$2]
git = "file://$W/o/$2"
tag = "v1"
modules = ["dist/$2.cyr"]
EOF
    rc=0; cy deps > "$W/$1.out" 2>&1 || rc=$?
}
mk7 app7b midpo; rb=$rc
mk7 app7c midabs; rcc=$rc
mk7 app7d midlg; rd=$rc
if [ "$a7" -eq 1 ] && [ "$rb" -eq 1 ] && [ "$rcc" -eq 1 ] && [ "$rd" -eq 1 ] \
   && grep -qF "error: midpo's manifest names [deps.leaf] path = \"../leaf\" with no git / tag — a published dependency must name git + tag; refused" "$W/app7b.out" \
   && grep -qF "error: midabs's manifest names [deps.leaf] path = \"$W/ws/leaf\", an absolute path — a dependency's manifest must be portable; refused" "$W/app7c.out" \
   && grep -qF "error: midlg's manifest names [deps.leaf] git = \"../leaf\", a local repository — a published dependency must name a remote git + tag; refused" "$W/app7d.out" \
   && [ ! -f "$WS/app7b/lib/leaf.cyr" ] && [ ! -f "$WS/app7c/lib/leaf.cyr" ]; then
    ok "L7 a tag-resolved dep: its path beside a remote git is dropped (leaf's tag, exit 10, a present path ignored); path-only, absolute and local-git entries refused by name"
else bad "L7 (a=$a7 exit=$ex b=$rb c=$rcc d=$rd): $(grep -h -m1 'error' "$W/app7b.out" "$W/app7c.out" "$W/app7d.out" 2>/dev/null | head -3)"; fi
# ── L8: a local checkout's own override ──
mkp app8 <<EOF
[deps.mid]
git = "file://$W/o/mid"
tag = "v1"
path = "../mid"
modules = ["dist/mid.cyr"]
EOF
main_calls leaf_v ""
LCL=1; b l8a; LCL=""; e8a=$ex
LCL=mid; b l8b; LCL=""; e8b=$ex
if [ "$e8a" -eq 99 ] && [ "$(grep -c '^local: ' "$W/l8a.out")" -eq 2 ] && grep -q '^local: leaf <- \.\./leaf (via mid) @[0-9a-f]\{7\}, at v1, dirty — CI builds v1$' "$W/l8a.out" \
   && [ "$e8b" -eq 10 ] && [ "$(grep -c '^local: ' "$W/l8b.out")" -eq 1 ]; then
    ok "L8 a local checkout's own override: followed when selected (CYRIUS_LOCAL=1: leaf via mid, dirty, exit 99), not when only mid is (exit 10)"
else bad "L8 (all exit=$e8a mid exit=$e8b): $(grep -m3 '^local' "$W/l8a.out")"; fi
# ── L9: a local checkout's path-only entry ──
mkp app9 <<EOF
[deps.midpo]
git = "file://$W/o/midpo"
tag = "v1"
path = "../midpo"
modules = ["dist/midpo.cyr"]
EOF
main_calls leaf_v ""
LCL=midpo; rc=0; cy deps > "$W/l9a.out" 2>&1 || rc=$?; r9a=$rc; LCL=""
LCL=1; b l9b; LCL=""
if [ "$r9a" -eq 1 ] && grep -qF "error: midpo's manifest names [deps.leaf] path = \"../leaf\" has no remote source, and leaf is not selected — CYRIUS_LOCAL=1 (or --local=midpo,leaf) builds it from that checkout; refused" "$W/l9a.out" \
   && [ "$ex" -eq 99 ]; then
    ok "L9 a local checkout's path-only entry: refused while unselected, naming the switch that builds it; CYRIUS_LOCAL=1 builds it (exit 99)"
else bad "L9 (midpo rc=$r9a, all exit=$ex): $(grep -m1 error "$W/l9a.out")"; fi
# ── L10 ── (the release verbs; --locked's share of the rule is pinned by deps_locked_writes_nothing.sh)
P="$WS/app"
rc=0; cy deps --local --no-local > "$W/l10a.out" 2>&1 || rc=$?; r10a=$rc
rc=0; cy publish --local > "$W/l10b.out" 2>&1 || rc=$?; r10b=$rc
rm -rf "$P/build/app"
LCL=1; rc=0; cy package > "$W/l10c.out" 2>&1 || rc=$?; r10c=$rc; LCL=""
ex=-1; [ -x "$P/build/app" ] && { ex=0; "$P/build/app" > /dev/null 2>&1 || ex=$?; }
if [ "$r10a" -eq 1 ] && grep -q '^error: --local and --no-local contradict each other$' "$W/l10a.out" \
   && [ "$r10b" -eq 1 ] && grep -q '^error: cyrius publish resolves what a release ships, the tags — --local is refused$' "$W/l10b.out" \
   && [ "$r10c" -eq 0 ] && grep -q '^note: CYRIUS_LOCAL is ignored here — cyrius package resolves the tags$' "$W/l10c.out" \
   && ! grep -q '^local: ' "$W/l10c.out" && [ "$ex" -eq 1 ]; then
    ok "L10 --local + --no-local and publish --local refused by name; CYRIUS_LOCAL=1 under package: one note, the tag packaged (exit 1)"
else bad "L10 (a=$r10a b=$r10b c=$r10c exit=$ex): $(cat "$W/l10a.out" "$W/l10b.out" "$W/l10c.out" | grep -m3 'error\|note')"; fi
# ── L11: local mode with no override in use ──
mkp app11 <<EOF
[deps.leaf]
git = "file://$W/o/leaf"
tag = "v1"
modules = ["dist/leaf.cyr"]
EOF
main_calls leaf_v ""
LCL=1; b l11; LCL=""
if [ "$rc" -eq 0 ] && [ "$ex" -eq 10 ] && [ -f "$P/cyrius.lock" ] && cmp -s "$P/lib/leaf.cyr" "$W/o/leaf/dist/leaf.cyr" && [ ! -d "$P/build/local-deps" ]; then
    ok "L11 CYRIUS_LOCAL=1 with no override in use: lib/ and cyrius.lock written exactly as the default resolve, no build/local-deps"
else bad "L11 (rc=$rc exit=$ex): $(grep -m2 'local\|error' "$W/l11.out")"; fi
# ── L12: a stale overlay in the shell ──
P="$WS/app"
LOV=build/local-deps/lib; b l12; LOV=""
if [ "$rc" -eq 0 ] && [ "$ex" -eq 1 ] && cmp -s "$P/build/local-deps/lib/sib.cyr" "$WS/sib/dist/sib.cyr"; then
    ok "L12 CYRIUS_LIB_OVERLAY left in the shell: a default build still compiles the tag (exit 1) beside an override-holding build/local-deps"
else bad "L12 (rc=$rc exit=$ex)"; fi
# ── L13: each local resolve starts clean ──
printf 'fn junk(): i64 { return 0; }\n' > "$P/build/local-deps/lib/junk.cyr"
LCL=1; b l13; LCL=""
if [ "$rc" -eq 0 ] && [ "$ex" -eq 2 ] && [ ! -e "$P/build/local-deps/lib/junk.cyr" ]; then
    ok "L13 a local-mode resolve starts from an empty build/local-deps/lib (a planted file is gone)"
else bad "L13 (rc=$rc exit=$ex junk=$( [ -e "$P/build/local-deps/lib/junk.cyr" ] && echo present || echo gone))"; fi
# ── L14: R12 ──
mkp app14 <<EOF
[deps.leaf]
path = "../leaf"
modules = ["dist/nothere.cyr"]
EOF
rc=0; cy deps > "$W/l14.out" 2>&1 || rc=$?
if [ "$rc" -eq 1 ] && grep -qF '[deps.leaf] modules entry "dist/nothere.cyr" not found in the local path ' "$W/l14.out" && ! grep -q 'at tag' "$W/l14.out"; then
    ok "L14 a path dep's missing module names the local path, not a tag"
else bad "L14 (rc=$rc): $(grep -m1 error "$W/l14.out")"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
