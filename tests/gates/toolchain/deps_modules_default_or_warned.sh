#!/bin/sh
# deps_modules_default_or_warned.sh — a `[deps.X]` that lists no `modules` is either RESOLVED
# (its tag or path ships `dist/X.cyr`) or WARNED BY NAME and counted; it is never dropped
# silently. And a `[deps.NAME]` whose NAME would make a path (`/`, `..`) is refused, in the
# root manifest and in a transitive one.
#
# 6.6.13 (I10, filed by agnostic 0.1.7). `cbt/deps.cyr` cloned a named dep only under
# `dep_git != 0 && dep_modules != 0` and marked it visited only when a module was copied, so a
# block with `git` + `tag` and nothing else was never cloned, vendored, commit-pinned, counted
# or reported — `cyrius deps` exited 0 and said nothing. Because it was never visited, the
# closest-wins rule did not shield it either: a TRANSITIVE declaration of the same name
# resolved at ITS tag (agnostic's root tags moved ahead of agnosai's and the lock kept
# agnosai's). A `modular`-only git block hit the same guard. Now: no `modules` and no
# `modular` means `modules = ["dist/X.cyr"]` when that file exists at the tag / path;
# otherwise a named warning and `, N vendored nothing` in the summary, exit 0. An explicit
# `modules = []` is the silent "declared, not linked" spelling.
#
# CVE-TBD(I10d): the header NAME becomes the clone dir `<home>/deps/<name>/<tag>` and the
# default `dist/<name>.cyr`; `[deps.../../esc/x]` cloned OUTSIDE the dep cache on 6.6.12 (the
# v6.2.51 traversal guard covered sub-module / index / package names, never this one).
#
# Hermetic: a mktemp CYRIUS_HOME with the CLI built FROM SOURCE as the pin's own wrapper,
# local file:// origins, no /etc/gitconfig or ~/.gitconfig (GIT_CONFIG_NOSYSTEM +
# GIT_CONFIG_GLOBAL), GIT_ALLOW_PROTOCOL=file. Nothing reads or writes the live ~/.cyrius.
# EVERY EXPECTED BYTE AND COMMIT COMES FROM THE ORIGIN (`git show <tag>:…`, `rev-parse`), never
# from the resolver under test. CYRIUS_GATE_CLI=<built cyrius> runs it where build/cycc is a
# foreign binary (ecb/ach/cass/pi); without it a non-Linux host SKIPs by name.
#
# Mutation ledger (MEASURED, each mutant built from cbt/ and run via CYRIUS_GATE_CLI):
#   the 6.6.12 resolver (cbt/ unchanged up to the I10 bites) -> D1 D2 D3 D3b D4 D6 D8 red
#   need_clone guard back to `dep_modules != 0`            -> D1 D2 D3 D3b D6 red
#   drop the dist/<name>.cyr probe (no default)            -> D1 D2 D4 red
#   drop the warning text                                  -> D3 D3b D4 red
#   drop `, N vendored nothing` from the summary           -> D3 D3b D4 red
#   drop the modular-pull success mark                     -> D6 red
#   drop the [deps.NAME] traversal refusal (I10d)          -> D8 red
# D5 (modules = []) and D7 (optional / target gates) are the anti-over-reach axes: every
# mutant above leaves them green, and so must the fix.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-"$ROOT/build/cycc"}
OS=$(uname -s 2>/dev/null || echo unknown)
G=deps_modules_default_or_warned
command -v git >/dev/null 2>&1 || { echo "SKIP: $G: git not found"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'chmod -R u+w "$W" 2>/dev/null || true; rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
V=$(tr -d '[:space:]' < "$ROOT/VERSION")
TAB=$(printf '\t')

# ── the CLI under test, staged as the pin's own wrapper in a throwaway home ──────────────
nohost() {
    if [ "$OS" = Linux ]; then echo "FAIL: $G: $1"; exit 1; fi
    echo "SKIP: $G: $1 (pass CYRIUS_GATE_CLI=<built cyrius> to run here)"; exit 77
}
if [ -n "${CYRIUS_GATE_CLI:-}" ]; then
    [ -x "$CYRIUS_GATE_CLI" ] || { echo "FAIL: $G: CYRIUS_GATE_CLI=$CYRIUS_GATE_CLI is not executable"; exit 1; }
    cp "$CYRIUS_GATE_CLI" "$W/cyrius"
else
    [ -x "$CC" ] || nohost "build/cycc missing"
    ( cd "$ROOT" && cat cbt/cyrius.cyr | "$CC" > "$W/cyrius" 2>/dev/null ) || nohost "could not build cbt/cyrius.cyr"
    [ -s "$W/cyrius" ] || nohost "cbt/cyrius.cyr built an EMPTY binary"
fi
chmod +x "$W/cyrius"
"$W/cyrius" --version >/dev/null 2>&1 || nohost "the CLI under test does not execute here"
H="$W/home"; mkdir -p "$H/versions/$V/bin" "$H/versions/$V/lib" "$H/deps"
cp -r "$ROOT/lib/." "$H/versions/$V/lib/"
cp "$W/cyrius" "$H/versions/$V/bin/cyrius"; chmod +x "$H/versions/$V/bin/cyrius"
printf '%s\n' "$V" > "$H/current"; ln -s "$H/versions/$V/bin" "$H/bin"; ln -s "$H/versions/$V/lib" "$H/lib"
CY="$H/versions/$V/bin/cyrius"
export CYRIUS_HOME="$H"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_ALLOW_PROTOCOL=file
printf '[user]\n\tname = gate\n\temail = gate@example.invalid\n[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$W/gitconfig"

# ── origins ──────────────────────────────────────────────────────────────────────────────
# foo: 1.0.0 and 2.0.0 ship dist/foo.cyr (different bytes); 3.0.0 ships src/foo.cyr ONLY.
# bar: 1.0.0 ships dist/bar.cyr and a cyrius.cyml declaring foo 1.0.0 WITH modules (the
#      transitive declaration that used to win).
# mod: 1.0.0 ships the modular layout dist/mod/{a.cyr,index.cyml} and no dist/mod.cyr.
# tbad: 1.0.0 ships dist/tbad.cyr and a cyrius.cyml whose own header is `[deps.../../esc/y]`.
O="$W/o"; F="$O/foo"; B="$O/bar"; M="$O/mod"; T="$O/tbad"
mkdir -p "$F/dist" "$B/dist" "$M/dist/mod" "$T/dist"
( cd "$F" && git init -q . \
  && printf 'fn foo_v(): i64 { return 1; }\n' > dist/foo.cyr && git add -A && git commit -qm v1 && git tag 1.0.0 \
  && printf 'fn foo_v(): i64 { return 2; }\n' > dist/foo.cyr && git commit -qam v2 && git tag 2.0.0 \
  && git rm -q dist/foo.cyr && mkdir -p src && printf 'fn foo_v(): i64 { return 3; }\n' > src/foo.cyr \
  && git add -A && git commit -qm v3 && git tag 3.0.0 )
( cd "$B" && git init -q . && printf 'fn bar_v(): i64 { return 7; }\n' > dist/bar.cyr \
  && printf '[package]\nname = "bar"\nversion = "1.0.0"\nlanguage = "cyrius"\n\n[deps.foo]\ngit = "file://%s"\ntag = "1.0.0"\nmodules = ["dist/foo.cyr"]\n' "$F" > cyrius.cyml \
  && git add -A && git commit -qm v1 && git tag 1.0.0 )
( cd "$M" && git init -q . && printf 'fn mod_a(): i64 { return 5; }\n' > dist/mod/a.cyr && printf 'a = []\n' > dist/mod/index.cyml \
  && git add -A && git commit -qm v1 && git tag 1.0.0 )
( cd "$T" && git init -q . && printf 'fn tbad_v(): i64 { return 9; }\n' > dist/tbad.cyr \
  && printf '[package]\nname = "tbad"\nversion = "1.0.0"\nlanguage = "cyrius"\n\n[deps.../../esc/y]\ngit = "file://%s"\ntag = "2.0.0"\nmodules = ["dist/foo.cyr"]\n' "$F" > cyrius.cyml \
  && git add -A && git commit -qm v1 && git tag 1.0.0 )
git -C "$F" show 1.0.0:dist/foo.cyr > "$W/foo1.expect"
git -C "$F" show 2.0.0:dist/foo.cyr > "$W/foo2.expect"
git -C "$M" show 1.0.0:dist/mod/a.cyr > "$W/moda.expect"
C1=$(git -C "$F" rev-parse '1.0.0^{commit}'); C2=$(git -C "$F" rev-parse '2.0.0^{commit}'); C3=$(git -C "$F" rev-parse '3.0.0^{commit}')
CM=$(git -C "$M" rev-parse '1.0.0^{commit}')
[ -s "$W/foo2.expect" ] && [ "${#C2}" = 40 ] && [ "$C1" != "$C2" ] && ! cmp -s "$W/foo1.expect" "$W/foo2.expect" \
    || { echo "FAIL: $G: origin fixture not built (expected bytes / commits not computed from the origin)"; exit 1; }
if git -C "$F" cat-file -e 3.0.0:dist/foo.cyr 2>/dev/null; then echo "FAIL: $G: foo 3.0.0 must NOT ship dist/foo.cyr"; exit 1; fi

mkp() {   # $1 = project dir; stdin = the [deps.*] blocks
    mkdir -p "$1/src"
    { printf '[package]\nname = "p"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[build]\nentry = "src/main.cyr"\n\n' "$V"; cat; } > "$1/cyrius.cyml"
    printf 'fn main(): i64 { return 0; }\nvar r = main();\nsyscall(60, r);\n' > "$1/src/main.cyr"
}
run() {   # $1 = project dir; sets rc, writes $1.out / $1.err
    rc=0; if ( cd "$1" && "$CY" deps > "$1.out" 2> "$1.err" ); then rc=0; else rc=$?; fi
}
freshcache() { chmod -R u+w "$H/deps" 2>/dev/null || true; rm -rf "$H/deps"; mkdir -p "$H/deps"; }
lockpins() {  # $1 = project dir, $2 = name → the commit shas the lock pins for that name
    [ -f "$1/cyrius.lock" ] || return 0
    grep "^commit$TAB" "$1/cyrius.lock" | awk -F"$TAB" -v n="$2" '$3 == n { print $2 }'
}
warn_line() {  # $1 = name, $2 = what (tag 'X' / path)
    printf 'warning: [deps.%s] declares no modules and %s ships no dist/%s.cyr — nothing vendored; a transitive [deps.%s] will resolve instead (list modules, or modules = [] for a dep that is declared but not linked)\n' "$1" "$2" "$1" "$1"
}

# ── D1: git + tag, no modules → vendored from dist/foo.cyr, commit-pinned, counted ──────
freshcache; P="$W/d1"; mkp "$P" <<EOF
[deps.foo]
git = "file://$F"
tag = "2.0.0"
EOF
run "$P"
if [ "$rc" -eq 0 ] && cmp -s "$P/lib/foo.cyr" "$W/foo2.expect" && [ "$(lockpins "$P" foo)" = "$C2" ] \
   && grep -q "^1 deps resolved$" "$P.out" && ! grep -q 'warning' "$P.err"; then
    ok "D1 modules-less git dep: lib/foo.cyr == git show 2.0.0:dist/foo.cyr, lock pins 2.0.0's commit, '1 deps resolved', no warning"
else bad "D1 (rc=$rc pins='$(lockpins "$P" foo)' want=$C2): $(cat "$P.out" "$P.err" | head -4)"; fi

# ── D2: closest-wins — the ROOT's modules-less tag beats a transitive tag WITH modules ───
freshcache; P="$W/d2"; mkp "$P" <<EOF
[deps.foo]
git = "file://$F"
tag = "2.0.0"

[deps.bar]
git = "file://$B"
tag = "1.0.0"
modules = ["dist/bar.cyr"]
EOF
run "$P"
if [ "$rc" -eq 0 ] && cmp -s "$P/lib/foo.cyr" "$W/foo2.expect" && [ "$(lockpins "$P" foo)" = "$C2" ] && [ -f "$P/lib/bar.cyr" ]; then
    ok "D2 closest-wins: root foo 2.0.0 (no modules) beats bar's foo 1.0.0 — lib/foo.cyr is 2.0.0's bytes, the lock pins 2.0.0 ONLY"
else bad "D2 (rc=$rc foo pins='$(lockpins "$P" foo | tr '\n' ' ')' want only $C2 — 6.6.12 pinned $C1): $(head -3 "$P.out")"; fi

# ── D3: a tag that ships no dist/foo.cyr → the named warning, counted, exit 0, nothing ───
freshcache; P="$W/d3"; mkp "$P" <<EOF
[deps.foo]
git = "file://$F"
tag = "3.0.0"
EOF
run "$P"; warn_line foo "tag '3.0.0'" > "$W/d3.want"
if [ "$rc" -eq 0 ] && grep -qxF -f "$W/d3.want" "$P.err" && grep -q "^0 deps resolved, 1 vendored nothing$" "$P.out" \
   && [ ! -e "$P/lib/foo.cyr" ]; then
    ok "D3 tag without dist/foo.cyr: rc 0, the exact named warning (name + tag), '0 deps resolved, 1 vendored nothing', no lib/foo.cyr"
else bad "D3 (rc=$rc): out=[$(cat "$P.out")] err=[$(head -2 "$P.err")]"; fi
# ...and the warning's claim holds: a transitive [deps.foo] then resolves in its place
freshcache; P="$W/d3b"; mkp "$P" <<EOF
[deps.foo]
git = "file://$F"
tag = "3.0.0"

[deps.bar]
git = "file://$B"
tag = "1.0.0"
modules = ["dist/bar.cyr"]
EOF
run "$P"
if [ "$rc" -eq 0 ] && grep -qxF -f "$W/d3.want" "$P.err" && cmp -s "$P/lib/foo.cyr" "$W/foo1.expect" \
   && grep -q "^2 deps resolved, 1 vendored nothing$" "$P.out"; then
    ok "D3b ...and, as the warning says, bar's transitive foo 1.0.0 resolves instead (lib/foo.cyr is 1.0.0's bytes)"
else bad "D3b (rc=$rc): out=[$(cat "$P.out")] err=[$(head -2 "$P.err")]"; fi

# ── D4: path-only — with dist/ it is vendored; without it, the warning names the path ────
PD="$W/pathdep"; mkdir -p "$PD/dist"; cp "$W/foo2.expect" "$PD/dist/foo.cyr"
PN="$W/pathnodist"; mkdir -p "$PN/src"; printf 'fn foo_v(): i64 { return 0; }\n' > "$PN/src/foo.cyr"
P="$W/d4a"; mkp "$P" <<EOF
[deps.foo]
path = "$PD"
EOF
run "$P"; rca=$rc
P="$W/d4b"; mkp "$P" <<EOF
[deps.foo]
path = "$PN"
EOF
run "$P"; rcb=$rc; warn_line foo "$PN" > "$W/d4.want"
if [ "$rca" -eq 0 ] && cmp -s "$W/d4a/lib/foo.cyr" "$PD/dist/foo.cyr" && grep -q "^1 deps resolved$" "$W/d4a.out" \
   && [ "$rcb" -eq 0 ] && grep -qxF -f "$W/d4.want" "$W/d4b.err" && grep -q "^0 deps resolved, 1 vendored nothing$" "$W/d4b.out" \
   && [ ! -e "$W/d4b/lib/foo.cyr" ]; then
    ok "D4 path-only: dist/foo.cyr present -> vendored; absent -> the named warning (it names the path), counted, rc 0"
else bad "D4 (rca=$rca rcb=$rcb): a=[$(cat "$W/d4a.out" "$W/d4a.err" | head -2)] b=[$(cat "$W/d4b.out" "$W/d4b.err" | head -2)]"; fi

# ── D5: `modules = []` is the declared-not-linked opt-out — no default, no warning ───────
freshcache; P="$W/d5"; mkp "$P" <<EOF
[deps.foo]
git = "file://$F"
tag = "2.0.0"
modules = []
EOF
run "$P"
if [ "$rc" -eq 0 ] && [ ! -e "$P/lib/foo.cyr" ] && ! grep -q 'warning' "$P.err" && ! grep -q 'vendored nothing' "$P.out"; then
    ok "D5 modules = []: nothing vendored, no warning, no count, rc 0 (the declared-but-not-linked spelling)"
else bad "D5 (rc=$rc): out=[$(cat "$P.out")] err=[$(head -2 "$P.err")]"; fi

# ── D6: a `modular`-only git block is cloned, vendored, and its pin reaches the lock ─────
freshcache; P="$W/d6"; mkp "$P" <<EOF
[deps.mod]
git = "file://$M"
tag = "1.0.0"
modular = ["a"]
EOF
run "$P"
if [ "$rc" -eq 0 ] && [ -d "$H/deps/mod/1.0.0/.git" ] && cmp -s "$P/lib/mod_a.cyr" "$W/moda.expect" \
   && [ "$(lockpins "$P" mod)" = "$CM" ] && ! grep -q 'warning' "$P.err"; then
    ok "D6 modular-only git dep: cloned, lib/mod_a.cyr == git show 1.0.0:dist/mod/a.cyr, lock pins its commit, no warning"
else bad "D6 (rc=$rc clone=$([ -d "$H/deps/mod/1.0.0" ] && echo yes || echo no) pins='$(lockpins "$P" mod)'): $(cat "$P.out" "$P.err" | head -3)"; fi

# ── D7: optional / target-gated modules-less blocks still skip SILENTLY, uncloned ────────
freshcache; P="$W/d7"; mkp "$P" <<EOF
[deps.foo]
git = "file://$F"
tag = "2.0.0"
optional = true

[deps.baz]
git = "file://$F"
tag = "2.0.0"
target = "no-such-target"
EOF
run "$P"
if [ "$rc" -eq 0 ] && [ ! -s "$P.err" ] && ! grep -q 'vendored nothing' "$P.out" && [ -z "$(ls -A "$H/deps")" ] && [ ! -d "$P/lib" ]; then
    ok "D7 optional (no active feature) and target-mismatch blocks: silent, nothing cloned, nothing counted"
else bad "D7 (rc=$rc deps=[$(ls -A "$H/deps" | tr '\n' ' ')]): $(cat "$P.out" "$P.err" | head -3)"; fi

# ── D8: CVE-TBD(I10d) — a header NAME with `/` or `..` is refused, root and transitive ───
# The escape targets are measured on the FILESYSTEM: `[deps.../x]` resolves its clone dir to
# $H/deps/../x = $H/x, `[deps.../../esc/x]` to $W/esc/x — exactly where 6.6.12 cloned.
snapw() { ( cd "$W" && find . -path ./home/deps -prune -o -path './d8*' -prune -o -path ./o -prune -o -print | LC_ALL=C sort ); }
freshcache; snapw > "$W/d8.before"
P="$W/d8a"; mkp "$P" <<EOF
[deps.../x]
git = "file://$F"
tag = "2.0.0"

[deps.../../esc/x]
git = "file://$F"
tag = "2.0.0"
modules = ["dist/foo.cyr"]
EOF
run "$P"; rca=$rc
P="$W/d8t"; mkp "$P" <<EOF
[deps.tbad]
git = "file://$T"
tag = "1.0.0"
modules = ["dist/tbad.cyr"]
EOF
run "$P"; rct=$rc
snapw | grep -v -e '^\./d8' > "$W/d8.after" || true
grep -v -e '^\./d8' "$W/d8.before" > "$W/d8.before2" || true
if [ "$rca" -ne 0 ] && grep -qF '[deps.../x] is not a usable dep name' "$W/d8a.err" && grep -qF '[deps.../../esc/x] is not a usable dep name' "$W/d8a.err" \
   && [ "$rct" -ne 0 ] && grep -qF '[deps.../../esc/y] is not a usable dep name' "$W/d8t.err" && [ -f "$W/d8t/lib/tbad.cyr" ] \
   && [ ! -e "$H/x" ] && [ ! -e "$W/esc" ] && cmp -s "$W/d8.before2" "$W/d8.after" && [ ! -f "$W/d8a/cyrius.lock" ] && [ ! -f "$W/d8t/cyrius.lock" ]; then
    ok "D8 [deps.../x] and [deps.../../esc/x] (root) and a TRANSITIVE [deps.../../esc/y]: refused by name, rc 1, no lock, nothing created outside \$CYRIUS_HOME/deps"
else bad "D8 (root rc=$rca transitive rc=$rct H/x=$([ -e "$H/x" ] && echo EXISTS || echo absent) W/esc=$([ -e "$W/esc" ] && echo EXISTS || echo absent)): $(diff "$W/d8.before2" "$W/d8.after" | head -3) $(head -2 "$W/d8a.err")"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
[ "$pass" -ge 9 ] || { echo "FAIL: $G: only $pass axes ran (floor 9)"; exit 1; }
echo "PASS: $G — a modules-less [deps.X] is resolved from dist/X.cyr or warned and counted; unsafe names refused"
