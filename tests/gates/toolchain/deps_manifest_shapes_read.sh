#!/bin/sh
# deps_manifest_shapes_read.sh — `cyrius deps` reads its manifest through the ONE reader
# (`_toml_line`, cbt/manifest.cyr): a `[deps.NAME]` table, its keys, `[deps] stdlib`, `[groups]`
# and `[features]` are found the way TOML writes them, never in prose or a multi-line value, and
# a section ends at the next table header of EITHER kind. The dry run and distlib's named-dep set
# read the same headers.
#
# 6.6.20 (REFACTOR-02). 6.6.17 put every other manifest read on `_toml_line`; `cyrius deps` kept
# a private column-0 walker. MEASURED on e696746d (each row below):
#   R2  an INDENTED `tag` was dropped: rc 0, no commit pin, lib/foo.cyr = the UNRELEASED HEAD;
#       indented `path` / `modules`: rc 0, nothing vendored, no message (yet --dry-run listed it)
#   R3  `[ deps.foo ]` ignored (rc 0, nothing vendored)
#   R4  `[deps.foo ]` vendored as `lib/foo _foo.cyr` (the space kept)
#   R5  a `[deps.foo]` inside a `"""` description resolved and vendored
#   R6  a later `[docs] tag = …` was read as foo's tag (any `[d…]` table continued the section)
#   R7  a later `[[bin]] tag = …` was applied to a tagless foo (a `[[` line never ended it)
#   R8  an indented `  [deps.foo]` header vendored, but --dry-run said there were no entries
#   R9  a `"""` description holding `stdlib = ["math"]` REPLACED the real `[deps] stdlib`
#       (cmd_deps' section-blind byte scan); R10 the same in `cyrius lib sync`'s copy
#   R11 `optional = tru` read as true (first byte only)
#   R14 (review) a manifest whose only dep table was `[deps.]`: `cyrius build` skipped the auto
#       resolve and built, rc 0, while `cyrius deps` refused it — a fourth header rule
# R1 (the control shape), R12 ([groups] / [features] through the new reader) and R13 (distlib's
# named-dep exclude set) are the anti-over-reach axes.
#
# Hermetic: a mktemp CYRIUS_HOME with the CLI built FROM SOURCE as the pin's own wrapper, local
# file:// origins, no system / global gitconfig. Every expected byte and commit comes from the
# origin (`git show <tag>:…`, `rev-parse`), never from the resolver under test.
# CYRIUS_GATE_CLI=<built cyrius> runs it where build/cycc is foreign; else a non-Linux host SKIPs.
#
# Mutation ledger (MEASURED, each mutant built from cbt/ and run via CYRIUS_GATE_CLI):
#   the e696746d walker (cbt/ before the rewrite)          -> R2 R3 R4 R5 R6 R7 R8 R9 R10 R11 red
#   a section ends only at a kind-1 header (`[[` continues) -> R7 red
#   keys matched as a prefix (`kl` unchecked)               -> R1 red (`tagline` read as `tag`)
#   optional back to its first byte                         -> R11 red
#   dry run lists every header, refused or not              -> R8 red
#   the auto resolve back on its own header test (`hl > 5`) -> R14 red (build skipped the resolve, rc 0)
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-"$ROOT/build/cycc"}
OS=$(uname -s 2>/dev/null || echo unknown)
G=deps_manifest_shapes_read
command -v git >/dev/null 2>&1 || { echo "SKIP: $G: git not found"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'chmod -R u+w "$W" 2>/dev/null || true; rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
V=$(tr -d '[:space:]' < "$ROOT/VERSION")
TAB=$(printf '\t')

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

# ── the origin: foo 1.0.0 returns 1, 2.0.0 returns 2, the untagged HEAD returns 3 ───────────
F="$W/o/foo"; mkdir -p "$F/dist"
( cd "$F" && git init -q . \
  && printf 'fn foo_v(): i64 { return 1; }\n' > dist/foo.cyr && git add -A && git commit -qm v1 && git tag 1.0.0 \
  && printf 'fn foo_v(): i64 { return 2; }\n' > dist/foo.cyr && git commit -qam v2 && git tag 2.0.0 \
  && printf 'fn foo_v(): i64 { return 3; }\n' > dist/foo.cyr && git commit -qam v3 )
git -C "$F" show 1.0.0:dist/foo.cyr > "$W/foo1"; git -C "$F" show 2.0.0:dist/foo.cyr > "$W/foo2"; git -C "$F" show HEAD:dist/foo.cyr > "$W/foo3"
C1=$(git -C "$F" rev-parse '1.0.0^{commit}')
[ "${#C1}" = 40 ] && ! cmp -s "$W/foo1" "$W/foo3" && ! cmp -s "$W/foo1" "$W/foo2" \
    || { echo "FAIL: $G: origin fixture not built"; exit 1; }
PD="$W/pathdep"; mkdir -p "$PD/dist"; cp "$W/foo2" "$PD/dist/foo.cyr"

mkp() {   # $1 = project dir; stdin = everything after [package]
    mkdir -p "$1/src"
    { printf '[package]\nname = "p"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n' "$V"; cat; } > "$1/cyrius.cyml"
    printf 'fn main(): i64 { return 0; }\nvar r = main();\nsyscall(60, r);\n' > "$1/src/main.cyr"
}
run() {   # $1 = project dir, $2.. = verb; sets rc, writes $1.out / $1.err
    d=$1; shift
    rc=0; if ( cd "$d" && "$CY" "$@" > "$d.out" 2> "$d.err" ); then rc=0; else rc=$?; fi
}
freshcache() { chmod -R u+w "$H/deps" 2>/dev/null || true; rm -rf "$H/deps"; mkdir -p "$H/deps"; }
lockpins() {  # $1 = project dir, $2 = name → the commit shas the lock pins for that name
    [ -f "$1/cyrius.lock" ] || return 0
    grep "^commit$TAB" "$1/cyrius.lock" | awk -F"$TAB" -v n="$2" '$3 == n { print $2 }'
}

# R1: the control — column-0 keys, tag 1.0.0; `tagline` is another key, not `tag`.
freshcache; P="$W/r1"; mkp "$P" <<EOF

[deps.foo]
git = "file://$F"
tag = "1.0.0"
tagline = "the release notes"
modules = ["dist/foo.cyr"]
EOF
run "$P" deps
if [ "$rc" -eq 0 ] && cmp -s "$P/lib/foo.cyr" "$W/foo1" && [ "$(lockpins "$P" foo)" = "$C1" ]; then
    ok "R1 control: lib/foo.cyr == git show 1.0.0:dist/foo.cyr, the lock pins 1.0.0's commit"
else bad "R1 (rc=$rc pins='$(lockpins "$P" foo)'): $(head -3 "$P.err")"; fi

# R2: every key INDENTED (a git dep and a path dep) — read exactly like R1.
freshcache; P="$W/r2"; mkp "$P" <<EOF

[deps.foo]
    git = "file://$F"
    tag = "1.0.0"
    modules = ["dist/foo.cyr"]

[deps.bar]
	path = "$PD"
	modules = ["dist/foo.cyr"]
EOF
run "$P" deps
if [ "$rc" -eq 0 ] && cmp -s "$P/lib/foo.cyr" "$W/foo1" && [ "$(lockpins "$P" foo)" = "$C1" ] \
   && cmp -s "$P/lib/bar_foo.cyr" "$PD/dist/foo.cyr"; then
    ok "R2 indented keys: foo pinned at 1.0.0 (not the unreleased HEAD), the tab-indented path dep vendored"
else bad "R2 (rc=$rc pins='$(lockpins "$P" foo)' lib=[$(ls "$P/lib" 2>/dev/null | tr '\n' ' ')]): $(head -3 "$P.err")"; fi

# R3 / R4: `[ deps.foo ]` is the table foo; `[deps.foo ]` is foo, not "foo ".
freshcache; P="$W/r3"; mkp "$P" <<EOF

[ deps.foo ]
git = "file://$F"
tag = "1.0.0"
modules = ["dist/foo.cyr"]
EOF
run "$P" deps; rc3=$rc
P="$W/r4"; mkp "$P" <<EOF

[deps.bar ]
path = "$PD"
modules = ["dist/foo.cyr"]
EOF
run "$P" deps; rc4=$rc
if [ "$rc3" -eq 0 ] && cmp -s "$W/r3/lib/foo.cyr" "$W/foo1" && [ "$rc4" -eq 0 ] && [ -f "$W/r4/lib/bar_foo.cyr" ] \
   && [ "$(ls "$W/r4/lib" | grep -c ' ')" = 0 ]; then
    ok "R3/R4 '[ deps.foo ]' resolves foo; '[deps.bar ]' vendors lib/bar_foo.cyr (no space in any name)"
else bad "R3/R4 (rc3=$rc3 rc4=$rc4 r4lib=[$(ls "$W/r4/lib" 2>/dev/null | tr '\n' '|')]): $(head -2 "$W/r3.err")"; fi

# R5: a `[deps.foo]` written inside a multi-line description is prose.
freshcache; P="$W/r5"; mkp "$P" <<EOF
description = """
How to depend on us:
[deps.foo]
git = "file://$F"
tag = "1.0.0"
modules = ["dist/foo.cyr"]
"""
EOF
run "$P" deps
if [ "$rc" -eq 0 ] && [ ! -e "$P/lib/foo.cyr" ] && [ -z "$(ls -A "$H/deps")" ]; then
    ok "R5 a [deps.foo] inside a \"\"\" description: not a table — nothing cloned, nothing vendored"
else bad "R5 (rc=$rc deps=[$(ls -A "$H/deps" | tr '\n' ' ')]): $(head -2 "$P.out" "$P.err")"; fi

# R6 / R7: a later `[docs]` table and a later `[[bin]]` array table END the dep section.
freshcache; P="$W/r6"; mkp "$P" <<EOF

[deps.foo]
git = "file://$F"
tag = "1.0.0"
modules = ["dist/foo.cyr"]

[docs]
tag = "2.0.0"
EOF
run "$P" deps; rc6=$rc
freshcache; P="$W/r7"; mkp "$P" <<EOF

[deps.foo]
git = "file://$F"
modules = ["dist/foo.cyr"]

[[bin]]
tag = "1.0.0"
EOF
run "$P" deps; rc7=$rc
if [ "$rc6" -eq 0 ] && cmp -s "$W/r6/lib/foo.cyr" "$W/foo1" && [ "$rc7" -eq 0 ] && cmp -s "$W/r7/lib/foo.cyr" "$W/foo3" \
   && [ -z "$(lockpins "$W/r7" foo)" ] && [ -d "$H/deps/foo/.untagged" ]; then
    ok "R6/R7 [docs] tag is not foo's (foo stays at 1.0.0); [[bin]] tag is not a tagless foo's (default branch, no pin)"
else bad "R6/R7 (rc6=$rc6 rc7=$rc7 pins7='$(lockpins "$W/r7" foo)'): $(head -2 "$W/r6.err" "$W/r7.err")"; fi

# R8: an indented header — the dry run lists exactly what the real run resolves.
freshcache; P="$W/r8"; mkp "$P" <<EOF

  [deps.foo]
git = "file://$F"
tag = "1.0.0"
modules = ["dist/foo.cyr"]

[deps.bad..name]
path = "$PD"
EOF
run "$P" deps --dry-run; rcd=$rc; cp "$P.out" "$W/r8.dry"; cp "$P.err" "$W/r8.dryerr"
run "$P" deps; rcr=$rc
# 6.7.6: a dry-run line names the dep AND where it would come from (`  foo  tag 1.0.0 from …`)
if [ "$rcd" -eq 1 ] && [ "$rcr" -eq 1 ] && grep -q "^  foo  tag 1\.0\.0 from file://" "$W/r8.dry" && ! grep -q 'bad' "$W/r8.dry" \
   && grep -qF '[deps.bad..name] is not a usable dep name' "$W/r8.dryerr" && grep -qF '[deps.bad..name] is not a usable dep name' "$P.err" \
   && cmp -s "$P/lib/foo.cyr" "$W/foo1"; then
    ok "R8 an indented [deps.foo]: --dry-run lists it and the real run vendors it; a refused name is refused by both (rc 1 each)"
else bad "R8 (dry rc=$rcd real rc=$rcr): dry=[$(tr '\n' '|' < "$W/r8.dry")] err=[$(head -1 "$P.err")]"; fi

# R9 / R10: `[deps] stdlib` is the key in [deps], not a `stdlib = [...]` inside a description —
# for `cyrius deps` and for `cyrius lib sync` (the second copy of the scan).
DECOY=$(printf 'description = """\nstdlib = ["math"]\n"""\n\n[deps]\nstdlib = ["string", "fmt"]\n')
P="$W/r9"; printf '%s\n' "$DECOY" | mkp "$P"
run "$P" deps; rc9=$rc
P="$W/r10"; printf '%s\n' "$DECOY" | mkp "$P"
run "$P" lib sync; rc10=$rc
if [ "$rc9" -eq 0 ] && [ -f "$W/r9/lib/string.cyr" ] && [ -f "$W/r9/lib/fmt.cyr" ] && [ ! -e "$W/r9/lib/math.cyr" ] \
   && [ "$rc10" -eq 0 ] && [ -f "$W/r10/lib/string.cyr" ] && [ -f "$W/r10/lib/fmt.cyr" ] && [ ! -e "$W/r10/lib/math.cyr" ]; then
    ok "R9/R10 a \"\"\"-embedded stdlib = [\"math\"]: deps and lib sync both vendor the real [deps] stdlib (string, fmt), not math"
else bad "R9/R10 (rc9=$rc9 rc10=$rc10 lib9=[$(ls "$W/r9/lib" 2>/dev/null | tr '\n' ' ')] lib10=[$(ls "$W/r10/lib" 2>/dev/null | tr '\n' ' ')]): $(head -2 "$W/r10.err")"; fi

# R11: `optional` is the bareword true / false — `tru` is refused by name, `false` resolves.
freshcache; P="$W/r11a"; mkp "$P" <<EOF

[deps.bar]
path = "$PD"
modules = ["dist/foo.cyr"]
optional = tru
EOF
run "$P" deps; rca=$rc
P="$W/r11b"; mkp "$P" <<EOF

[deps.bar]
path = "$PD"
modules = ["dist/foo.cyr"]
optional = false
EOF
run "$P" deps; rcb=$rc
if [ "$rca" -eq 1 ] && grep -qxF "error: [deps.bar] optional is not true or false — section refused" "$W/r11a.err" \
   && [ ! -e "$W/r11a/lib/bar_foo.cyr" ] && [ "$rcb" -eq 0 ] && [ -f "$W/r11b/lib/bar_foo.cyr" ]; then
    ok "R11 optional = tru: refused by name, rc 1; optional = false: resolves"
else bad "R11 (rca=$rca rcb=$rcb): $(head -2 "$W/r11a.err")"; fi

# R12: [groups] and [features] through the reader — indented entries, a group named in stdlib,
# a default feature activating an optional dep.
freshcache; P="$W/r12"; mkp "$P" <<EOF

[groups]
    web = ["string", "fmt"]

[features]
    default = ["bar"]

[deps]
stdlib = ["web"]

[deps.bar]
path = "$PD"
modules = ["dist/foo.cyr"]
optional = true
EOF
run "$P" deps
if [ "$rc" -eq 0 ] && [ -f "$P/lib/string.cyr" ] && [ -f "$P/lib/fmt.cyr" ] && [ -f "$P/lib/bar_foo.cyr" ]; then
    ok "R12 [groups] web = [string, fmt] named in stdlib expands; [features] default activates the optional bar"
else bad "R12 (rc=$rc lib=[$(ls "$P/lib" 2>/dev/null | tr '\n' ' ')]): $(head -2 "$P.err")"; fi

# R13: distlib --modular excludes a REAL named dep's leaf from the index — and only a real one:
# a `[deps.fmt]` inside a """ value no longer drops the fmt leaf.
P="$W/r13"; mkp "$P" <<EOF
description = """
[deps.fmt]
"""

[lib]
modules = ["src/a.cyr"]

  [deps.str]
path = "$PD"
modules = []
EOF
printf 'include "lib/string.cyr"\ninclude "lib/fmt.cyr"\ninclude "lib/str.cyr"\nfn q_a(): i64 { return 4; }\n' > "$P/src/a.cyr"
run "$P" distlib --modular
if [ "$rc" -eq 0 ] && grep -qxF 'a = ["lib:string", "lib:fmt"]' "$P/dist/p/index.cyml"; then
    ok "R13 distlib --modular: the indented [deps.str] is excluded, the \"\"\"-quoted [deps.fmt] is not"
else bad "R13 (rc=$rc): index=[$(grep '^a' "$P/dist/p/index.cyml" 2>/dev/null)] $(head -2 "$P.err")"; fi

# R14: the AUTO resolve before build / run / test reads dep tables by the same header rule — a
# manifest whose only dep table is `[deps.]` used to make `cyrius build` skip the resolve and
# build (rc 0) while `cyrius deps` refused it by name.
[ -x "$CC" ] && cp "$CC" "$H/versions/$V/bin/cycc" 2>/dev/null || true
P="$W/r14"; mkp "$P" <<EOF

[deps.]
path = "$PD"
EOF
run "$P" deps; rcd=$rc; cp "$P.err" "$W/r14.deperr"
run "$P" build src/main.cyr build/p
if [ "$rcd" -eq 1 ] && [ "$rc" -eq 1 ] && grep -qF 'error: [deps.] is not a usable dep name' "$W/r14.deperr" \
   && grep -qF 'error: [deps.] is not a usable dep name' "$P.err" && [ ! -e "$P/build/p" ]; then
    ok "R14 a manifest whose only dep table is [deps.]: cyrius build refuses it by the resolver's own line (rc 1, nothing built), as cyrius deps does"
else bad "R14 (deps rc=$rcd build rc=$rc): $(head -2 "$P.err") build=[$(ls "$P/build" 2>/dev/null | tr '\n' ' ')]"; fi
rm -f "$H/versions/$V/bin/cycc"

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
[ "$pass" -ge 11 ] || { echo "FAIL: $G: only $pass axes ran (floor 11)"; exit 1; }
echo "PASS: $G — [deps.NAME] tables, their keys, [deps] stdlib, [groups] and [features] are read as TOML, through one header rule"
