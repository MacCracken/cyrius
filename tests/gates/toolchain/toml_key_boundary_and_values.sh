#!/bin/sh
# toml_key_boundary_and_values.sh — 6.6.17 (P1 m6). The manifest line scanners in cbt/deps.cyr read
# whole TOML keys and TOML string values.
#
# THE DEFECTS (measured on 6.6.16):
#   * `_toml_key_at` rejected a key preceded by [A-Za-z0-9_] but not by `-`, so a key that is the
#     TAIL of a hyphenated key matched: `dev-stdlib = ["math"]` above the real `stdlib` made
#     `cyrius deps` vendor math.cyr and NOT the declared leaves (the scan takes the first match).
#     (`test` vs `test-only` — a key that is the HEAD of a hyphenated one — was already refused
#     by the separator test; axis 2 pins that, and the one reader's whole-token compare.)
#   * `[deps.X]` scalar values were read as "skip to the next double quote", so `path = '../foo'`
#     resolved the NEXT double-quoted string in the file (the modules entry) — and `tag = 'v1'`
#     the same; a single-quoted ARRAY element was dropped; a `"…"` inside a comment inside an
#     array was taken as an element.
#
# AXES
#   1. `dev-stdlib = [...]` above `stdlib = [...]`: deps vendors the declared leaf, not the decoy.
#   2. `[build] test-only` is not `test`, in either order (--print-config).
#   3. `[deps.foo] path = '../foo'` + `modules = ['src/foo.cyr']`: foo is vendored.
#   4. a git dep with `git = '…'` and `tag = 'v1'` (a local file:// origin) resolves THAT tag.
#   5. a `"…"` inside a comment inside `stdlib = [ … ]` is not a leaf.
#   6. `tag = v1` (not a TOML string) is refused by name, not read as some other string.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: toml_key_boundary_and_values: no compiler at $CC"; exit 77; }
command -v git >/dev/null 2>&1 || { echo "SKIP: toml_key_boundary_and_values: needs git (axis 4's origin)"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: toml_key_boundary_and_values: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: toml_key_boundary_and_values: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
chmod +x "$W/cyrius"
# A throwaway home whose pinned snapshot holds two leaves that name themselves.
H="$W/home"; mkdir -p "$H/bin" "$H/versions/9.9.9/lib"; cp "$CC" "$H/bin/cycc"
printf '# leaf: string\nfn string_marker(): i64 { return 1; }\n' > "$H/versions/9.9.9/lib/string.cyr"
printf '# leaf: math\nfn math_marker(): i64 { return 2; }\n' > "$H/versions/9.9.9/lib/math.cyr"
printf '# the resolver recognises a snapshot by this file\n' > "$H/versions/9.9.9/lib/syscalls.cyr"
cyr() { d=$1; shift; RC=0; ( cd "$d" && HOME="$W" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 GIT_CONFIG_NOSYSTEM=1 "$W/cyrius" "$@" ) > "$W/out" 2>&1 || RC=$?; }
show() { sed 's/^/      /' "$W/out" | head -6; }
pkg() { printf '[package]\nname = "%s"\nversion = "0.1.0"\ncyrius = "9.9.9"\n\n' "$1"; }

# ── 1: dev-stdlib is not stdlib ─────────────────────────────────────────────────────────
mkdir -p "$W/a1"; { pkg a1; printf '[deps]\ndev-stdlib = ["math"]\nstdlib = ["string"]\n'; } > "$W/a1/cyrius.cyml"
cyr "$W/a1" deps
if [ -f "$W/a1/lib/string.cyr" ] && [ ! -f "$W/a1/lib/math.cyr" ]; then echo "  ok 1: dev-stdlib = [\"math\"] is not the stdlib key — string vendored, math not"
else fail "1: vendored: $(ls "$W/a1/lib" 2>/dev/null | tr '\n' ' ') (want string.cyr only; rc $RC)"; show; fi

# ── 2: test-only is not test ────────────────────────────────────────────────────────────
x=$FAIL
mkdir -p "$W/a2"
for order in 'test-only = "src/wrong.cyr"\ntest = "src/test.cyr"\n' 'test = "src/test.cyr"\ntest-only = "src/wrong.cyr"\n'; do
    printf '[package]\nname = "a2"\n\n[build]\nentry = "src/main.cyr"\n%b' "$order" > "$W/a2/cyrius.cyml"
    cyr "$W/a2" build --print-config
    grep -qF '  build.test = ["src/test.cyr"]  (manifest: [build] test)' "$W/out" || { fail "2: test-only was read as test:"; show; }
done
printf '[package]\nname = "a2"\n\n[build]\nentry = "src/main.cyr"\ntest-only = "src/wrong.cyr"\n' > "$W/a2/cyrius.cyml"
cyr "$W/a2" build --print-config
grep -qF '  build.test = []  (default)' "$W/out" || { fail "2: a lone test-only declared build.test:"; show; }
[ "$FAIL" = "$x" ] && echo "  ok 2: [build] test-only is never [build] test (both orders, and alone)"

# ── 3: a single-quoted path ─────────────────────────────────────────────────────────────
mkdir -p "$W/a3/app" "$W/a3/foo/src"
printf 'fn foo_marker(): i64 { return 3; }\n' > "$W/a3/foo/src/foo.cyr"
{ pkg app; printf "[deps.foo]\npath = '../foo'\nmodules = ['src/foo.cyr']\n"; } > "$W/a3/app/cyrius.cyml"
cyr "$W/a3/app" deps
if grep -qs foo_marker "$W/a3/app/lib/"*.cyr; then echo "  ok 3: path = '../foo' and modules = ['src/foo.cyr'] (TOML literal strings) vendor foo"
else fail "3: foo not vendored from a single-quoted path (rc $RC; lib: $(ls "$W/a3/app/lib" 2>/dev/null | tr '\n' ' '))"; show; fi

# ── 4: a single-quoted git + tag ────────────────────────────────────────────────────────
O="$W/a4/origin"; mkdir -p "$O/src"
( cd "$O" && git init -q && git config user.email g@x && git config user.name g \
  && printf 'fn tagged_v1(): i64 { return 1; }\n' > src/foo.cyr && git add -A && git commit -qm v1 && git tag v1 \
  && printf 'fn moved_on(): i64 { return 2; }\n' > src/foo.cyr && git commit -qam later ) > /dev/null 2>&1 \
  || { echo "FAIL: toml_key_boundary_and_values: could not build the axis-4 git origin"; exit 1; }
mkdir -p "$W/a4/app"
{ pkg app; printf "[deps.foo]\ngit = 'file://%s'\ntag = 'v1'\nmodules = [\"src/foo.cyr\"]\n" "$O"; } > "$W/a4/app/cyrius.cyml"
cyr "$W/a4/app" deps
if grep -qs tagged_v1 "$W/a4/app/lib/"*.cyr; then echo "  ok 4: git = '…' / tag = 'v1' resolve the v1 tag"
else fail "4: tag = 'v1' did not resolve v1 (rc $RC; lib: $(ls "$W/a4/app/lib" 2>/dev/null | tr '\n' ' '))"; show; fi

# ── 5: a quoted word in a comment inside an array ──────────────────────────────────────
mkdir -p "$W/a5"; { pkg a5; printf '[deps]\nstdlib = [\n    "string",   # "math" moved out in 0.2\n]\n'; } > "$W/a5/cyrius.cyml"
cyr "$W/a5" deps
if [ -f "$W/a5/lib/string.cyr" ] && [ ! -f "$W/a5/lib/math.cyr" ]; then echo "  ok 5: a \"…\" inside a comment inside an array is not an element"
else fail "5: vendored: $(ls "$W/a5/lib" 2>/dev/null | tr '\n' ' ') (want string.cyr only)"; show; fi

# ── 6: a non-string tag is refused ──────────────────────────────────────────────────────
mkdir -p "$W/a6/app"
{ pkg app; printf '[deps.foo]\ngit = "file://%s"\ntag = v1\nmodules = ["src/foo.cyr"]\n' "$O"; } > "$W/a6/app/cyrius.cyml"
cyr "$W/a6/app" deps
if [ "$RC" -ne 0 ] && grep -q 'tag is not a TOML string' "$W/out" && [ ! -e "$W/a6/app/lib/foo.cyr" ]; then echo "  ok 6: tag = v1 (bare) is refused by name, nothing vendored"
else fail "6: a bare tag was not refused (rc $RC)"; show; fi

[ "$FAIL" = 0 ] || exit 1
echo "PASS: toml_key_boundary_and_values (hyphenated key tails, literal strings, comments in arrays)"
