#!/bin/sh
# deps_modules_default_or_warned.sh — a `[deps.X]` that lists no `modules` is either RESOLVED
# (its tag or path ships `dist/X.cyr`) or WARNED BY NAME and counted; it is never dropped
# silently. And a `[deps.NAME]` whose NAME would make a path (`/`, `..`), or whose `tag` would
# move the clone dir out of `<home>/deps/<name>`, is refused, in the root manifest and in a
# transitive one.
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
# CVE-62: the header NAME becomes the clone dir `<home>/deps/<name>/<tag>` and the
# default `dist/<name>.cyr`; `[deps.../../esc/x]` cloned OUTSIDE the dep cache on 6.6.12 (the
# v6.2.51 traversal guard covered sub-module / index / package names, never this one).
# CVE-76 (6.6.16): the same class on the TAG — `tag = "../../../esc/sub"` made git mkdir
# outside the cache, and a tag naming an existing dir printed `rm -rf` advice for it (D9).
# 6.6.20 (CVE-TBD): the NAME rule caught up with the tag rule — `[deps.]` / `[deps..]` aliased
# another dep's cache root, and `\`, control bytes and a header spanning lines passed (D8b-D8f).
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
#   drop the tag refusal call (6.6.16, T1)                 -> D9a D9b D9c D9f red
#   call the tag check on a tagless dep (no dep_tag guard) -> D4 D9e red (SIGSEGV)
#   also refuse `/` inside a tag                           -> D9d red
#   drop the empty-tag refusal                             -> D9f red
#   print the refused tag raw (no \xNN escape)            -> D9f red
#   6.6.20: drop the empty / `.`-led name rule              -> D8b D8c D8f red
#   6.6.20: print the refused name raw (no \xNN escape)     -> D8d D8e D8f red
#   6.6.20: drop the `\` / control-byte name rule           -> D8d D8e D8f red
#   6.6.20: dry-run skips `[deps.]` again (`i - ls > 7`)    -> D8f red
# D5 (modules = []) and D7 (optional / target gates) are the anti-over-reach axes: every
# mutant above leaves them green, and so must the fix. D9d (plain + slash tags) and D9e
# (tagless path / git deps) are the tag check's anti-over-reach rows.
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

# ── D8: CVE-62 — a header NAME with `/` or `..` is refused, root and transitive ───
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

# ── D9: CVE-76 — a `tag` that would move the clone dir out of <home>/deps/<name> ─────
# The tag is joined into `<home>/deps/<name>/<tag>`. On 6.6.15 `../../../esc/sub` made git
# mkdir $W/esc before it rejected the ref, and `../../..` (an EXISTING dir, $W) skipped the
# clone and printed `rm -rf <home>/deps/foo/../../..` — the parent of CYRIUS_HOME. git runs
# through `/usr/bin/env git`, so a PATH shim logs every invocation: "git never invoked" is
# measured, not inferred. The anti-over-reach rows (D9d, D9e) must stay green under every
# mutant: plain and slash tags, and the tagless path / git deps that are most of the ecosystem.
REALGIT=$(command -v git)
mkdir -p "$W/shim"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/git.log"\nexec "%s" "$@"\n' "$W" "$REALGIT" > "$W/shim/git"
chmod +x "$W/shim/git"
run9() {   # run() with the git shim first on PATH; $W/git.log starts empty
    : > "$W/git.log"
    rc=0; if ( cd "$1" && PATH="$W/shim:$PATH" "$CY" deps > "$1.out" 2> "$1.err" ); then rc=0; else rc=$?; fi
}
snap9() { ( cd "$W" && find . -path ./home/deps -prune -o -path './d9*' -prune -o -path ./o -prune \
    -o -path ./shim -prune -o -path ./git.log -prune -o -print | LC_ALL=C sort ); }
git -C "$F" tag rel/1.0 2.0.0
TT="$O/tt"; mkdir -p "$TT/dist"
( cd "$TT" && git init -q . && printf 'fn tt_v(): i64 { return 4; }\n' > dist/tt.cyr \
  && printf '[package]\nname = "tt"\nversion = "1.0.0"\nlanguage = "cyrius"\n\n[deps.foo]\ngit = "file://%s"\ntag = "../../../esc/t"\nmodules = ["dist/foo.cyr"]\n' "$F" > cyrius.cyml \
  && git add -A && git commit -qm v1 && git tag 1.0.0 )
git -C "$B" show HEAD:dist/bar.cyr > "$W/barmain.expect"
noleak() {  # $1 = project dir: stderr + stdout carry no rm -rf and no real path under $W
    ! grep -q 'rm -rf' "$1.err" "$1.out" && ! grep -qF "$W" "$1.err" "$1.out"
}
REFUSAL_TAIL="is not a usable tag (it would make the cache path leave <home>/deps/foo) — section refused"

# D9a: the root traversal tag that used to mkdir outside the cache.
freshcache; snap9 > "$W/d9.before"
P="$W/d9a"; mkp "$P" <<EOF
[deps.foo]
git = "file://$F"
tag = "../../../esc/sub"
modules = ["dist/foo.cyr"]
EOF
run9 "$P"; snap9 > "$W/d9a.after"
if [ "$rc" -eq 1 ] && grep -qxF "error: [deps.foo] tag '../../../esc/sub' $REFUSAL_TAIL" "$P.err" \
   && [ ! -s "$W/git.log" ] && [ ! -e "$W/esc" ] && cmp -s "$W/d9.before" "$W/d9a.after" && [ ! -f "$P/cyrius.lock" ] \
   && [ ! -e "$P/lib/foo.cyr" ] && noleak "$P"; then
    ok "D9a root tag '../../../esc/sub': refused by name, rc 1, git never invoked, nothing created outside \$CYRIUS_HOME/deps, no lock"
else bad "D9a (rc=$rc git=[$(head -1 "$W/git.log")] W/esc=$([ -e "$W/esc" ] && echo EXISTS || echo absent)): $(diff "$W/d9.before" "$W/d9a.after" | head -3) $(head -2 "$P.err")"; fi

# D9b: `../../..` names an EXISTING dir ($W) — the shape that printed `rm -rf` of it.
freshcache; mkdir -p "$H/deps/foo"
P="$W/d9b"; mkp "$P" <<EOF
[deps.foo]
git = "file://$F"
tag = "../../.."
modules = ["dist/foo.cyr"]
EOF
run9 "$P"
if [ "$rc" -eq 1 ] && grep -qxF "error: [deps.foo] tag '../../..' $REFUSAL_TAIL" "$P.err" && [ ! -s "$W/git.log" ] \
   && [ ! -f "$P/cyrius.lock" ] && noleak "$P"; then
    ok "D9b tag '../../..' naming an existing dir: refused, rc 1, no 'rm -rf' and no real path in the output, git never invoked"
else bad "D9b (rc=$rc git=[$(head -1 "$W/git.log")]): $(head -4 "$P.err")"; fi

# D9c: the same class from a TRANSITIVE manifest (tt 1.0.0 declares foo at '../../../esc/t').
freshcache; snap9 > "$W/d9.before"
P="$W/d9c"; mkp "$P" <<EOF
[deps.tt]
git = "file://$TT"
tag = "1.0.0"
modules = ["dist/tt.cyr"]
EOF
run9 "$P"; snap9 > "$W/d9c.after"
if [ "$rc" -eq 1 ] && grep -qxF "error: [deps.foo] tag '../../../esc/t' $REFUSAL_TAIL" "$P.err" \
   && [ -f "$P/lib/tt.cyr" ] && ! grep -qF "file://$F" "$W/git.log" && [ ! -e "$W/esc" ] && cmp -s "$W/d9.before" "$W/d9c.after" \
   && [ ! -f "$P/cyrius.lock" ] && [ ! -e "$P/lib/foo.cyr" ] && noleak "$P"; then
    ok "D9c a TRANSITIVE [deps.foo] tag '../../../esc/t': refused by name, rc 1, foo's origin never fetched, nothing outside \$CYRIUS_HOME/deps, no lock"
else bad "D9c (rc=$rc W/esc=$([ -e "$W/esc" ] && echo EXISTS || echo absent)): $(diff "$W/d9.before" "$W/d9c.after" | head -3) $(head -3 "$P.err")"; fi

# D9d: anti-over-reach — a plain tag and a SLASH tag still clone, pin and vendor.
freshcache
P="$W/d9d1"; mkp "$P" <<EOF
[deps.foo]
git = "file://$F"
tag = "1.0.0"
modules = ["dist/foo.cyr"]
EOF
run9 "$P"; rc1=$rc
P="$W/d9d2"; mkp "$P" <<EOF
[deps.foo]
git = "file://$F"
tag = "rel/1.0"
modules = ["dist/foo.cyr"]
EOF
run9 "$P"; rc2=$rc
if [ "$rc1" -eq 0 ] && cmp -s "$W/d9d1/lib/foo.cyr" "$W/foo1.expect" && [ "$(lockpins "$W/d9d1" foo)" = "$C1" ] \
   && [ "$rc2" -eq 0 ] && [ -d "$H/deps/foo/rel/1.0/.git" ] && cmp -s "$W/d9d2/lib/foo.cyr" "$W/foo2.expect" \
   && [ "$(lockpins "$W/d9d2" foo)" = "$C2" ] && ! grep -q 'not a usable tag' "$W/d9d1.err" "$W/d9d2.err"; then
    ok "D9d tags '1.0.0' and 'rel/1.0' still clone (under <home>/deps/foo/), vendor the tag's bytes and pin the tag's commit"
else bad "D9d (rc1=$rc1 rc2=$rc2 pins1='$(lockpins "$W/d9d1" foo)' pins2='$(lockpins "$W/d9d2" foo)'): $(cat "$W/d9d1.err" "$W/d9d2.err" | head -4)"; fi

# D9e: anti-over-reach — TAGLESS deps (no `tag` key at all) never reach the check.
freshcache
P="$W/d9e1"; mkp "$P" <<EOF
[deps.foo]
path = "../pathdep"
modules = ["dist/foo.cyr"]
EOF
run9 "$P"; rc1=$rc
P="$W/d9e2"; mkp "$P" <<EOF
[deps.bar]
git = "file://$B"
modules = ["dist/bar.cyr"]
EOF
run9 "$P"; rc2=$rc
if [ "$rc1" -eq 0 ] && cmp -s "$W/d9e1/lib/foo.cyr" "$PD/dist/foo.cyr" \
   && [ "$rc2" -eq 0 ] && [ -d "$H/deps/bar/.untagged/.git" ] && cmp -s "$W/d9e2/lib/bar.cyr" "$W/barmain.expect" \
   && ! grep -q 'not a usable tag' "$W/d9e1.err" "$W/d9e2.err"; then
    ok "D9e tagless path = \"../pathdep\" and a tagless git dep (default branch): both resolve, no tag refusal"
else bad "D9e (rc1=$rc1 rc2=$rc2): $(cat "$W/d9e1.out" "$W/d9e1.err" "$W/d9e2.out" "$W/d9e2.err" | head -6)"; fi

# D9f: the rest of the refused set — a literally empty `tag = ""`, a leading `-` / `/`, a
# `.`-led component, a backslash, a control byte (shown escaped, never raw).
freshcache; d9f=0; d9fn=0
ESC=$(printf '\033')
for t in '' '-x' '/abs' '.hidden' 'a/.b' 'a\b' "a${ESC}b"; do
    d9fn=$((d9fn+1)); P="$W/d9f$d9fn"; mkp "$P" <<EOF
[deps.foo]
git = "file://$F"
tag = "$t"
modules = ["dist/foo.cyr"]
EOF
    run9 "$P"
    if [ "$rc" -eq 1 ] && grep -qF "error: [deps.foo] tag '" "$P.err" && grep -qF "$REFUSAL_TAIL" "$P.err" \
       && [ ! -s "$W/git.log" ] && [ ! -f "$P/cyrius.lock" ] && ! grep -qF "$ESC" "$P.err"; then
        d9f=$((d9f+1))
    else echo "    D9f row $d9fn: rc=$rc git=[$(head -1 "$W/git.log")] $(head -2 "$P.err")"; fi
done
if [ "$d9f" -eq 7 ] && grep -qxF "error: [deps.foo] tag '' $REFUSAL_TAIL" "$W/d9f1.err" \
   && grep -qxF "error: [deps.foo] tag 'a\\x1bb' $REFUSAL_TAIL" "$W/d9f7.err"; then
    ok "D9f tag = \"\", '-x', '/abs', '.hidden', 'a/.b', a backslash and a control byte: each refused (rc 1, git never invoked, no lock), the ESC shown as \\x1b"
else bad "D9f ($d9f of 7 refused): $(head -1 "$W/d9f7.err")"; fi

# ── D8b-D8f: 6.6.20 (CVE-TBD) — the rest of the unusable header NAMES ───────────────────
# `_dep_reject_unsafe_name` refused only `/` and `..`, so `[deps.]` and `[deps..]` passed and
# their clone dir `<home>/deps/<name>/<tag>` became `<home>/deps//<tag>` / `<home>/deps/./<tag>`
# — ANOTHER dep's NAME directory (a foreign checkout cloned AS `<home>/deps/<tag>`, and the
# tamper refusal printed `rm -rf <home>/deps/./victim`, every cached tag of victim). `\` and
# control bytes passed too, and the name was echoed raw (a terminal escape out of a transitive
# manifest; the scan ran across newlines, so a header could span lines).
REFUSE_NAME_TAIL="is not a usable dep name (empty, \`.\`-led, or holding \`/\`, \`\\\`, \`..\` or a control byte, it would make a path) — section refused"
# D8b: the root's `[deps.]`, `[deps..]` (aimed at a planted victim's whole cache root) and `[deps..x]`.
freshcache; mkdir -p "$H/deps/victim/v1"; printf 'kept\n' > "$H/deps/victim/v1/marker"
d8b=0
for nm in '' '.' '.x'; do
    P="$W/d8b$d8b"; mkp "$P" <<EOF
[deps.$nm]
git = "file://$F"
tag = "victim"
modules = ["dist/foo.cyr"]
EOF
    run9 "$P"
    if [ "$rc" -eq 1 ] && grep -qxF "error: [deps.$nm] $REFUSE_NAME_TAIL" "$P.err" && [ ! -s "$W/git.log" ] \
       && [ ! -f "$P/cyrius.lock" ] && ! grep -q 'rm -rf' "$P.err" "$P.out" && [ ! -e "$P/lib/foo.cyr" ]; then
        d8b=$((d8b+1))
    else echo "    D8b name '$nm': rc=$rc git=[$(head -1 "$W/git.log")] $(head -3 "$P.err")"; d8b=$((d8b+10)); fi
done
if [ "$d8b" -eq 3 ] && [ "$(ls -A "$H/deps")" = victim ] && [ "$(cat "$H/deps/victim/v1/marker")" = kept ] \
   && [ "$(ls -A "$H/deps/victim")" = v1 ]; then
    ok "D8b [deps.], [deps..] and [deps..x]: each refused by name (rc 1, git never invoked, no lock, no rm -rf advice); the planted victim cache is untouched"
else bad "D8b ($d8b): deps=[$(ls -A "$H/deps" | tr '\n' ' ')] victim=[$(ls -A "$H/deps/victim" 2>/dev/null | tr '\n' ' ')]"; fi

# D8c: a TRANSITIVE `[deps.]` (tdot 1.0.0 declares one at foo 2.0.0) — refused, never cloned.
TD="$O/tdot"; mkdir -p "$TD/dist"
( cd "$TD" && git init -q . && printf 'fn tdot_v(): i64 { return 6; }\n' > dist/tdot.cyr \
  && printf '[package]\nname = "tdot"\nversion = "1.0.0"\nlanguage = "cyrius"\n\n[deps.]\ngit = "file://%s"\ntag = "2.0.0"\nmodules = ["dist/foo.cyr"]\n' "$F" > cyrius.cyml \
  && git add -A && git commit -qm v1 && git tag 1.0.0 )
freshcache
P="$W/d8c"; mkp "$P" <<EOF
[deps.tdot]
git = "file://$TD"
tag = "1.0.0"
modules = ["dist/tdot.cyr"]
EOF
run9 "$P"
if [ "$rc" -eq 1 ] && grep -qxF "error: [deps.] $REFUSE_NAME_TAIL" "$P.err" && [ -f "$P/lib/tdot.cyr" ] \
   && [ "$(ls -A "$H/deps")" = tdot ] && [ ! -e "$H/deps/2.0.0" ] && ! grep -qF "file://$F" "$W/git.log" \
   && [ ! -f "$P/cyrius.lock" ] && [ ! -e "$P/lib/foo.cyr" ]; then
    ok "D8c a TRANSITIVE [deps.]: refused by name, rc 1, foo's origin never fetched, nothing cloned AS \$CYRIUS_HOME/deps/2.0.0"
else bad "D8c (rc=$rc deps=[$(ls -A "$H/deps" | tr '\n' ' ')]): $(head -3 "$P.err")"; fi

# D8d: a control byte (ESC) and a backslash in the name — refused, and SHOWN escaped, never raw.
freshcache
P="$W/d8d1"; mkp "$P" <<EOF
[deps.ev${ESC}[2Jil]
git = "file://$F"
tag = "2.0.0"
modules = ["dist/foo.cyr"]
EOF
run9 "$P"; rc1=$rc
P="$W/d8d2"; mkp "$P" <<EOF
[deps.a\\b]
git = "file://$F"
tag = "2.0.0"
modules = ["dist/foo.cyr"]
EOF
run9 "$P"; rc2=$rc
if [ "$rc1" -eq 1 ] && grep -qxF "error: [deps.ev\\x1b[2Jil] $REFUSE_NAME_TAIL" "$W/d8d1.err" && ! grep -qF "$ESC" "$W/d8d1.err" "$W/d8d1.out" \
   && [ "$rc2" -eq 1 ] && grep -qxF "error: [deps.a\\b] $REFUSE_NAME_TAIL" "$W/d8d2.err" \
   && [ -z "$(ls -A "$H/deps")" ] && [ ! -f "$W/d8d1/cyrius.lock" ] && [ ! -f "$W/d8d2/cyrius.lock" ]; then
    ok "D8d a name holding ESC (shown as \\x1b, no raw ESC on either stream) and one holding a backslash: refused, rc 1, nothing cloned"
else bad "D8d (rc1=$rc1 rc2=$rc2): $(head -2 "$W/d8d1.err" | od -c | head -3) $(head -1 "$W/d8d2.err")"; fi

# D8e: a header that runs across lines — `[deps.a` / `forged line` / `]` — is refused, and no
# line of the manifest is replayed onto the terminal as a line of its own.
freshcache
P="$W/d8e"; mkp "$P" <<EOF
[deps.a
forged line
]
git = "file://$F"
tag = "2.0.0"
modules = ["dist/foo.cyr"]
EOF
run9 "$P"
if [ "$rc" -eq 1 ] && [ ! -s "$W/git.log" ] && [ -z "$(ls -A "$H/deps")" ] && [ ! -f "$P/cyrius.lock" ] \
   && ! grep -q '^forged line' "$P.err" "$P.out" && [ ! -e "$P/lib/foo.cyr" ]; then
    ok "D8e a [deps.a header spanning lines: refused, rc 1, git never invoked, no forged line on the terminal"
else bad "D8e (rc=$rc git=[$(head -1 "$W/git.log")]): $(head -3 "$P.err")"; fi

# D8f: `deps --dry-run` agrees with the real run: it lists `[deps.]` (it skipped it) as refused,
# exits 1, shows a control byte escaped — and still lists a usable name (anti-over-reach).
P="$W/d8f"; mkp "$P" <<EOF
[deps.foo]
git = "file://$F"
tag = "2.0.0"

[deps.]
git = "file://$F"
tag = "2.0.0"

[deps.e${ESC}x]
git = "file://$F"
EOF
rc=0; ( cd "$P" && "$CY" deps --dry-run > "$P.out" 2> "$P.err" ) || rc=$?
if [ "$rc" -eq 1 ] && grep -qxF "  foo" "$P.out" && grep -qxF "error: [deps.] $REFUSE_NAME_TAIL" "$P.err" \
   && grep -qxF "error: [deps.e\\x1bx] $REFUSE_NAME_TAIL" "$P.err" && ! grep -qF "$ESC" "$P.err" "$P.out" \
   && [ ! -d "$P/lib" ] && [ ! -f "$P/cyrius.lock" ]; then
    ok "D8f deps --dry-run: lists foo, refuses [deps.] and the ESC name by the resolver's own line (escaped), rc 1, writes nothing"
else bad "D8f (rc=$rc): out=[$(cat "$P.out" | tr '\n' '|')] err=[$(head -2 "$P.err")]"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
[ "$pass" -ge 20 ] || { echo "FAIL: $G: only $pass axes ran (floor 20)"; exit 1; }
echo "PASS: $G — a modules-less [deps.X] is resolved from dist/X.cyr or warned and counted; unsafe names and tags refused"
