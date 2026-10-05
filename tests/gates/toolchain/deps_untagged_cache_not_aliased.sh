#!/bin/sh
# deps_untagged_cache_not_aliased.sh — 6.6.17. An untagged git dep and a `tag = "main"` dep of
# the same name never share one dep-cache entry.
#
# THE DEFECT: the untagged clone (the remote's default branch) lived at `<home>/deps/<name>/main`,
# the dir a `tag = "main"` dep resolves to, and an existing dir is reused without a clone.
# Measured on the 6.6.17 slot-open CLI with an origin whose default branch is `master` and whose
# `main` branch differs: tagged first, the untagged project vendored `main`'s bytes, exit 0;
# untagged first, the tagged project was refused as a "tampered cache".
#
# THE FIX: the untagged key is `<home>/deps/<name>/.untagged`. A `.`-led component is refused in
# every tag by CVE-76's validator, so no tag can name it.
#
# AXES
#   1. tag = "main" first, then untagged: each project vendors its own ref's bytes (expected
#      bytes from `git show <ref>:dist/foo.cyr` on the origin).
#   2. Fresh cache, untagged first, then tag = "main": the tagged dep resolves (no refusal).
#   3. The two cache entries are distinct dirs: `<name>/main` and `<name>/.untagged`.
#   4. `tag = ".untagged"` is refused by name, so a tag cannot reach the untagged key.
# Old code: axes 1, 2 and 3 FAIL.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=deps_untagged_cache_not_aliased
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "SKIP: $G: git not found"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
FAIL=0
fail() { echo "FAIL: $G: $*"; FAIL=1; }
ulimit -c 0 2>/dev/null

"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/cli.err" && [ -s "$W/cyrius" ] \
  || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
chmod +x "$W/cyrius"
V=$(tr -d '[:space:]' < VERSION)
H="$W/home"
mkdir -p "$H/versions/$V" "$H/deps" && cp -r lib "$H/versions/$V/lib" && printf '%s\n' "$V" > "$H/current" \
  || { echo "FAIL: $G: cannot stage the throwaway home"; exit 1; }
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_ALLOW_PROTOCOL=file
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = master\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"

# The origin: default branch `master`, and a `main` branch with different bytes.
O="$W/o/foo"; mkdir -p "$O/dist"
( cd "$O" && git init -q . \
  && printf 'fn foo_v(): i64 { return 1; }\n' > dist/foo.cyr && git add -A && git commit -qm m \
  && git checkout -qb main && printf 'fn foo_v(): i64 { return 2; }\n' > dist/foo.cyr && git commit -qam b \
  && git checkout -q master ) || { echo "FAIL: $G: cannot build the origin"; exit 1; }
git -C "$O" show master:dist/foo.cyr > "$W/default.expect"
git -C "$O" show main:dist/foo.cyr > "$W/main.expect"
[ "$(git -C "$O" symbolic-ref --short HEAD)" = master ] && [ -s "$W/main.expect" ] && ! cmp -s "$W/default.expect" "$W/main.expect" \
  || { echo "FAIL: $G: origin fixture wrong (default branch not master, or main not distinct)"; exit 1; }

mkp() {   # $1 = project dir, $2 = the tag line ("" for untagged)
    rm -rf "$1"; mkdir -p "$1/src"
    printf '[package]\nname = "p"\nversion = "0.0.1"\ncyrius = "%s"\n\n[deps.foo]\ngit = "file://%s"\n%bmodules = ["dist/foo.cyr"]\n' "$V" "$O" "$2" > "$1/cyrius.cyml"
    printf 'fn main(): i64 { return 0; }\n' > "$1/src/main.cyr"
}
_cy() { _d=$1; shift; ( cd "$_d" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$W/cyrius" "$@" ); }
TAGGED="$W/pt"; UNTAGGED="$W/pu"

# ── axis 1: tagged first, then untagged ────────────────────────────────────────────────
x=0
mkp "$TAGGED" 'tag = "main"\n'; mkp "$UNTAGGED" ''
rc=0; _cy "$TAGGED" deps > "$W/a1t.out" 2>&1 || rc=$?
{ [ "$rc" -eq 0 ] && cmp -s "$TAGGED/lib/foo.cyr" "$W/main.expect"; } \
  || { fail "axis 1: the tag = \"main\" dep did not vendor main's bytes (rc=$rc):"; tail -3 "$W/a1t.out" | sed 's/^/      /'; x=1; }
rc=0; _cy "$UNTAGGED" deps > "$W/a1u.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then fail "axis 1: the untagged dep failed after the tagged one (rc=$rc):"; tail -3 "$W/a1u.out" | sed 's/^/      /'; x=1
elif cmp -s "$UNTAGGED/lib/foo.cyr" "$W/main.expect"; then fail "axis 1: the untagged dep vendored the main BRANCH's bytes (the tagged dep's cache), not the default branch's"; x=1
elif ! cmp -s "$UNTAGGED/lib/foo.cyr" "$W/default.expect"; then fail "axis 1: the untagged dep's lib/foo.cyr is not the default branch's bytes"; x=1; fi
[ "$x" = 0 ] && echo "  ok: axis 1: tagged first — each dep vendors its own ref"

# ── axis 3: two distinct cache entries ─────────────────────────────────────────────────
x=0
[ -d "$H/deps/foo/main/.git" ] || { fail "axis 3: no clone at <home>/deps/foo/main for the tagged dep"; x=1; }
[ -d "$H/deps/foo/.untagged/.git" ] || { fail "axis 3: no clone at <home>/deps/foo/.untagged for the untagged dep"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 3: <name>/main and <name>/.untagged are separate clones"

# ── axis 2: fresh cache, untagged first, then tagged ───────────────────────────────────
x=0
rm -rf "$H/deps/foo"; mkp "$TAGGED" 'tag = "main"\n'; mkp "$UNTAGGED" ''
rc=0; _cy "$UNTAGGED" deps > "$W/a2u.out" 2>&1 || rc=$?
{ [ "$rc" -eq 0 ] && cmp -s "$UNTAGGED/lib/foo.cyr" "$W/default.expect"; } \
  || { fail "axis 2: the untagged dep did not vendor the default branch (rc=$rc)"; x=1; }
rc=0; _cy "$TAGGED" deps > "$W/a2t.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then fail "axis 2: the tag = \"main\" dep failed after the untagged one (rc=$rc):"; grep -m2 -E 'error|refusing' "$W/a2t.out" | sed 's/^/      /'; x=1
elif ! cmp -s "$TAGGED/lib/foo.cyr" "$W/main.expect"; then fail "axis 2: the tag = \"main\" dep did not vendor main's bytes"; x=1; fi
[ "$x" = 0 ] && echo "  ok: axis 2: untagged first — the tagged dep still resolves"

# ── axis 4: no tag can name the untagged key ───────────────────────────────────────────
x=0
P4="$W/p4"; mkp "$P4" 'tag = ".untagged"\n'
rc=0; _cy "$P4" deps > "$W/a4.out" 2>&1 || rc=$?
{ [ "$rc" -ne 0 ] && grep -q 'not a usable tag' "$W/a4.out"; } \
  || { fail "axis 4: tag = \".untagged\" was not refused (rc=$rc)"; x=1; }
[ -f "$P4/lib/foo.cyr" ] && { fail "axis 4: tag = \".untagged\" vendored lib/foo.cyr"; x=1; }
[ "$x" = 0 ] && echo "  ok: axis 4: tag = \".untagged\" is refused by name"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: $G"
exit 0
