#!/bin/sh
# deps_update_refetches_untagged.sh — 6.7.6 (lane C, R8). `cyrius update` does what its help always
# said ("re-resolve all deps to latest tags") within the rule that the committed manifest means what
# it says: an UNTAGGED dep's clone — which floats by design, and which the cache froze at its first
# fetch — is RE-FETCHED; each root dep's NEWER version tags are LISTED, newest first; the manifest
# re-resolves (lib/ + cyrius.lock); and cyrius.cyml is NEVER edited (moving a tag is its author's
# decision). Before 6.7.6 `update` touched no [deps.NAME] at all, so an untagged dep stayed at the
# commit of its first fetch on that machine for good.
#
# AXES (file:// origins, a throwaway CYRIUS_HOME):
#   D1  the untagged origin moves: a plain `cyrius deps` keeps the frozen clone (lib/fl.cyr = 1)
#   D2  `cyrius update` re-fetches it, says so, and vendors the new bytes (lib/fl.cyr = 2)
#   D3  the tagged dep: its newer VERSION tags newest first (1.10.0, 1.9.0, 1.3.0 — ls-remote lists 1.10.0, 1.3.0, 1.9.0) — not the older v0.9,
#       not the pre-release 2.0.0-beta, not the pinned 1.2.0 — and "cyrius.cyml is not edited"
#   D4  cyrius.cyml byte-identical; the tagged dep's lib/ copy is still its tag's (1)
#   D5  the lock the update wrote verifies (`deps --verify`: 0 failed)
#   D6  a tag that is not a version number: said, not compared
#
# MUTATION LEDGER (measured 2026-10-08, each in a SCRATCH copy of the tree, one at a time; real
# tree 6/6 green):
#   M1  update leaves the untagged clone in place .................... D2 red
#   M2  the newer-tag list keeps pre-releases ......................... D3 red
#   M3  the newer-tag list is not ordered (ls-remote order) ........... D3 red
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=deps_update_refetches_untagged
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "SKIP: $G: git not found"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
unset CYRIUS_LOCAL CYRIUS_LOCKED CYRIUS_LIB_OVERLAY
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
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
mkdir -p "$W/o/fl/dist" "$W/o/tg/dist" "$W/o/nm/dist"
printf 'fn fl_v(): i64 { return 1; }\n' > "$W/o/fl/dist/fl.cyr"
printf 'fn tg_v(): i64 { return 1; }\n' > "$W/o/tg/dist/tg.cyr"
printf 'fn nm_v(): i64 { return 1; }\n' > "$W/o/nm/dist/nm.cyr"
( cd "$W/o/fl" && git init -q . && git add -A && git commit -qm one ) \
 && ( cd "$W/o/tg" && git init -q . && git add -A && git commit -qm one && git tag 1.2.0 && git tag v0.9 ) \
 && ( cd "$W/o/nm" && git init -q . && git add -A && git commit -qm one && git tag stable ) || { echo "FAIL: $G: origins"; exit 1; }
P="$W/p"; mkdir -p "$P"
cat > "$P/cyrius.cyml" <<EOF
[package]
name = "p"
version = "0.1.0"
cyrius = "$V"

[deps.fl]
git = "file://$W/o/fl"
modules = ["dist/fl.cyr"]

[deps.tg]
git = "file://$W/o/tg"
tag = "1.2.0"
modules = ["dist/tg.cyr"]

[deps.nm]
git = "file://$W/o/nm"
tag = "stable"
modules = ["dist/nm.cyr"]
EOF
cp "$P/cyrius.cyml" "$W/cyml0"
cy() { ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$CY" "$@" ); }
rc=0; cy deps > "$W/setup.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && grep -q 'return 1;' "$P/lib/fl.cyr" || { echo "FAIL: $G: setup (rc=$rc): $(tail -2 "$W/setup.out")"; exit 1; }
( cd "$W/o/fl" && printf 'fn fl_v(): i64 { return 2; }\n' > dist/fl.cyr && git commit -qam two )
( cd "$W/o/tg" && printf 'fn tg_v(): i64 { return 3; }\n' > dist/tg.cyr && git commit -qam three && git tag 1.3.0 && git tag 1.10.0 && git tag 1.9.0 && git tag 2.0.0-beta )
# ── D1 ──
rc=0; cy deps > "$W/d1.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && grep -q 'return 1;' "$P/lib/fl.cyr" && ok "D1 a plain deps keeps the frozen untagged clone (lib/fl.cyr is the first fetch)" || bad "D1 (rc=$rc): $(cat "$P/lib/fl.cyr")"
# ── D2..D4 ──
rc=0; cy update > "$W/u.out" 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && grep -qxF "  fl: untagged — re-fetching file://$W/o/fl" "$W/u.out" && grep -q 'return 2;' "$P/lib/fl.cyr"; then
    ok "D2 cyrius update re-fetches the untagged clone and vendors its new bytes"
else bad "D2 (rc=$rc): $(grep -m2 'fl\|error' "$W/u.out") lib=[$(cat "$P/lib/fl.cyr")]"; fi
if grep -qxF '    tg: 1.2.0 pinned; newer tags: 1.10.0, 1.9.0, 1.3.0 (cyrius.cyml is not edited)' "$W/u.out"; then
    ok "D3 the tagged dep's newer version tags, newest first, without the older or pre-release ones"
else bad "D3: $(grep 'tg:' "$W/u.out")"; fi
if cmp -s "$P/cyrius.cyml" "$W/cyml0" && grep -q 'return 1;' "$P/lib/tg.cyr"; then ok "D4 cyrius.cyml byte-identical; tg still its tag's bytes"
else bad "D4: cyml $(cmp "$P/cyrius.cyml" "$W/cyml0" 2>&1 | head -1); tg=[$(cat "$P/lib/tg.cyr")]"; fi
# ── D5 ──
rc=0; cy deps --verify > "$W/d5.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && grep -q ' 0 failed$' "$W/d5.out" && ok "D5 the lock the update wrote verifies ($(tail -1 "$W/d5.out"))" || bad "D5 (rc=$rc): $(tail -2 "$W/d5.out")"
# ── D6 ──
grep -qxF '    nm: stable pinned (not a version number: newer tags are not compared)' "$W/u.out" \
  && ok "D6 a tag that is not a version number: said, not compared" || bad "D6: $(grep 'nm:' "$W/u.out")"

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
