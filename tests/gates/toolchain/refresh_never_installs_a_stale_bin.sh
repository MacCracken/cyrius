#!/bin/sh
# refresh_never_installs_a_stale_bin.sh — `install.sh --refresh-only` rebuilds every bin it
# installs (or refuses), and verify-store judges the one untracked bin it can rebuild.
#
# 6.6.20 (RS-02). `cybs` — the bootstrap compiler, the root of the seed → cybs → cycc chain —
# is listed in cyrius.cyml `bins` but has no programs/cybs.cyr. `_rebuild_stale` returned 0 for
# a missing source, and the copy loop then installed whatever gitignored build/cybs the clone
# held: a 12,344 B June binary that prints `syntax error` on src/main.cyr, in 17 slots
# (6.6.3–6.6.9, 6.6.11–6.6.20), each stamped `tree-matches-tag: yes`. verify-store judged only
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
# Mutation ledger (MEASURED in a scratch ROOT at 6.6.20 — re-run, don't trust):
#   install.sh + verify-store.sh as they were at 6.6.19              → axes 1 2 3 4 4r red
#   the `cybs) _rebuild_cybs` arm made a no-op                       → axes 1 3 red
#   `[ -f "$source" ] || return 0` restored in _rebuild_stale         → axis 2 red
#   the closure `cmp` dropped from _rebuild_cybs                      → axis 3 red
#   verify_slot never judges cybs                                     → axis 4 red
#   restore_slot never re-assembles cybs                              → axis 4r red
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
G=refresh_never_installs_a_stale_bin
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

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
