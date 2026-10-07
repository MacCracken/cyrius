#!/bin/sh
# refresh_never_installs_a_stale_bin.sh — `install.sh --refresh-only` rebuilds every bin it
# installs whenever anything it is built from changed (or refuses), and verify-store judges the
# one untracked bin it can rebuild.
#
# 6.6.20 (RS-02). `cybs` — the bootstrap compiler, the root of the seed → cybs → cycc chain —
# is listed in cyrius.cyml `bins` but has no programs/cybs.cyr. `_rebuild_stale` returned 0 for
# a missing source, and the copy loop then installed whatever gitignored build/cybs the clone
# held: a 12,344 B June binary that prints `syntax error` on src/main.cyr, in 16 tagged slots
# (6.6.3–6.6.9, 6.6.11–6.6.19), each stamped `tree-matches-tag: yes`, plus the in-flight
# 6.6.20. verify-store judged only
# the TRACKED bins and named only the cross-bins as unverified, so it reported every one OK.
#
# Everything runs in mktemp trees against mktemp homes (HOME too) — never the live ~/.cyrius.
#   axis 1  a tagged mini repo at tree == tag holding a STALE build/cybs: the slot's bin/cybs is
#           the seed-assembled bootstrap/cybs.cyr (and so is build/cybs), not the stale bytes
#   axis 2  a bin listed in `bins` with no source: the refresh REFUSES, names the bin and its
#           missing source, and installs nothing (the planted build/<bin> never reaches the slot)
#   axis 3  a cybs that fails the closure (it does not compile bootstrap/asm.cyr to the seed):
#           refused, build/cybs removed, the slot's bin/cybs untouched
#   axis 4  verify-store: a slot whose cybs is not the tag's, and whose bin/asm is not the
#           tag's bootstrap/asm, is BAD with both named; untracked bins are NAMED as unverified
#           (and cybs is not among them); --restore re-assembles cybs + restores asm; the report
#           is then clean (anti-vacuous: a correct slot verifies OK)
#
# 6.6.20 (RS-03). `_rebuild_stale`'s dependency roots were per-bin — "lib" for programs/<bin>,
# "lib cbt" for `cyrius` — while programs/cyrius-lsp.cyr includes cbt/srcscan.cyr (6.6.10),
# programs/ark.cyr includes programs/nous_stub.cyr and cbt/cyrius.cyr includes
# src/version_str.cyr; and build/cycc was no dependency at all. An edit to any of those left
# the installed binary stale against a fresh compile. Axes run in a tree carrying the real
# sources of those three bins, with mtimes SET (sources + compiler 2020, bins 2021, edit 2022):
#   axis 5  the first refresh builds all three
#   axis 6  ANTI-VACUOUS control: nothing newer than the bins → nothing rebuilt
#   axis 7  edit cbt/srcscan.cyr      → cyrius-lsp rebuilt; installed == a fresh compile
#   axis 8  edit programs/nous_stub.cyr → ark rebuilt; installed == a fresh compile
#   axis 9  edit src/version_str.cyr  → cyrius rebuilt; installed == a fresh compile
#           (each edit axis first proves its edit changes that bin's code)
#   axis 10 build/cycc newer than the bins → all rebuilt
#
# 6.6.20 (RS-02 review): the CROSS-bin arms. cycc_win skipped silently on a missing source or
# compiler and only WARNED on a failed compile; the unknown-entry arm warned it "will copy
# existing build/<bin>". Either way the copy loop installed a build/<bin> nothing rebuilt —
# measured: a broken src/main_win.cyr gave refresh rc 0 and the slot kept the old cycc_win.
#   axis 11 a tiny src/main_win.cyr: cycc_win rebuilt, installed == a fresh PE compile
#           (anti-vacuous — the arm still builds)
#   axis 12 that source broken: refused by name, build/cycc_win removed, the slot's cycc_win
#           still axis 11's bytes
#   axis 13 the source deleted, a stale build/cycc_win planted: refused, naming the source,
#           the slot untouched
#   axis 14 a cross_bins entry with no rebuild rule, its build/<bin> planted: refused by
#           name, never installed
#
# Mutation ledger (MEASURED in a scratch ROOT at 6.6.20 — re-run, don't trust):
#   install.sh + verify-store.sh as they were at 6.6.19              → axes 1 2 3 4 4r red
#   the `cybs) _rebuild_cybs` arm made a no-op                       → axes 1 3 red
#   `[ -f "$source" ] || return 0` restored in _rebuild_stale         → axis 2 red
#   the closure `cmp` dropped from _rebuild_cybs                      → axis 3 red
#   verify_slot never judges cybs                                     → axis 4 red
#   restore_slot never re-assembles cybs                              → axis 4r red
#   install.sh as of the RS-02 commit (per-bin roots, no cycc dep)    → axes 7 8 9 10 red
#   the union cut back to "lib"                                       → axes 7 8 9 red
#   the union cut back to "lib cbt" (the old `cyrius` arm)            → axes 8 9 red
#   the `build/cycc -nt build/<bin>` dependency dropped               → axis 10 red
#   the cross_bins arms as of the RS-03..CLN-01 commits (warn/skip)   → axes 12 13 14 red
#   only the cycc_win compile failure made fatal (skip arms left)      → axes 13 14 red
#   only the unknown-entry arm made fatal                              → axes 12 13 red
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
G=refresh_never_installs_a_stale_bin
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "SKIP: $G: git not found"; exit 77; }
[ "$(uname -s)/$(uname -m)" = Linux/x86_64 ] || { echo "SKIP: $G: the seed (bootstrap/asm) is an x86-64 Linux ELF"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

# What a correct cybs IS, computed here the way bootstrap/bootstrap.sh does it.
"$ROOT/bootstrap/asm" < "$ROOT/bootstrap/cybs.cyr" > "$W/cybs.expected" \
  || { echo "FAIL: $G: the seed did not assemble bootstrap/cybs.cyr"; exit 1; }
[ -s "$W/cybs.expected" ] || { echo "FAIL: $G: the seed produced an empty cybs"; exit 1; }
printf '#!/bin/sh\necho stale-june-cybs\nexit 1\n' > "$W/cybs.stale"; chmod +x "$W/cybs.stale"

# ── a mini cyrius repo: VERSION 9.9.9 tagged; cybs + the seed tracked as in the real tree ──
R="$W/repo"; mkdir -p "$R/lib" "$R/build" "$R/scripts" "$R/bootstrap"
cp "$ROOT/scripts/install.sh" "$ROOT/scripts/verify-store.sh" "$R/scripts/"
cp "$ROOT/bootstrap/asm" "$ROOT/bootstrap/asm.cyr" "$ROOT/bootstrap/cybs.cyr" "$R/bootstrap/"
chmod +x "$R/bootstrap/asm"
printf '9.9.9\n' > "$R/VERSION"
printf 'fn probe_lib(): i64 { return 1; }\n' > "$R/lib/probe.cyr"
printf 'tracked-compiler-bytes\n' > "$R/build/cycc"; chmod +x "$R/build/cycc"
printf '/build/*\n!/build/cycc\n' > "$R/.gitignore"
cat > "$R/cyrius.cyml" <<'EOF'
[package]
name = "mini"
version = "9.9.9"

[release]
bins = ["cycc", "cybs", "cyrfmt"]
cross_bins = []
scripts = []
EOF
( cd "$R" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm "9.9.9" && git tag 9.9.9 )
# cyrfmt has no programs/ source in the mini repo: axis 1 drops it from bins so the refresh
# reaches the copy, axis 2 is the refusal it now earns. (Edits are to cyrius.cyml in a COPY.)
_refresh() {  # _refresh <tree> <home> <tag> → rc echoed; output in $W/<tag>.out / .err
    rc=0
    ( cd "$1" && HOME="$W/userhome" CYRIUS_HOME="$2" sh scripts/install.sh --refresh-only \
        > "$W/$3.out" 2> "$W/$3.err" ) || rc=$?
    echo "$rc"
}
mkdir -p "$W/userhome"

# ── axis 1: tree == tag, a STALE build/cybs in the clone → the slot gets the assembled one ──
R1="$W/repo1"; git clone -q "$R" "$R1"
sed -i 's/^bins = .*/bins = ["cycc", "cybs"]/' "$R1/cyrius.cyml"
( cd "$R1" && git -c user.email=t@t -c user.name=t commit -qam "bins" && git tag -f 9.9.9 >/dev/null )
cp "$W/cybs.stale" "$R1/build/cybs"
rc=$(_refresh "$R1" "$W/home1" a1)
if [ "$rc" -eq 0 ] && cmp -s "$W/home1/versions/9.9.9/bin/cybs" "$W/cybs.expected" \
   && cmp -s "$R1/build/cybs" "$W/cybs.expected" && grep -q 'rebuilt cybs' "$W/a1.out" \
   && grep -q '^tree-matches-tag: yes' "$W/home1/versions/9.9.9/SOURCE_COMMIT"; then
    ok "a stale build/cybs never reaches the slot: bin/cybs is the seed-assembled bootstrap/cybs.cyr (stamp: tree-matches-tag yes)"
else bad "axis 1 (rc=$rc): slot cybs $(wc -c < "$W/home1/versions/9.9.9/bin/cybs" 2>/dev/null || echo none) B, expected $(wc -c < "$W/cybs.expected") B — $(head -2 "$W/a1.err" | tr '\n' ' ')"; fi

# ── axis 2: a listed bin with NO source → refused by name, nothing installed ────────────────
R2="$W/repo2"; git clone -q "$R" "$R2"
printf '#!/bin/sh\necho stale-cyrfmt\n' > "$R2/build/cyrfmt"; chmod +x "$R2/build/cyrfmt"
rc=$(_refresh "$R2" "$W/home2" a2)
if [ "$rc" -ne 0 ] && grep -q "cyrfmt" "$W/a2.err" && grep -q "programs/cyrfmt.cyr" "$W/a2.err" \
   && [ ! -e "$W/home2/versions/9.9.9/bin/cyrfmt" ]; then
    ok "a bin with no source (cyrfmt, no programs/cyrfmt.cyr): refused by name (rc=$rc), the planted build/cyrfmt not installed"
else bad "axis 2 (rc=$rc): $(head -2 "$W/a2.err" | tr '\n' ' ') / installed: $(ls "$W/home2/versions/9.9.9/bin" 2>/dev/null | tr '\n' ' ')"; fi

# ── axis 3: a cybs that fails the closure → refused, build/cybs removed, slot untouched ─────
R3="$W/repo3"; git clone -q "$R" "$R3"
sed -i 's/^bins = .*/bins = ["cycc", "cybs"]/' "$R3/cyrius.cyml"
printf 'var x = 7;\n' > "$R3/bootstrap/asm.cyr"   # cybs compiles it, to a 184 B ELF that is not the seed
( cd "$R3" && git -c user.email=t@t -c user.name=t commit -qam "broken closure" && git tag -f 9.9.9 >/dev/null )
mkdir -p "$W/home3/versions/9.9.9/bin"; printf 'previous\n' > "$W/home3/versions/9.9.9/bin/cybs"
rc=$(_refresh "$R3" "$W/home3" a3)
if [ "$rc" -ne 0 ] && grep -q "cybs" "$W/a3.err" && [ ! -e "$R3/build/cybs" ] \
   && [ "$(cat "$W/home3/versions/9.9.9/bin/cybs")" = previous ]; then
    ok "a cybs that does not compile bootstrap/asm.cyr to the seed: refused (rc=$rc), build/cybs removed, slot untouched"
else bad "axis 3 (rc=$rc): $(head -2 "$W/a3.err" | tr '\n' ' ')"; fi

# ── axis 4: verify-store rebuilds + compares cybs, checks the seed, names what it did not ───
H4="$W/home4"; S4="$H4/versions/9.9.9"; mkdir -p "$S4/lib" "$S4/bin"
cp "$R/lib/probe.cyr" "$S4/lib/probe.cyr"
cp "$R/build/cycc" "$S4/bin/cycc"
cp "$W/cybs.stale" "$S4/bin/cybs"                                   # not the tag's cybs
printf 'not-the-seed\n' > "$S4/bin/asm"                             # not the tag's bootstrap/asm
printf '#!/bin/sh\n' > "$S4/bin/cyrfmt"                             # untracked, unverifiable here
printf '%s\ntree-matches-tag: yes\n' "$(git -C "$R" rev-list -n1 9.9.9)" > "$S4/SOURCE_COMMIT"
rc=0; ( cd "$R" && CYRIUS_HOME="$H4" sh scripts/verify-store.sh > "$W/a4.out" 2>&1 ) || rc=$?
if [ "$rc" -ne 0 ] && grep -q 'DIFFERS   bin/cybs' "$W/a4.out" && grep -q 'DIFFERS   bin/asm' "$W/a4.out" \
   && grep -q '1 BAD' "$W/a4.out" && grep -q 'NOT verified.*cyrfmt' "$W/a4.out" \
   && ! grep -q 'NOT verified.* cybs' "$W/a4.out"; then
    ok "verify-store: a slot with a foreign cybs and seed is BAD, both named; the untracked cyrfmt is named as unverified"
else bad "axis 4 (rc=$rc): $(cat "$W/a4.out")"; fi
rc=0; ( cd "$R" && CYRIUS_HOME="$H4" sh scripts/verify-store.sh --restore 9.9.9 > "$W/a4r.out" 2>&1 ) || rc=$?
rc2=0; ( cd "$R" && CYRIUS_HOME="$H4" sh scripts/verify-store.sh > "$W/a4b.out" 2>&1 ) || rc2=$?
if [ "$rc" -eq 0 ] && cmp -s "$S4/bin/cybs" "$W/cybs.expected" && cmp -s "$S4/bin/asm" "$ROOT/bootstrap/asm" \
   && [ "$rc2" -eq 0 ] && grep -q '9.9.9    OK' "$W/a4b.out" && grep -q '0 BAD' "$W/a4b.out"; then
    ok "verify-store --restore: cybs re-assembled from the tag, the seed restored, the report is then clean"
else bad "axis 4r (rc=$rc, report rc=$rc2): $(tail -3 "$W/a4r.out" | tr '\n' ' ') / $(tail -2 "$W/a4b.out" | tr '\n' ' ')"; fi

# ── RS-03 (6.6.20): the dependency set is every include root of every bin, and the compiler ──
# programs/<bin> took "lib" only (cyrius-lsp includes cbt/srcscan.cyr, ark programs/nous_stub.cyr)
# and `cyrius` took "lib cbt" (cbt/cyrius.cyr includes src/version_str.cyr); build/cycc was no
# dependency at all. A tree carrying the real sources of those three bins, in its own `git init`
# (no commits, no tags — no enclosing repo is consulted; the override covers the reused slot).
# Times are SET, not slept on: sources + compiler at 2020, built bins at 2021, an edit at 2022.
L="$W/lsp"; mkdir -p "$L/build" "$L/scripts" "$L/programs" "$L/src"
cp "$ROOT/scripts/install.sh" "$L/scripts/"
cp -RL "$ROOT/lib" "$ROOT/cbt" "$L/"
cp "$ROOT/programs/cyrius-lsp.cyr" "$ROOT/programs/ark.cyr" "$ROOT/programs/nous_stub.cyr" "$L/programs/"
cp "$ROOT/src/version_str.cyr" "$L/src/"
cp "$CC" "$L/build/cycc"; chmod +x "$L/build/cycc"
printf '9.9.9\n' > "$L/VERSION"
printf '[release]\nbins = ["cycc", "cyrius", "cyrius-lsp", "ark"]\ncross_bins = []\nscripts = []\n' > "$L/cyrius.cyml"
( cd "$L" && git init -q )
HL="$W/homeL"; SL="$HL/versions/9.9.9/bin"
_lrefresh() {  # _lrefresh <tag> → rc echoed
    rc=0
    ( cd "$L" && HOME="$W/userhome" CYRIUS_HOME="$HL" CYRIUS_REFRESH_RELEASED=1 sh scripts/install.sh --refresh-only \
        > "$W/$1.out" 2> "$W/$1.err" ) || rc=$?
    echo "$rc"
}
_settle() {
    find "$L/lib" "$L/cbt" "$L/src" "$L/programs" -name '*.cyr' -exec touch -t 202001010000 {} +
    touch -t 202001010000 "$L/build/cycc"
    for b in cyrius cyrius-lsp ark; do touch -t 202101010000 "$L/build/$b"; done
}
_fresh() {  # _fresh <bin> <source> → $W/fresh.<bin>, compiled from the tree as install.sh does
    ( cd "$L" && ./build/cycc < "$2" > "$W/fresh.$1" 2>/dev/null )
}
# _edit_axis <name> <bin> <source> <file> <sed-expr> <what>
_edit_axis() {
    cp "$SL/$2" "$W/before.$2"
    cp "$L/$4" "$W/orig.edit"; sed -i "$5" "$L/$4"
    if cmp -s "$W/orig.edit" "$L/$4"; then bad "axis $1: the probe edit to $4 changed nothing — re-derive it"; return 0; fi
    touch -t 202201010000 "$L/$4"
    rc=$(_lrefresh "a$1"); _fresh "$2" "$3"
    if cmp -s "$W/fresh.$2" "$W/before.$2"; then bad "axis $1: the edit to $4 does not change $2's code — the axis would pass vacuously"
    elif [ "$rc" -eq 0 ] && grep -q "rebuilt $2 from $3" "$W/a$1.out" && cmp -s "$SL/$2" "$W/fresh.$2"; then
        ok "$6: $2 rebuilt and the installed binary == a fresh compile"
    else bad "axis $1 (rc=$rc): $2 not rebuilt / installed STALE vs a fresh compile — $(grep -h -m1 -E 'rebuilt|refus' "$W/a$1.out" "$W/a$1.err" | tr '\n' ' ')"; fi
    _settle
}
rc=$(_lrefresh a5)
if [ "$rc" -eq 0 ] && grep -q 'rebuilt cyrius-lsp' "$W/a5.out" && grep -q 'rebuilt ark' "$W/a5.out" && grep -q 'rebuilt cyrius from' "$W/a5.out"; then
    ok "first refresh of the dependency tree builds cyrius, cyrius-lsp and ark"
else bad "axis 5 (rc=$rc): $(head -3 "$W/a5.err" | tr '\n' ' ')"; fi
_settle
rc=$(_lrefresh a6)
if [ "$rc" -eq 0 ] && ! grep -qE 'rebuilt (cyrius|cyrius-lsp|ark) from' "$W/a6.out"; then
    ok "nothing newer than the bins: nothing is rebuilt (anti-vacuous — the union does not rebuild every time)"
else bad "axis 6 (rc=$rc): a no-op refresh rebuilt: $(grep -E 'rebuilt' "$W/a6.out" | tr '\n' ' ')"; fi
_edit_axis 7 cyrius-lsp programs/cyrius-lsp.cyr cbt/srcscan.cyr 's/"#io"/"#iq"/' "an edit to cbt/srcscan.cyr (included by programs/cyrius-lsp.cyr)"
_edit_axis 8 ark programs/ark.cyr programs/nous_stub.cyr '0,/return 0;/s//return 7;/' "an edit to programs/nous_stub.cyr (included by programs/ark.cyr)"
_edit_axis 9 cyrius cbt/cyrius.cyr src/version_str.cyr 's/^\(var _VERSION_TOOLCHAIN *= *\)"[^"]*"/\1"9.9.9-probe"/' "an edit to src/version_str.cyr (included by cbt/cyrius.cyr)"
touch -t 202201010000 "$L/build/cycc"
rc=$(_lrefresh a10)
if [ "$rc" -eq 0 ] && grep -q 'rebuilt cyrius-lsp' "$W/a10.out" && grep -q 'rebuilt ark' "$W/a10.out" && grep -q 'rebuilt cyrius from' "$W/a10.out"; then
    ok "a build/cycc newer than the bins rebuilds them (the compiler is a dependency)"
else bad "axis 10 (rc=$rc): $(grep -E 'rebuilt' "$W/a10.out" | tr '\n' ' ')"; fi

# ── axes 11-14 (6.6.20, RS-02 review): a cross-bin nothing rebuilt is refused, never copied ─
X="$W/cross"; mkdir -p "$X/build" "$X/scripts" "$X/src" "$X/lib"
printf 'fn probe_lib(): i64 { return 1; }\n' > "$X/lib/probe.cyr"
cp "$ROOT/scripts/install.sh" "$X/scripts/"
cp "$CC" "$X/build/cycc"; chmod +x "$X/build/cycc"
printf '9.9.9\n' > "$X/VERSION"
printf 'var x = 1;\n' > "$X/src/main_win.cyr"
printf '[release]\nbins = ["cycc"]\ncross_bins = ["cycc_win"]\nscripts = []\n' > "$X/cyrius.cyml"
( cd "$X" && git init -q )
HX="$W/homeX"; SX="$HX/versions/9.9.9/bin"
_xrefresh() {  # _xrefresh <tag> → rc echoed
    rc=0
    ( cd "$X" && HOME="$W/userhome" CYRIUS_HOME="$HX" CYRIUS_REFRESH_RELEASED=1 sh scripts/install.sh --refresh-only \
        > "$W/$1.out" 2> "$W/$1.err" ) || rc=$?
    echo "$rc"
}
rc=$(_xrefresh a11)
CYRIUS_TARGET_WIN=1 "$X/build/cycc" < "$X/src/main_win.cyr" > "$W/fresh.cycc_win" 2>/dev/null || true
if [ "$rc" -eq 0 ] && grep -q 'rebuilt cycc_win' "$W/a11.out" && [ -s "$W/fresh.cycc_win" ] \
   && cmp -s "$SX/cycc_win" "$W/fresh.cycc_win"; then
    ok "cross_bins cycc_win: rebuilt from src/main_win.cyr, installed == a fresh PE compile"
else bad "axis 11 (rc=$rc): $(head -2 "$W/a11.err" | tr '\n' ' ') / installed: $(ls "$SX" 2>/dev/null | tr '\n' ' ')"; fi
cp "$SX/cycc_win" "$W/slot.cycc_win" 2>/dev/null || printf 'none\n' > "$W/slot.cycc_win"
printf 'fn broken( {\n' > "$X/src/main_win.cyr"
rc=$(_xrefresh a12)
if [ "$rc" -ne 0 ] && grep -q 'cycc_win' "$W/a12.err" && grep -q 'refusing' "$W/a12.err" \
   && [ ! -e "$X/build/cycc_win" ] && cmp -s "$SX/cycc_win" "$W/slot.cycc_win"; then
    ok "a src/main_win.cyr that does not compile: refused by name (rc=$rc), build/cycc_win removed, the slot keeps its cycc_win"
else bad "axis 12 (rc=$rc): $(grep -h -m2 -E 'cycc_win|refus' "$W/a12.out" "$W/a12.err" | tr '\n' ' ') / build/cycc_win: $([ -e "$X/build/cycc_win" ] && echo present || echo absent)"; fi
rm -f "$X/src/main_win.cyr"
printf '#!/bin/sh\necho stale-cycc_win\n' > "$X/build/cycc_win"; chmod +x "$X/build/cycc_win"
rc=$(_xrefresh a13)
if [ "$rc" -ne 0 ] && grep -q 'src/main_win.cyr' "$W/a13.err" && grep -q 'refusing' "$W/a13.err" \
   && cmp -s "$SX/cycc_win" "$W/slot.cycc_win"; then
    ok "no src/main_win.cyr, a stale build/cycc_win planted: refused naming the source (rc=$rc), the slot untouched"
else bad "axis 13 (rc=$rc): $(head -2 "$W/a13.err" | tr '\n' ' ') / slot cycc_win: $(head -c 40 "$SX/cycc_win" 2>/dev/null | tr -c '[:print:]' '.')"; fi
printf '[release]\nbins = ["cycc"]\ncross_bins = ["cycc_mystery"]\nscripts = []\n' > "$X/cyrius.cyml"
printf '#!/bin/sh\necho stale-mystery\n' > "$X/build/cycc_mystery"; chmod +x "$X/build/cycc_mystery"
rc=$(_xrefresh a14)
if [ "$rc" -ne 0 ] && grep -q 'cycc_mystery' "$W/a14.err" && grep -q 'no rebuild rule' "$W/a14.err" \
   && [ ! -e "$SX/cycc_mystery" ]; then
    ok "a cross_bins entry with no rebuild rule: refused by name (rc=$rc), the planted build/cycc_mystery never installed"
else bad "axis 14 (rc=$rc): $(head -2 "$W/a14.err" | tr '\n' ' ') / installed: $(ls "$SX" 2>/dev/null | tr '\n' ' ')"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
