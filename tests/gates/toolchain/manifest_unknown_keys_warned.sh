#!/bin/sh
# manifest_unknown_keys_warned.sh — 6.7.6 (lane C, R11). A key nothing reads in the project's own
# `[deps]` / `[deps.NAME]`, and a TABLE nothing reads (`[dev-dependencies]`, `[[bin]]`, a misspelt
# `[dep.x]`), is named by `cyrius deps` and every resolving verb — once per run, as a warning (the
# verb still succeeds), exactly as `[build]`'s unknown keys have been since 6.6.17. Before 6.7.6
# `dev = true` inside a [deps.X] and a whole `[dev-dependencies]` table read as silence: an inert
# key cannot be observed to be wrong. A DEPENDENCY's manifest is its author's business and is not
# warned about. Known = what `cyrius help manifest` declares (cbt/manifest.cyr's vocabulary).
#
# AXES (path deps only — no network, a throwaway CYRIUS_HOME):
#   U1  `dev = true` in a root [deps.x]: one warning naming the table and the key
#   U2  an unknown [deps] key: one warning
#   U3  `[dev-dependencies]` and `[[bin]]`: one warning each, naming the table
#   U4  anti-over-reach: a manifest that uses every declared section and every [deps.*] key: no warning
#   U5  an unknown key in a DEPENDENCY's own manifest: not warned
#   U6  the warnings do not fail the verb (rc 0, the dep vendored)
#   U7  `cyrius build` (resolve + compile) prints each warning once
#
# MUTATION LEDGER (measured 2026-10-08, each in a SCRATCH copy of the tree, one at a time; real
# tree 7/7 green):
#   M1  no unknown-key warning for a root [deps.NAME] ............... U1 U7 red
#   M2  every section reads as known ................................ U3 U7 red
#   M3  a dependency's manifest is warned about too ................. U4 U5 red
#   M4  the once-per-run guard removed .............................. U7 red
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=manifest_unknown_keys_warned
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
unset CYRIUS_LOCAL CYRIUS_LOCKED CYRIUS_LIB_OVERLAY
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
cy() { ( cd "$P" && HOME="$W/nohome" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 exec "$CY" "$@" ); }
# a path dep whose OWN manifest carries an unknown key (U5)
D="$W/dep"; mkdir -p "$D/dist"
printf 'fn dep_v(): i64 { return 4; }\n' > "$D/dist/dep.cyr"
printf '[package]\nname = "dep"\n\n[deps]\nweird = 1\n\n[deps.inner]\npath = "../nowhere"\nmodules = []\nsurprise = true\n\n[mystery]\nx = 1\n' > "$D/cyrius.cyml"
mkp() { P="$W/$1"; rm -rf "$P"; mkdir -p "$P/src"; { printf '[package]\nname = "%s"\nversion = "0.1.0"\ncyrius = "%s"\n\n' "$1" "$V"; cat; } > "$P/cyrius.cyml"
        printf 'fn main(): i64 { return dep_v(); }\nvar r = main();\nsyscall(60, r);\n' > "$P/src/main.cyr"; }
TAIL='is not a known key and nothing reads it (cyrius help manifest lists them)'
STAIL='is not a known section and nothing reads it (cyrius help manifest lists them)'
mkp a <<EOF
[deps]
stdlib = ["syscalls"]
dev-stdlib = ["assert"]

[deps.dep]
path = "../dep"
modules = ["dist/dep.cyr"]
dev = true

[dev-dependencies]
x = "1"

[[bin]]
name = "a"
EOF
rc=0; cy deps > "$W/a.out" 2>&1 || rc=$?
grep -qxF "warn: cyrius.cyml [deps.dep] dev $TAIL" "$W/a.out" && ok "U1 dev = true in a root [deps.dep]: named" || bad "U1: $(grep warn "$W/a.out" | tr '\n' '|')"
grep -qxF "warn: cyrius.cyml [deps] dev-stdlib $TAIL" "$W/a.out" && ok "U2 an unknown [deps] key: named" || bad "U2: $(grep warn "$W/a.out" | tr '\n' '|')"
if grep -qxF "warn: cyrius.cyml [dev-dependencies] $STAIL" "$W/a.out" && grep -qxF "warn: cyrius.cyml [[bin]] $STAIL" "$W/a.out"; then
    ok "U3 [dev-dependencies] and [[bin]]: one warning each"
else bad "U3: $(grep warn "$W/a.out" | tr '\n' '|')"; fi
if ! grep -q 'weird\|surprise\|mystery\|inner' "$W/a.out"; then ok "U5 the dependency's own unknown key, [deps] key and table: not warned"
else bad "U5: $(grep 'weird\|surprise\|mystery\|inner' "$W/a.out" | tr '\n' '|')"; fi
if [ "$rc" -eq 0 ] && [ -f "$P/lib/dep.cyr" ]; then ok "U6 the warnings do not fail the verb (rc 0, the dep vendored)"
else bad "U6 (rc=$rc): $(grep -v warn "$W/a.out" | head -2)"; fi
rc=0; cy build src/main.cyr build/a > "$W/b.out" 2>&1 || rc=$?
n1=$(grep -c "\[deps.dep\] dev $TAIL" "$W/b.out"); n2=$(grep -c "\[dev-dependencies\] $STAIL" "$W/b.out")
if [ "$rc" -eq 0 ] && [ "$n1" -eq 1 ] && [ "$n2" -eq 1 ]; then ok "U7 cyrius build: each warning once"
else bad "U7 (rc=$rc dev x$n1, dev-dependencies x$n2)"; fi
# ── U4: every declared section and every [deps.*] key ──
mkdir -p "$W/full/data"; printf 'x' > "$W/full/data/blob.bin"
mkp full <<EOF
[build]
entry = "src/main.cyr"
output = "build/full"

[deps]
stdlib = ["syscalls"]

[deps.dep]
path = "../dep"
modules = ["dist/dep.cyr"]
requires = ["syscalls"]

[deps.opt]
path = "../dep"
modules = ["dist/dep.cyr"]
optional = true
target = "aarch64"
modular = []

[features]
default = []
gpu = ["opt"]

[groups]
core = ["syscalls"]

[lib]
modules = ["src/main.cyr"]

[lib.small]
modules = ["src/main.cyr"]

[release]
bins = ["full"]

[embed]
BLOB = "data/blob.bin"

[coverage]
programs = []

[sections]
base = "0x100000"
EOF
rc=0; cy deps > "$W/full.out" 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'is not a known' "$W/full.out"; then ok "U4 every declared section and [deps.*] key: no warning"
else bad "U4 (rc=$rc): $(grep 'warn\|error' "$W/full.out" | tr '\n' '|')"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
