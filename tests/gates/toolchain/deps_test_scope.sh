#!/bin/sh
# deps_test_scope.sh — 6.7.6 (Break 1, lane C, part T). `[deps.NAME] scope = "test"`: a dependency
# the project's tests need and its production code does not — a mock peer, a fixture library.
# EVERY resolve vendors it into lib/ and pins it in cyrius.lock (lib/ and the lock are one function
# of the manifest, whichever verb resolved); only test / bench / fuzz compiles prepend it. It is
# resolved AFTER every production dependency, so a name both sides reach is the production one. A
# DEPENDENCY's own `scope = "test"` entries are its own test business: never walked by a consumer.
#
# AXES (every origin a local file:// repo; a throwaway CYRIUS_HOME; no network):
#   D1  `cyrius deps -v`: the test dep is cloned, vendored (lib/mockpeer.cyr), commit-pinned in
#       cyrius.lock, and listed `[test scope]`
#   D2  `cyrius test`: a test calling mock_v() with no include of its own passes
#   D3  `cyrius build` of a source calling mock_v(): undefined — the production compile never
#       sees it; the project's own entry builds
#   D4  lib/ and cyrius.lock are byte-identical whether `cyrius build` or `cyrius test` resolved
#   D5  a production dependency's own `scope = "test"` entry (a path that does not exist, a git
#       that does not exist) is never walked: no error, nothing vendored
#   D6  `scope = "dev"` is refused by name, `scope = 1` as not a TOML string; both rc 1
#   D7  `deps --dry-run` marks the test dep `[test scope]` and lists no dependency's test dep
#   D8  additive: the same manifest without `scope` resolves the same files, no `[test scope]`,
#       and `scope` is never warned as an unknown key
#   D9  `deps --locked` holds the test dep to the lock too: lib/mockpeer.cyr removed is named
#   D10 a name both sides reach — the root's test-scope leaf@v2, a production dep's own leaf@v1 —
#       resolves the production v1, and the diamond notice names the v2 that was not used
#   D11 the test-scope pass walks the root manifest a second time: an unsafe `[deps.a..b]` and an
#       unclosed `[deps.zz` header are each refused ONCE, and the root manifest counts once in the
#       summary (`1 errors` — a pass's count is clamped to 1 since v6.5.37 — not 2)
#
# MUTATION LEDGER (6.7.6) — each mutant built in a SCRATCH copy of the tree, the gate run against
# it; the unmutated copy PASSES, and each mutant turns the rows named RED:
#   M1  deps.cyr: a dependency's own scope = "test" entries are walked (lane C's rule then
#       refuses prod's path-only test dep: every consumer of prod breaks)   D1 D2 D3 D4 D5 D8 D9 D10
#   M2  deps.cyr: phase 4 resolves the test deps with _dep_includes NOT swapped     D3
#   M3  deps.cyr: the production pass does not skip the test deps (resolved first,
#       pushed onto _dep_includes)                                                D1 D3 D10
#   M4  manifest.cyr: _tc_incs_for drops _dep_test_includes                        D2
#   M5  deps.cyr: a scope value other than "test" read as no scope                 D6
#   M6  deps.cyr: the dry run walks a dependency's own test deps                   D7
#   M7  deps.cyr: the test-scope pass refuses the root's headers again (6.7.6 FXCL-5)  D11
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=deps_test_scope
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "SKIP: $G: git not found"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
unset CYRIUS_LOCAL CYRIUS_LOCKED CYRIUS_LIB_OVERLAY CYRIUS_DEFINES
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/cli.err" && [ -s "$W/cyrius" ] \
  || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
V=$(tr -d '[:space:]' < VERSION)
H="$W/home"
mkdir -p "$H/versions/$V/bin" && cp -r lib "$H/versions/$V/lib" \
  && cp "$W/cyrius" "$H/versions/$V/bin/cyrius" && cp "$CC" "$H/versions/$V/bin/cycc" \
  && chmod +x "$H/versions/$V/bin/cyrius" "$H/versions/$V/bin/cycc" && printf '%s\n' "$V" > "$H/current" \
  || { echo "FAIL: $G: cannot stage the throwaway home"; exit 1; }
CY="$H/versions/$V/bin/cyrius"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_ALLOW_PROTOCOL=file
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"
TAB=$(printf '\t')

# origin <name> <fn body> [<cyrius.cyml body>] — a tagged v1 repo shipping dist/<name>.cyr
origin() {
    _o="$W/o/$1"; mkdir -p "$_o/dist"
    printf '%b\n' "$2" > "$_o/dist/$1.cyr"
    [ -n "${3:-}" ] && printf '%b' "$3" > "$_o/cyrius.cyml"
    ( cd "$_o" && git init -q . && git add -A && git commit -qm v1 && git tag v1 ) || { echo "FAIL: $G: cannot build origin $1"; exit 1; }
}
origin mockpeer 'fn mock_v(): i64 { return 7; }'
origin leaf 'fn leaf_v(): i64 { return 1; }'
( cd "$W/o/leaf" && printf 'fn leaf_v(): i64 { return 2; }\n' > dist/leaf.cyr && git commit -qam v2 && git tag v2 ) || { echo "FAIL: $G: leaf v2"; exit 1; }
# a production dependency whose OWN manifest declares test deps that do not exist anywhere
origin prod 'fn prod_v(): i64 { return 3; }' "[package]\nname = \"prod\"\n\n[deps.leaf]\ngit = \"file://$W/o/leaf\"\ntag = \"v1\"\nmodules = [\"dist/leaf.cyr\"]\n\n[deps.ghost]\npath = \"../nowhere\"\nmodules = [\"x.cyr\"]\nscope = \"test\"\n\n[deps.phantom]\ngit = \"file://$W/o/no-such-repo\"\ntag = \"v9\"\nmodules = [\"dist/phantom.cyr\"]\nscope = \"test\"\n"

cy() { ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$CY" "$@" ); }
# mkp <name> <scope line or ""> — a project with a production dep (prod) and mockpeer
mkp() {
    P="$W/$1"; rm -rf "$P"; mkdir -p "$P/src" "$P/tests"
    cat > "$P/cyrius.cyml" <<EOF
[package]
name = "$1"
version = "0.1.0"
cyrius = "$V"

[build]
entry = "src/main.cyr"
output = "build/app"

[deps]
stdlib = ["syscalls"]

[deps.prod]
git = "file://$W/o/prod"
tag = "v1"
modules = ["dist/prod.cyr"]

[deps.mockpeer]
git = "file://$W/o/mockpeer"
tag = "v1"
modules = ["dist/mockpeer.cyr"]
$2
EOF
    printf 'fn main(): i64 { return prod_v() - 3; }\nvar r = main();\nsyscall(SYS_EXIT, r);\n' > "$P/src/main.cyr"
    printf 'var r = mock_v() + prod_v() - 10;\nsyscall(60, r);\n' > "$P/tests/a.tcyr"
}

# ── D1 ──
mkp app 'scope = "test"'
rc=0; cy deps -v > "$W/d1.out" 2>&1 || rc=$?
MPV1=$(git -C "$W/o/mockpeer" rev-parse 'v1^{commit}')
if [ "$rc" = 0 ] && [ -f "$P/lib/mockpeer.cyr" ] && grep -q "^commit${TAB}${MPV1}${TAB}mockpeer${TAB}" "$P/cyrius.lock" \
    && grep -q 'lib/mockpeer.cyr' "$P/cyrius.lock" && grep -q '^  mockpeer  tag v1 @.* \[test scope\]$' "$W/d1.out"; then
    ok "D1 deps -v: the test dep is vendored, commit-pinned, hashed and listed [test scope]"
else bad "D1 (rc $rc): $(grep -v '^ *$' "$W/d1.out" | tr '\n' '|' | cut -c1-300)"; fi
# ── D2 ──
rc=0; cy test > "$W/d2.out" 2>&1 || rc=$?
if [ "$rc" = 0 ] && grep -q '^1 passed, 0 failed$' "$W/d2.out"; then ok "D2 cyrius test: mock_v() is in scope with no include"
else bad "D2 (rc $rc): $(tail -3 "$W/d2.out" | tr '\n' '|')"; fi
# ── D3 ──
printf 'var r = mock_v();\nsyscall(60, 0);\n' > "$P/src/uses_mock.cyr"
rc=0; cy build src/uses_mock.cyr build/um > "$W/d3.out" 2>&1 || rc=$?
rb=0; cy build > "$W/d3b.out" 2>&1 || rb=$?
if [ "$rc" != 0 ] && grep -q "undefined function 'mock_v'" "$W/d3.out" && [ "$rb" = 0 ]; then
    ok "D3 cyrius build: mock_v() is undefined there (rc $rc); the project's own entry builds"
else bad "D3 (rc $rc, entry $rb): $(grep -i 'error\|undefined' "$W/d3.out" | head -2 | tr '\n' '|')"; fi
# ── D4 ──
mkp ab 'scope = "test"'; cy build > "$W/d4a.out" 2>&1
mkp at 'scope = "test"'; cy test > "$W/d4b.out" 2>&1
if [ -f "$W/ab/lib/mockpeer.cyr" ] && diff -r "$W/ab/lib" "$W/at/lib" > /dev/null && cmp -s "$W/ab/cyrius.lock" "$W/at/cyrius.lock"; then
    ok "D4 lib/ and cyrius.lock are byte-identical whether a build or a test resolved"
else bad "D4: $(diff -r "$W/ab/lib" "$W/at/lib" 2>&1 | head -2 | tr '\n' '|') lock $(cmp "$W/ab/cyrius.lock" "$W/at/cyrius.lock" 2>&1)"; fi
# ── D5 ──
if ! grep -q 'ghost\|phantom\|nowhere\|no-such-repo' "$W/d1.out" && [ ! -f "$W/app/lib/ghost_x.cyr" ] && [ ! -f "$W/app/lib/phantom.cyr" ] \
    && [ ! -d "$H/deps/phantom" ] && [ -f "$W/app/lib/prod.cyr" ] && [ -f "$W/app/lib/leaf.cyr" ]; then
    ok "D5 a production dependency's own scope = \"test\" entries are never walked (its leaf is)"
else bad "D5: $(grep 'ghost\|phantom\|nowhere\|no-such' "$W/d1.out" | head -2 | tr '\n' '|')"; fi
# ── D6 ──
mkp bad1 'scope = "dev"'
rc=0; cy deps > "$W/d6.out" 2>&1 || rc=$?
mkp bad2 'scope = 1'
rc2=0; cy deps > "$W/d6b.out" 2>&1 || rc2=$?
if [ "$rc" = 1 ] && grep -qF 'error: [deps.mockpeer] scope = "dev" is not a scope — the one scope is "test"' "$W/d6.out" \
    && [ "$rc2" = 1 ] && grep -qF 'error: [deps.mockpeer] scope is not a TOML string' "$W/d6b.out"; then
    ok "D6 scope = \"dev\" and scope = 1 are refused by name (rc 1 each)"
else bad "D6 (rc $rc / $rc2): $(grep error "$W/d6.out" "$W/d6b.out" | tr '\n' '|')"; fi
# ── D7 ──
P="$W/app"
rc=0; cy deps --dry-run > "$W/d7.out" 2>&1 || rc=$?
if [ "$rc" = 0 ] && grep -q '^  mockpeer  tag v1 from .*\[test scope\]$' "$W/d7.out" && grep -q '^  leaf  ' "$W/d7.out" \
    && ! grep -q 'ghost\|phantom' "$W/d7.out"; then ok "D7 deps --dry-run marks mockpeer [test scope] and lists no dependency's own test dep"
else bad "D7 (rc $rc): $(tr '\n' '|' < "$W/d7.out")"; fi
# ── D8 ──
mkp plain ''
rc=0; cy deps -v > "$W/d8.out" 2>&1 || rc=$?
if [ "$rc" = 0 ] && ! grep -q 'test scope' "$W/d8.out" && diff -r "$W/plain/lib" "$W/app/lib" > /dev/null \
    && ! grep -q 'scope is not a known key' "$W/d1.out"; then
    ok "D8 additive: without scope the same files resolve, no [test scope]; scope is a known key"
else bad "D8 (rc $rc): $(diff -r "$W/plain/lib" "$W/app/lib" 2>&1 | head -2 | tr '\n' '|')"; fi
# ── D9 ──
P="$W/app"; rm -f "$P/lib/mockpeer.cyr"
rc=0; cy deps --locked > "$W/d9.out" 2>&1 || rc=$?
if [ "$rc" = 1 ] && grep -q 'mockpeer' "$W/d9.out" && [ ! -f "$P/lib/mockpeer.cyr" ]; then ok "D9 deps --locked holds the test dep to lib/ + the lock: the missing lib/mockpeer.cyr is named, nothing written"
else bad "D9 (rc $rc): $(grep -i 'error\|mockpeer' "$W/d9.out" | head -3 | tr '\n' '|')"; fi
# ── D10 ──
P="$W/dia"; rm -rf "$P"; mkdir -p "$P/src"
cat > "$P/cyrius.cyml" <<EOF
[package]
name = "dia"
version = "0.1.0"
cyrius = "$V"

[deps]
stdlib = ["syscalls"]

[deps.leaf]
git = "file://$W/o/leaf"
tag = "v2"
modules = ["dist/leaf.cyr"]
scope = "test"

[deps.prod]
git = "file://$W/o/prod"
tag = "v1"
modules = ["dist/prod.cyr"]
EOF
rc=0; cy deps > "$W/d10.out" 2>&1 || rc=$?
if [ "$rc" = 0 ] && grep -q 'return 1;' "$P/lib/leaf.cyr" && grep -qF 'note: leaf v2 (wanted by the root) not used; v1 (prod) resolved first' "$W/d10.out"; then
    ok "D10 the production dependency's leaf@v1 resolves first; the root's test-scope leaf@v2 is named, not used"
else bad "D10 (rc $rc): lib/leaf.cyr '$(cat "$P/lib/leaf.cyr" 2>/dev/null)' — $(tr '\n' '|' < "$W/d10.out")"; fi
# ── D11 ──
P="$W/twice"; rm -rf "$P"; mkdir -p "$P/src"
cat > "$P/cyrius.cyml" <<EOF
[package]
name = "twice"
version = "0.1.0"
cyrius = "$V"

[deps.a..b]
git = "file://$W/o/leaf"
tag = "v1"

[deps.zz
git = "file://$W/o/leaf"
tag = "v1"

[deps.mockpeer]
git = "file://$W/o/mockpeer"
tag = "v1"
modules = ["dist/mockpeer.cyr"]
scope = "test"
EOF
rc=0; cy deps > "$W/d11.out" 2>&1 || rc=$?
n1=$(grep -c '^error: \[deps.a\.\.b\] is not a usable dep name' "$W/d11.out")
n2=$(grep -c '^error: \[deps.zz has no closing' "$W/d11.out")
if [ "$rc" = 1 ] && [ "$n1" = 1 ] && [ "$n2" = 1 ] && grep -q ' deps resolved, 1 errors$' "$W/d11.out"; then
    ok "D11 an unsafe and an unclosed root header: each refused once, the root manifest counted once"
else bad "D11 (rc $rc; a..b named ${n1}x, zz named ${n2}x): $(grep 'resolved' "$W/d11.out")"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
