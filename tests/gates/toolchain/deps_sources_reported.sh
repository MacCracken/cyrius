#!/bin/sh
# deps_sources_reported.sh — 6.7.6 (lane C, parts L and R7). `cyrius deps` SAYS WHERE EACH DEPENDENCY
# CAME FROM, by the resolver's own rule:
#   * `deps -v` after a resolve, one line per dep:   sib   tag v1 @1a2b3c4 (fetched)
#                                                    leaf  tag v1 @9f8e7d6 (cache) via p1
#                                                    sib   local ../sib @…, 1 commit past v1
#   * `deps --dry-run`, writing NOTHING (no clone, no lib/, no lock), one line per dep — the
#     transitive ones too as far as a local checkout or the cache can show them — and failing
#     exactly where the real run fails (the same refusal lines);
#   * R7: a DIAMOND — a dep already resolved, wanted again at another tag — is one line,
#     `note: leaf v2 (wanted by p2) not used; v1 (p1) resolved first`. Closest-wins still decides;
#     before 6.7.6 it decided in silence.
# Before 6.7.6 the dry run printed the bare [deps.NAME] headers and nothing said which source a
# dep was built from — the one fact a developer needed once `path` and `tag` could disagree.
#
# AXES (file:// origins, a throwaway CYRIUS_HOME):
#   S1  `deps --dry-run` on a fresh cache: each root dep `tag v1 from file://… (not fetched: …)`,
#       rc 0, and NOTHING written — no lib/, no lock, no clone in the cache
#   S2  `deps -v`: a `dependency sources:` block, `tag v1 @<sha7> (fetched)` for the root deps and
#       `… via p1` for the transitive one; the sha is the tag's
#   S3  the dry run after the resolve: cached tags carry `(cached @<sha7>)` and the transitive dep
#       shows `via p1`, read out of the cache
#   S4  R7: p1 wants leaf v1, p2 wants leaf v2 — exactly one note, as designed; leaf resolved at v1
#   S5  anti-over-reach: two deps wanting the SAME tag of leaf print no note
#   S6  local mode: the dry run says `local ../sib @<sha7>, 1 commit past v1 — CI builds v1` and
#       names build/local-deps/lib/ as the destination; -v says `local ../sib …`
#   S7  the dry run fails where the real run fails: a cached tag dep whose manifest names a
#       path-only entry — the SAME refusal line from both, rc 1 each
#   S8  only an entry this run would resolve can be "wanted": p4's leaf v2 is `optional` with no
#       active feature and p5's leaf v2 is `target = "aarch64"` (an x86_64 build) — no note for
#       either, leaf resolved at p1's v1 (both were called "wanted by p4 / p5")
#
# MUTATION LEDGER (measured 2026-10-08, each in a SCRATCH copy of the tree, one at a time; real
# tree 8/8 green):
#   M1  no `_dep_diamond` call at the closest-wins skip ............... S4 red
#   M2  `_dep_diamond` reports equal tags too ......................... S5 red
#   M3  the dry run ignores the source rule (always the git line) ..... S6 S7 red
#   M4  the dry run does not walk the cache (no transitive lines) ..... S3 S7 red
#   M5  `deps -v` prints no sources ................................... S2 S6 red
#   M6  the diamond notice ignores the optional / target gates (6.7.6 FXCL-7) .. S8 red
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=deps_sources_reported
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
mkorigin() {   # $1 name, $2 return value, $3 optional cyrius.cyml body (printf %b)
    _o="$W/o/$1"; mkdir -p "$_o/dist"
    printf 'fn %s_v(): i64 { return %s; }\n' "$1" "$2" > "$_o/dist/$1.cyr"
    [ -n "$3" ] && printf '%b' "$3" > "$_o/cyrius.cyml"
    ( cd "$_o" && git init -q . && git add -A && git commit -qm v1 && git tag v1 ) || { echo "FAIL: $G: cannot build origin $1"; exit 1; }
}
mkorigin leaf 10
( cd "$W/o/leaf" && printf 'fn leaf_v(): i64 { return 20; }\n' > dist/leaf.cyr && git commit -qam v2 && git tag v2 )
mkorigin p1 1 "[package]\nname = \"p1\"\n\n[deps.leaf]\ngit = \"file://$W/o/leaf\"\ntag = \"v1\"\nmodules = [\"dist/leaf.cyr\"]\n"
mkorigin p2 2 "[package]\nname = \"p2\"\n\n[deps.leaf]\ngit = \"file://$W/o/leaf\"\ntag = \"v2\"\nmodules = [\"dist/leaf.cyr\"]\n"
mkorigin p3 3 "[package]\nname = \"p3\"\n\n[deps.leaf]\ngit = \"file://$W/o/leaf\"\ntag = \"v1\"\nmodules = [\"dist/leaf.cyr\"]\n"
mkorigin bad 4 "[package]\nname = \"bad\"\n\n[deps.leaf]\npath = \"../leaf\"\nmodules = [\"dist/leaf.cyr\"]\n"
mkorigin p4 4 "[package]\nname = \"p4\"\n\n[deps.leaf]\ngit = \"file://$W/o/leaf\"\ntag = \"v2\"\nmodules = [\"dist/leaf.cyr\"]\noptional = true\n"
mkorigin p5 5 "[package]\nname = \"p5\"\n\n[deps.leaf]\ngit = \"file://$W/o/leaf\"\ntag = \"v2\"\nmodules = [\"dist/leaf.cyr\"]\ntarget = \"aarch64\"\n"
mkorigin sib 1
mkdir -p "$W/ws" && git clone -q "$W/o/sib" "$W/ws/sib" && ( cd "$W/ws/sib" && printf 'fn sib_v(): i64 { return 2; }\n' > dist/sib.cyr && git commit -qam dev )
sha7() { git -C "$W/o/$1" rev-parse --short=7 "$2^{commit}"; }
LCL=""
cy() { ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 CYRIUS_LOCAL="$LCL" exec "$CY" "$@" ); }
mkp() { P="$W/ws/$1"; rm -rf "$P"; mkdir -p "$P"; { printf '[package]\nname = "%s"\nversion = "0.1.0"\ncyrius = "%s"\n\n' "$1" "$V"; cat; } > "$P/cyrius.cyml"; }
deps2() { # $1 first, $2 second
    printf '[deps.%s]\ngit = "file://%s/o/%s"\ntag = "v1"\nmodules = ["dist/%s.cyr"]\n\n[deps.%s]\ngit = "file://%s/o/%s"\ntag = "v1"\nmodules = ["dist/%s.cyr"]\n' "$1" "$W" "$1" "$1" "$2" "$W" "$2" "$2"
}
# ── S1 ──
deps2 p1 p2 > "$W/d12"; mkp app < "$W/d12"   # not a pipe: mkp sets $P
rc=0; cy deps --dry-run > "$W/s1.out" 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && grep -qxF "  p1  tag v1 from file://$W/o/p1 (not fetched: its own dependencies are listed once it is)" "$W/s1.out" \
   && grep -qxF "  p2  tag v1 from file://$W/o/p2 (not fetched: its own dependencies are listed once it is)" "$W/s1.out" \
   && [ ! -e "$P/lib" ] && [ ! -e "$P/cyrius.lock" ] && [ -z "$(ls -A "$H/deps")" ]; then
    ok "S1 dry run on a fresh cache: one line per dep with its tag and origin, nothing written, nothing cloned"
else bad "S1 (rc=$rc deps=[$(ls -A "$H/deps" | tr '\n' ' ')]): $(cat "$W/s1.out" | tr '\n' '|')"; fi
# ── S2 + S4 ──
rc=0; cy -v deps > "$W/s2.out" 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && grep -q '^dependency sources:$' "$W/s2.out" \
   && grep -qxF "  p1    tag v1 @$(sha7 p1 v1) (fetched)" "$W/s2.out" \
   && grep -qxF "  p2    tag v1 @$(sha7 p2 v1) (fetched)" "$W/s2.out" \
   && grep -qxF "  leaf  tag v1 @$(sha7 leaf v1) (fetched) via p1" "$W/s2.out"; then
    ok "S2 deps -v: each dep's tag and commit, fetched or cached, and the transitive one via p1"
else bad "S2 (rc=$rc): $(sed -n '/dependency sources/,+4p' "$W/s2.out" | tr '\n' '|')"; fi
nn=$(grep -c '^note: ' "$W/s2.out")
if [ "$nn" -eq 1 ] && grep -qxF 'note: leaf v2 (wanted by p2) not used; v1 (p1) resolved first' "$W/s2.out" \
   && grep -q 'return 10;' "$P/lib/leaf.cyr"; then
    ok "S4 a diamond (p1 wants leaf v1, p2 leaf v2): one note — 'leaf v2 (wanted by p2) not used; v1 (p1) resolved first' — and leaf is v1"
else bad "S4 ($nn notes): $(grep 'note' "$W/s2.out" | tr '\n' '|') leaf=[$(cat "$P/lib/leaf.cyr" 2>/dev/null)]"; fi
# ── S3 ──
rc=0; cy deps --dry-run > "$W/s3.out" 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && grep -qxF "  p1  tag v1 from file://$W/o/p1 (cached @$(sha7 p1 v1))" "$W/s3.out" \
   && grep -qxF "  leaf  tag v1 from file://$W/o/leaf (cached @$(sha7 leaf v1)) via p1" "$W/s3.out"; then
    ok "S3 dry run after the resolve: cached tags carry their commit, and the transitive dep shows via p1"
else bad "S3 (rc=$rc): $(cat "$W/s3.out" | tr '\n' '|')"; fi
# ── S5 ──
deps2 p1 p3 > "$W/d13"; mkp app5 < "$W/d13"
rc=0; cy deps > "$W/s5.out" 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^note: ' "$W/s5.out"; then ok "S5 two deps wanting the same tag of leaf: no note"
else bad "S5 (rc=$rc): $(grep note "$W/s5.out")"; fi
# ── S6 ──
mkp app6 <<EOF
[deps.sib]
git = "file://$W/o/sib"
tag = "v1"
path = "../sib"
modules = ["dist/sib.cyr"]
EOF
LCL=1; rc=0; cy deps --dry-run > "$W/s6a.out" 2>&1 || rc=$?; r6a=$rc
rc=0; cy -v deps > "$W/s6b.out" 2>&1 || rc=$?; LCL=""
if [ "$r6a" -eq 0 ] && grep -q '^dry-run: would resolve deps from cyrius.cyml into build/local-deps/lib/ (local mode' "$W/s6a.out" \
   && grep -q '^  sib  local \.\./sib @[0-9a-f]\{7\}, 1 commit past v1 — CI builds v1$' "$W/s6a.out" \
   && [ "$rc" -eq 0 ] && grep -q '^  sib  local \.\./sib @[0-9a-f]\{7\}, 1 commit past v1$' "$W/s6b.out" && [ ! -e "$P/lib" ]; then
    ok "S6 local mode: the dry run names the checkout and build/local-deps/lib/; -v says local ../sib"
else bad "S6 (dry rc=$r6a -v rc=$rc): $(cat "$W/s6a.out" | tr '\n' '|') -v: $(grep '^  sib' "$W/s6b.out")"; fi
# ── S7 ──
mkp app7 <<EOF
[deps.bad]
git = "file://$W/o/bad"
tag = "v1"
modules = ["dist/bad.cyr"]
EOF
rc=0; cy deps > "$W/s7r.out" 2>&1 || rc=$?; r7r=$rc
rc=0; cy deps --dry-run > "$W/s7d.out" 2>&1 || rc=$?
want="error: bad's manifest names [deps.leaf] path = \"../leaf\" with no git / tag — a published dependency must name git + tag; refused (it resolves on its author's box and nowhere else)"
if [ "$r7r" -eq 1 ] && [ "$rc" -eq 1 ] && grep -qxF "$want" "$W/s7r.out" && grep -qxF "$want" "$W/s7d.out"; then
    ok "S7 the dry run fails where the real run fails: the same refusal line for a cached dep's path-only entry, rc 1 each"
else bad "S7 (real rc=$r7r dry rc=$rc): $(grep -m1 error "$W/s7r.out") / $(grep -m1 error "$W/s7d.out")"; fi
# ── S8 ──
{ deps2 p1 p4; printf '\n[deps.p5]\ngit = "file://%s/o/p5"\ntag = "v1"\nmodules = ["dist/p5.cyr"]\n' "$W"; } > "$W/d18"; mkp app8 < "$W/d18"
rc=0; cy -v deps > "$W/s8.out" 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^note: ' "$W/s8.out" && grep -q 'return 10;' "$P/lib/leaf.cyr"; then
    ok "S8 a gated-out entry (optional with no feature, another target) wants nothing: no note, leaf at v1"
else bad "S8 (rc=$rc): $(grep note "$W/s8.out" | tr '\n' '|') leaf=[$(cat "$P/lib/leaf.cyr" 2>/dev/null)]"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
