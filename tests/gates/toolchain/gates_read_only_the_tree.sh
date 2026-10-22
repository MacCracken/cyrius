#!/bin/sh
# tests/gates/toolchain/gates_read_only_the_tree.sh — 6.7.16
#
# A GATE READS THIS CHECKOUT — ITS build/, ITS THROWAWAY CYRIUS_HOME AND TMPDIR — AND NEVER
# ANOTHER PROJECT'S CHECKOUT.
#
# WHY. Moving cyrius development to a new machine (2026-10-19) needed four consumer projects
# cloned AND BUILT before `release-gate.sh` could go GREEN: gates read agnos's ABI document and
# kernel source, ran mirshi's and sit's built binaries, cross-built agnoshi, parsed
# secureyeoman's .ts files and surveyed every repo beside the checkout — and SKIPped without
# them, which the release gate refuses. The user, 2026-10-19: "we need to rip out all those
# gates longer term, LANGUAGES DO NOT GATE ON OTHER PROJECTS." 6.7.16 removed every such read
# (docs/development/issues/archived/2026-10-19-gates-read-other-projects-checkouts.md); this gate keeps
# them out. Its allowlist has ZERO entries: a read it refuses is removed, never excused.
#
# WHAT IT SCANS — every NON-COMMENT line (a comment line is optional whitespace then `#`, in
# shell and cyrius alike; prose about the old reads lives in comments and is not a read):
#   * tests/gates/**/*.sh and the top-level scripts/*.sh (check.sh, release-gate.sh and the
#     gate scripts beside them). Refused:
#       S1  $HOME/Repos, ${HOME}/Repos, ${HOME:-}/Repos (any ${HOME<op>...}), "$HOME"/Repos,
#           ~/Repos
#       S2  a literal /home/<user> path, or /home/$USER, /home/${USER} (not `$T/home/bin` — a
#           scratch dir's own home/)
#       S3  CYRIUS_SIBLING_ROOT
#       S4  <root>/.. — `$ROOT/../x`, `"$ROOT"/../x`, `${R}/..` — for every variable the file
#           sets to its checkout root. DERIVED per file, not listed: an assignment whose value is
#           `dirname "$0"` followed by exactly as many `/..` as the file sits below the root (3
#           in tests/gates/<bucket>/, 1 in scripts/), a plain copy of such a variable, or a
#           column-0 `V=$(pwd)` / `V=$(pwd -P)` / `V="$PWD"` while the cwd is the root (after a
#           column-0 `cd` to `dirname "$0"` + exactly that depth, or to a root variable, and
#           before any other column-0 `cd`) — ROOT and R across the gates today (two of them by
#           `cd …; ROOT=$(pwd)`), REPO and REPO_ROOT in two scripts
#       S5  `dirname "<root>"` and `${<root>%…}` — the checkout's parent — for those same variables
#       S6  `dirname "$0"` followed by MORE `/..` than the file's depth: climbing out inline
#       S7  a bare relative read of the checkout's parent, for the files that cd to the root
#           with no root variable (release-gate.sh among them) or after `cd "$ROOT"`: a file
#           test on `../<name>` (`[ -x ../sit/… ]`, `test -d "../x"`), any `../<name>/build/`
#           path, `cd ../<name>`, and `$PWD/..` / `$(pwd)/..`
#   * programs/checks/*.cyr (the check driver). Refused:
#       C1  a string literal that BEGINS with ~/Repos, /Repos, Repos/, $HOME/Repos or
#           /home/<user>/ — `_cat2(home, "/Repos/sit")`, `"/home/macro/Repos/secureyeoman"`.
#           Only the START of a literal: a `_gate` row's description is one long literal whose
#           prose may mention a past census "under ~/Repos", and prose is not a path
#       C2  `_root_path("../x")` / `_root_path("..")`, and ROOT_PATH joined to a literal "/../x"
#       C3  CYRIUS_SIBLING_ROOT
#       C4  a string literal that BEGINS with `../` or IS `..` — the driver runs at the checkout
#           root, so `"../sit/build/sit"`, `file_exists("../x")` and `_cat3(ROOT_PATH, "/",
#           "../x")` all name the checkout's parent (a `"/../…"` traversal fixture is not one)
# NOT A READ, AND NOT FLAGGED: a fixture that WRITES `path = "../x"` or `include "../x.cyr"`
# into a scratch manifest or source — relative to its scratch dir, not to the checkout — and a
# scratch subshell's `../elf` run or `< ../in` redirect. The patterns above were measured on the
# 6.7.16 tree: zero hits, with no allowlist.
#
# WHAT IT DOES NOT SCAN, AND WHY: scripts/dev, scripts/release and scripts/folds. They hold the
# development helpers moved into the tree on 2026-10-19 (scratch from CYRIUS_SCRATCH, a fold's
# CI run in an isolated copy, release bookkeeping) — tools a developer runs by hand, which may
# legitimately name a sibling checkout (a fold's CI runs in the FOLD's repo). No gate runs them,
# and axis 4 keeps it that way.
#
# AXES
#   1  the tree is clean: every hit is named file:line: rule: the line
#   2  MUTATION: a scratch copy of a real gate (this one) with `X="$HOME/Repos/agnos/x"` planted,
#      one with `cat "$ROOT/../sit/VERSION"` planted, and a programs/checks file with a
#      "/home/macro/Repos/x" literal planted are each RED, by rule; a copy of
#      tests/gates/memory/freelist_thread_safe.sh (its root is `cd …; ROOT=$(pwd)`) with
#      `$ROOT/../x` and `dirname "$ROOT"` planted is RED (S4, S5); one planted read for each
#      other rule and spelling (S1's ${HOME:-}, S2 and its /home/$USER, S3, S5 and its
#      ${ROOT%/*}, S6, each S7 shape, C1's "/Repos/sit", both C2 shapes, each C4 shape) is RED;
#      and twelve clean spellings stay clean (a commented ~/Repos read, a fixture's
#      `path = "../x"`, `$T/home/bin`, the root derivation itself, a gate-dir `$D/../../..`, a
#      fixture's `include "../x.cyr"`, a scratch subshell's `../elf` run and `< ../in` redirect, a long
#      `_gate` literal mentioning ~/Repos, a manifest literal holding `path = \"../C\"`,
#      `ROOT_PATH` with "/tests", a "/../../etc/x" traversal fixture)
#   3  ANTI-VACUOUS: the scan read every file of each of its three roots — every file an
#      independent reader (git ls-files, else find) lists was scanned — and each count clears a
#      floor derived from the 6.7.16 tree (tests/gates 560, programs/checks 15, scripts/*.sh 28: half of each, rounded
#      down — 280, 7, 14), and the root-variable derivation found a root variable in at least
#      half of the shell files (it finds one in all but a handful)
#   4  no scanned file invokes anything under scripts/dev, scripts/release or scripts/folds
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: gates_read_only_the_tree: cannot cd to $ROOT"; exit 1; }
NAME=gates_read_only_the_tree
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
FAILS=0
_fail() { echo "  FAIL: $NAME: $1"; FAILS=$((FAILS + 1)); }

# ── the scanners ─────────────────────────────────────────────────────────────────────────
# Each prints `S <file>` per file it read, `V <file> <var>` per root variable it derived, and
# `H <file>:<line>: <rule> <why>: <text>` per refused read. Paths are relative to the scan root
# (the cwd), so a file's depth below the root is its count of `/`.
SH_AWK='
function ups_after(s,    n) { n = 0; while (substr(s, 1, 3) == "/..") { n++; s = substr(s, 4) } return n }
# the longest run of `/..` right after any `dirname "$0")` on the line; -1 when there is none
function dn0_ups(line,    s, best, u) {
    best = -1; s = line
    while (match(s, /dirname[ \t]+(--[ \t]+)?"?\$\{?0\}?"?\)/)) {
        s = substr(s, RSTART + RLENGTH)
        u = ups_after(s)
        if (u > best) best = u
    }
    return best
}
function hit(rule, why) { printf "H %s:%d: %s %s: %s\n", FILENAME, FNR, rule, why, $0 }
FNR == 1 {
    print "S " FILENAME
    depth = gsub(/\//, "/", FILENAME)
    split("", RV)
    cdroot = 0    # 1 while a column-0 cd has made the cwd the checkout root
    while ((getline l < FILENAME) > 0) {
        if (l ~ /^[ \t]*#/) continue
        if (l ~ /^cd[ \t]/) {
            cdroot = (dn0_ups(l) == depth)
            for (r in RV) if (l ~ ("^cd[ \t]+\"?\\$\\{?" r "\\}?\"?[ \t]*(\\|\\||&&|;|$)")) cdroot = 1
            continue
        }
        if (l !~ /^[ \t]*(export[ \t]+|readonly[ \t]+)?[A-Za-z_][A-Za-z0-9_]*=/) continue
        v = l; sub(/^[ \t]*(export[ \t]+|readonly[ \t]+)?/, "", v); sub(/=.*/, "", v)
        val = l; sub(/^[^=]*=/, "", val)
        isroot = (dn0_ups(l) == depth)
        for (r in RV) if (val ~ ("^\"?\\$\\{?" r "\\}?\"?[ \t]*(;|$)")) isroot = 1
        if (cdroot && l ~ /^(export[ \t]+|readonly[ \t]+)?[A-Za-z_]/ &&
            val ~ /^"?(\$\(pwd([ \t]+-P)?\)|\$\{?PWD\}?)"?[ \t]*(;|$)/) isroot = 1
        if (isroot && !(v in RV)) { RV[v] = 1; print "V " FILENAME " " v }
    }
    close(FILENAME)
}
/^[ \t]*#/ { next }
{
    if ($0 ~ /((\$HOME|\$\{HOME(:?[-=?+][^}]*)?\})"?|~)\/Re[p]os([^A-Za-z0-9_]|$)/) hit("S1", "reads a Re" "pos dir under HOME")
    if ($0 ~ /(^|[^A-Za-z0-9_}$.\/-])\/ho[m]e\/(\$\{?[A-Za-z_]|[A-Za-z0-9._-])/) hit("S2", "names a home-directory path")
    if ($0 ~ /CYRIUS_SIBLING_[R]OOT/) hit("S3", "reads the sibling-root variable")
    for (r in RV) {
        if ($0 ~ ("\\$\\{?" r "\\}?\"?/\\.\\.([/\"'"'"' \t);|&]|$)")) hit("S4", "reads above the checkout root ($" r "/..)")
        if ($0 ~ ("dirname[ \t]+(--[ \t]+)?\"?\\$\\{?" r "\\}?\"?([^A-Za-z0-9_]|$)")) hit("S5", "takes the checkout root'"'"'s parent (dirname $" r ")")
        if ($0 ~ ("\\$\\{" r "%")) hit("S5", "takes the checkout root'"'"'s parent (${" r "%...})")
    }
    if (dn0_ups($0) > depth) hit("S6", "climbs above the checkout from dirname \"$0\"")
    if ($0 ~ /(\[|test)[ \t]+(![ \t]+)?-[A-Za-z][ \t]+"?\.\.\/[A-Za-z0-9_.-]/) hit("S7", "tests a path in the checkout'"'"'s parent (../<name>)")
    if ($0 ~ /\.\.\/[A-Za-z0-9_.-]+\/build\//) hit("S7", "names another checkout'"'"'s build/ (../<name>/build/)")
    if ($0 ~ /(^|[ \t;&|(])cd[ \t]+"?\.\.\/[A-Za-z0-9_.-]/) hit("S7", "cds into ../<name>")
    if ($0 ~ /(\$\{?PWD\}?|\$\(pwd\))"?\/\.\.([^A-Za-z0-9_.-]|$)/) hit("S7", "climbs from the cwd (PWD/..)")
}'
CYR_AWK='
function hit(rule, why) { printf "H %s:%d: %s %s: %s\n", FILENAME, FNR, rule, why, $0 }
FNR == 1 { print "S " FILENAME }
/^[ \t]*#/ { next }
{
    s = $0
    while (match(s, /"([^"\\]|\\.)*"/)) {
        lit = substr(s, RSTART + 1, RLENGTH - 2)
        s = substr(s, RSTART + RLENGTH)
        if (lit ~ /^(~\/Re[p]os|\/Re[p]os|Re[p]os\/|\$HOME\/Re[p]os|\$\{HOME\}\/Re[p]os)/ || lit ~ /^\/ho[m]e\/[A-Za-z0-9._-]+\//) {
            hit("C1", "a literal path into another checkout (\"" lit "\")")
        }
    }
    if ($0 ~ /_root_path\([ \t]*"\.\.(\/|")/) hit("C2", "_root_path above the checkout root")
    if ($0 ~ /ROOT_PATH[ \t]*,[ \t]*"\/\.\.(\/|")/) hit("C2", "ROOT_PATH joined above the checkout root")
    if ($0 ~ /CYRIUS_SIBLING_[R]OOT/) hit("C3", "reads the sibling-root variable")
    s = $0
    while (match(s, /"([^"\\]|\\.)*"/)) {
        lit = substr(s, RSTART + 1, RLENGTH - 2)
        s = substr(s, RSTART + RLENGTH)
        if (lit ~ /^\.\.(\/|$)/) hit("C4", "a relative literal above the cwd, which is the checkout root (\"" lit "\")")
    }
}'
# _scan <root> <out>: scans the three roots under <root>; the records land in <out>.
_scan() {
    ( cd "$1" || exit 1
      _sh=$( { find tests/gates -name '*.sh' -type f 2>/dev/null; for _f in scripts/*.sh; do [ -f "$_f" ] && echo "$_f"; done; } | LC_ALL=C sort)
      _cy=$(find programs/checks -name '*.cyr' -type f 2>/dev/null | LC_ALL=C sort)
      # shellcheck disable=SC2086
      [ -z "$_sh" ] || awk "$SH_AWK" $_sh
      # shellcheck disable=SC2086
      [ -z "$_cy" ] || awk "$CYR_AWK" $_cy
    ) > "$2" 2> "$2.err"
}

# ── axis 1: the tree is clean ─────────────────────────────────────────────────────────────
_scan "$ROOT" "$T/tree" || _fail "axis 1: the scan itself failed: $(head -3 "$T/tree.err")"
[ -s "$T/tree.err" ] && _fail "axis 1: the scanner wrote errors: $(head -3 "$T/tree.err")"
NH=$(grep -c '^H ' "$T/tree" || true)
if [ "$NH" -gt 0 ]; then
    _fail "axis 1: $NH read(s) of another checkout (allowlist: none — remove the read):"
    grep '^H ' "$T/tree" | sed 's/^H /      /' | cut -c1-240
else
    echo "  ok: axis 1: no gate, check.sh row, release-gate.sh step or driver row reads outside the checkout"
fi

# ── axis 2: MUTATION — each planted read is RED; the clean spellings are not ───────────────
# The planted lines are assembled from parts (RP, HM, UP, SR) so that THIS file's own lines
# carry none of the shapes it refuses — the allowlist has zero entries, this gate included.
RP=Re; RP=${RP}pos            # the Repos dir name
HM=ho; HM=${HM}me             # the home-directory root
UP=..                         # one parent step
SR=CYRIUS_SIBLING_; SR=${SR}ROOT
M="$T/mut"
_mk() { rm -rf "$M"; mkdir -p "$M/tests/gates/toolchain" "$M/programs/checks" "$M/scripts"; }
_hits() { _scan "$M" "$T/m.out"; grep '^H ' "$T/m.out" || true; }
G0='#!/bin/sh
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1'
# m1 / m2 are a COPY of a real gate (this one — axis 1 proves it clean) with one line planted
# at its end, so the root variable the plant uses is the one the derivation finds in a real file.
SELF="$ROOT/tests/gates/toolchain/$NAME.sh"
NSELF=$(wc -l < "$SELF" | tr -d ' ')
_mk; { cat "$SELF"; printf 'X="$HOME/%s/agnos/x"\n' "$RP"; } > "$M/tests/gates/toolchain/m1.sh"
case "$(_hits)" in *"m1.sh:$((NSELF + 1)): S1 "*) echo "  ok: axis 2: a copied gate with X=\"<HOME>/$RP/agnos/x\" planted is RED (S1)" ;;
    *) _fail "axis 2: a planted HOME/$RP read was NOT caught: $(_hits)" ;; esac
_mk; { cat "$SELF"; printf 'cat "$ROOT/%s/sit/VERSION"\n' "$UP"; } > "$M/tests/gates/toolchain/m2.sh"
case "$(_hits)" in *"m2.sh:$((NSELF + 1)): S4 "*) echo "  ok: axis 2: a copied gate with \"<ROOT>/$UP/sit\" planted is RED (S4)" ;;
    *) _fail "axis 2: a planted <ROOT>/$UP/sit read was NOT caught: $(_hits)" ;; esac
_mk; printf 'fn _m3(): i64 {\n    var d = "/%s/macro/%s/x";\n    return 0;\n}\n' "$HM" "$RP" > "$M/programs/checks/m3.cyr"
case "$(_hits)" in *"m3.cyr:2: C1 "*) echo "  ok: axis 2: a planted programs/checks \"/$HM/macro/$RP/x\" literal is RED (C1)" ;;
    *) _fail "axis 2: a planted /$HM/<user>/ literal in programs/checks was NOT caught: $(_hits)" ;; esac
# the remaining rules, one planted read each (a rule nothing exercises can rot unseen)
_mk; { printf '%s\n' "$G0"; printf 'R=$(cd "$(dirname "$0")/../../.." && pwd)\n'
       printf 'P=$(dirname "$R")\n'
       printf 'S=${%s:-x}\n' "$SR"
       printf 'Y=$(cd "$(dirname "$0")/%s/%s/%s/%s/agnos" && pwd)\n' "$UP" "$UP" "$UP" "$UP"
       printf 'Z=/%s/someone/%s/x\n' "$HM" "$RP"; } > "$M/tests/gates/toolchain/m4.sh"
printf 'fn _m5(): i64 { var s = _root_path("%s/sit"); var t = _cat2(ROOT_PATH, "/%s/x"); var h = _cat2(home, "/%s/sit"); return 0; }\n' "$UP" "$UP" "$RP" > "$M/programs/checks/m5.cyr"
H5=$(_hits)
for want in "m4.sh:5: S5 " "m4.sh:6: S3 " "m4.sh:7: S6 " "m4.sh:8: S2 " "m5.cyr:1: C1 " "m5.cyr:1: C2 "; do
    case "$H5" in *"$want"*) ;; *) _fail "axis 2: the planted read for rule ${want##*: } was NOT caught (want '$want'): $H5" ;; esac
done
[ "$(printf '%s\n' "$H5" | grep -c 'm5.cyr:1: C2 ' || true)" = 2 ] || _fail "axis 2: _root_path(\"$UP/sit\") and ROOT_PATH + \"/$UP/x\" are not BOTH caught: $H5"
case "$H5" in *"m4.sh:5: S5 "*"m4.sh:6: S3 "*"m4.sh:7: S6 "*"m4.sh:8: S2 "*"m5.cyr:1: C1 "*) echo "  ok: axis 2: S2, S3, S5, S6, C1 (\"/$RP/sit\") and both C2 shapes are each RED on a planted read" ;; esac
# m6 is a COPY of a real gate whose root is `cd "$(dirname "$0")/../../.."; ROOT=$(pwd)` (no
# `dirname "$0"` in the assignment), at its own depth: the derivation must find ROOT there too.
CD0="$ROOT/tests/gates/memory/freelist_thread_safe.sh"
N6=$(wc -l < "$CD0" | tr -d ' ')
_mk; mkdir -p "$M/tests/gates/memory"
{ cat "$CD0"; printf 'cat "$ROOT/%s/x/VERSION"\n' "$UP"; printf 'P=$(dirname "$%s")\n' ROOT; } > "$M/tests/gates/memory/m6.sh"
H6=$(_hits)
grep -q '^V tests/gates/memory/m6.sh ROOT$' "$T/m.out" || _fail "axis 2: the cd-then-pwd root of a copied freelist_thread_safe.sh was not derived: $(grep '^V tests/gates/memory/m6.sh' "$T/m.out")"
case "$H6" in *"m6.sh:$((N6 + 1)): S4 "*"m6.sh:$((N6 + 2)): S5 "*) echo "  ok: axis 2: a copied freelist_thread_safe.sh (root by cd + pwd) with <ROOT>/$UP/x and dirname <ROOT> planted is RED (S4, S5)" ;;
    *) _fail "axis 2: a cd + pwd root's <ROOT>/$UP and dirname <ROOT> were NOT both caught: $H6" ;; esac
# the widened spellings and the bare-relative S7 / C4 shapes, one planted read each
_mk; { printf '%s\n' "$G0"
       printf 'B="${HOME:-}/%s/agnos/x"\n' "$RP"
       printf 'C=/%s/$USER/%s/agnos\n' "$HM" "$RP"
       printf 'E="${%s%%/*}/sit"\n' ROOT
       printf '[ -x %s/sit/build/sit ] && echo y\n' "$UP"
       printf 'D=%s/mirshi/build/mirshi\n' "$UP"
       printf '(cd %s/agnoshi && ls)\n' "$UP"
       printf 'cat "$PWD/%s/sit/VERSION"\n' "$UP"
       printf 'test ! -d "%s/agnos" || echo y\n' "$UP"; } > "$M/tests/gates/toolchain/m7.sh"
{ printf 'fn _m8(): i64 {\n'
  printf '    var a = "%s/sit/build/sit";\n' "$UP"
  printf '    if (file_exists("%s/mirshi/build/mirshi") == 1) { return 1; }\n' "$UP"
  printf '    var b = _cat3(ROOT_PATH, "/", "%s/agnos");\n' "$UP"
  printf '    var c = "%s";\n' "$UP"
  printf '    return 0;\n}\n'; } > "$M/programs/checks/m8.cyr"
H7=$(_hits)
for want in "m7.sh:4: S1 " "m7.sh:5: S2 " "m7.sh:6: S5 " "m7.sh:7: S7 " "m7.sh:8: S7 " "m7.sh:9: S7 " "m7.sh:10: S7 " "m7.sh:11: S7 " \
            "m8.cyr:2: C4 " "m8.cyr:3: C4 " "m8.cyr:4: C4 " "m8.cyr:5: C4 "; do
    case "$H7" in *"$want"*) ;; *) _fail "axis 2: the planted read '$want' was NOT caught: $H7" ;; esac
done
case "$H7" in *"m7.sh:4: S1 "*"m7.sh:5: S2 "*"m7.sh:6: S5 "*"m7.sh:7: S7 "*"m7.sh:8: S7 "*"m7.sh:9: S7 "*"m7.sh:10: S7 "*"m7.sh:11: S7 "*"m8.cyr:2: C4 "*"m8.cyr:3: C4 "*"m8.cyr:4: C4 "*"m8.cyr:5: C4 "*)
    echo "  ok: axis 2: \${HOME:-}/$RP (S1), /$HM/\$USER (S2), \${<root>%/*} (S5), a file test on / a build path under / a cd into / a PWD climb to $UP/<name> (S7), and four driver literals starting $UP (C4) are each RED" ;; esac
# clean spellings: none may trip
_mk; { printf '%s\n' "$G0"
       printf '# a comment: X="$HOME/%s/agnos/x" and cat "$ROOT/%s/sit/VERSION"\n' "$RP" "$UP"
       printf '    # an indented comment: ~/%s\n' "$RP"
       printf 'printf '"'"'[deps.a]\\npath = "../x"\\n'"'"' > "$T/p/cyrius.cyml"\n'
       printf 'mkdir -p "$T/%s/bin"; cp x "$T/%s/bin/cycc"\n' "$HM" "$HM"
       printf 'D=$(dirname "$0"); cat "$D/../../../VERSION"\n'
       printf 'include_line='"'"'include "../x.cyr"'"'"'\n'
       printf 'rc=0; ( cd "$D/n" && ../elf > "$D/elf.out" 2>&1 ) || rc=$?\n'
       printf '(cd "$T/h7" && "$VM" < ../h7.cyx > ../h7.out 2>&1) || rc=$?\n'; } > "$M/tests/gates/toolchain/c1.sh"
{ printf 'fn _c2(): i64 {\n'
  printf '    _gate("a census of every repo under ~/%s found none", "tests/gates/x.sh");\n' "$RP"
  printf '    str_builder_add_cstr(sb, "[package]\\nname = \\"B\\"\\npath = \\"../C\\"\\n");\n'
  printf '    # var d = "/%s/macro/%s/x";\n' "$HM" "$RP"
  printf '    var p = _cat2(ROOT_PATH, "/tests/gates");\n'
  printf '    str_builder_add_cstr(trav_sb, "/../../../etc/evil.cyr\\",\\"languageId\\":1");\n'
  printf '    return 0;\n}\n'; } > "$M/programs/checks/c2.cyr"
HC=$(_hits)
[ -z "$HC" ] && echo "  ok: axis 2: the twelve clean spellings (comments, a fixture's path = ../x and include ../x.cyr, \$T/$HM, the root derivation, \$D/../../.., a scratch subshell's ../elf run and ../in redirect, _gate prose, an escaped manifest literal, ROOT_PATH + /tests, a /../ traversal literal) stay clean" \
    || _fail "axis 2: a clean spelling was flagged (a false positive): $HC"
# the planted files really hold the shapes (a printf that lost its argument plants nothing)
grep -q "/$RP/agnos" "$M/tests/gates/toolchain/c1.sh" && grep -q "~/$RP found" "$M/programs/checks/c2.cyr" \
    || _fail "axis 2: the clean-spelling fixtures were not written as intended"

# ── axis 3: ANTI-VACUOUS — every file of each root was scanned, and the derivation works ───
# The independent reader is `git ls-files` (find when this is not a git checkout): every file
# it lists must appear among the files the scanners read. An untracked file the scan also read
# is fine; a tracked one it did not read is a blind spot.
grep '^S ' "$T/tree" | sed 's/^S //' | LC_ALL=C sort -u > "$T/scanned"
if git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1; then
    { git -C "$ROOT" ls-files -- 'tests/gates/*.sh' 'programs/checks/*.cyr'
      git -C "$ROOT" ls-files -- 'scripts/*.sh' | grep -v '^scripts/.*/' || true; } | LC_ALL=C sort -u > "$T/listed"
else
    { find tests/gates -name '*.sh' -type f; find programs/checks -name '*.cyr' -type f
      find scripts -maxdepth 1 -name '*.sh' -type f; } | LC_ALL=C sort -u > "$T/listed"
fi
MISS=$(LC_ALL=C comm -23 "$T/listed" "$T/scanned")
[ -z "$MISS" ] || _fail "axis 3: listed but NOT scanned: $(printf '%s\n' "$MISS" | head -5 | tr '\n' ' ')"
NG=$(grep -c '^tests/gates/' "$T/scanned" || true)
NP=$(grep -c '^programs/checks/' "$T/scanned" || true)
NS=$(grep -c '^scripts/' "$T/scanned" || true)
NL=$(grep -c . "$T/listed" || true)
[ "$NL" -ge 300 ] || _fail "axis 3: the independent reader listed only $NL files (floor 300) — it is not reading the tree"
[ "$NG" -ge 280 ] || _fail "axis 3: only $NG tests/gates files scanned (floor 280) — the scan read too little"
[ "$NP" -ge 7 ] || _fail "axis 3: only $NP programs/checks files scanned (floor 7)"
[ "$NS" -ge 14 ] || _fail "axis 3: only $NS scripts/*.sh files scanned (floor 14)"
NV=$(grep '^V ' "$T/tree" | awk '{print $2}' | LC_ALL=C sort -u | grep -c . || true)
[ "$NV" -ge $(((NG + NS) / 2)) ] || _fail "axis 3: a root variable was derived in only $NV of $((NG + NS)) shell files — the derivation went blind, so S4 / S5 check nothing"
grep -q '^V tests/gates/toolchain/gates_read_only_the_tree.sh ROOT$' "$T/tree" || _fail "axis 3: this gate's own ROOT was not derived as a root variable"
[ "$FAILS" = 0 ] && echo "  ok: axis 3: scanned all $NL listed files ($NG tests/gates + $NP programs/checks + $NS scripts; floors 280 / 7 / 14); root variables derived in $NV shell files"

# ── axis 4: nothing scanned invokes the development helpers ───────────────────────────────
HD=$( { find tests/gates -name '*.sh' -type f; for _f in scripts/*.sh; do [ -f "$_f" ] && echo "$_f"; done
        find programs/checks -name '*.cyr' -type f; } | LC_ALL=C sort \
      | while IFS= read -r _f; do awk -v F="$_f" '/^[ \t]*#/ { next } /scripts\/(dev|release|folds)\// { print F ":" FNR ": " $0 }' "$_f"; done || true)
if [ -n "$HD" ]; then
    _fail "axis 4: a gate, check.sh, release-gate.sh or the driver invokes a development helper (scripts/dev|release|folds are not gates):"
    printf '%s\n' "$HD" | sed 's/^/      /' | cut -c1-240
else
    echo "  ok: axis 4: no scanned file invokes anything under scripts/dev, scripts/release or scripts/folds"
fi

if [ "$FAILS" != 0 ]; then echo "FAIL: $NAME ($FAILS)"; exit 1; fi
echo "PASS: $NAME — no gate, check row or release-gate step reads another checkout ($NG + $NP + $NS files, allowlist of zero; every rule and spelling RED on a planted read, 12 clean spellings clean)"
