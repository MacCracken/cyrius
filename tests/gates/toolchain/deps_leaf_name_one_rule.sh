#!/bin/sh
# deps_leaf_name_one_rule.sh — a stdlib LEAF name obeys ONE rule (`_dep_leaf_ok`, cbt/deps.cyr)
# wherever it is produced or consumed: [A-Za-z0-9_/-], non-empty, no leading, trailing or
# doubled `/`. A `/` is legal — `unicode/categories` is a leaf.
#
# 6.6.20 (REFACTOR-05). There were three rules for one token. distlib's requires block allowed
# `/`; the `--modular` index emit checked NOTHING (it wrote whatever sat between the quotes of
# an `include "lib/…"`); and the consumer checked a `lib:` index entry with the dep-NAME rule,
# which refuses every `/`. MEASURED on e696746d: a producer module keeping
# `include "lib/unicode/categories.cyr"` gave `distlib --modular` rc 0 and the index row
# `a = ["lib:unicode/categories"]`; every consumer then got rc 1, "unsafe dep name (path
# traversal rejected): unicode/categories" — and lib/modp_a.cyr written anyway — while the SAME
# leaf through the `.deps` sidecar route resolved and built. Sidecar and `requires` leaves had no
# name check at all: a `../../x` line reached `_dep_copy_file`'s destination guard and then the
# false "it IS in the stdlib (<a path outside the stdlib>)".
#
# AXES
#   L1  the modular route: the index carries `lib:unicode/categories`, a consumer resolves it,
#       vendors lib/unicode/, and the program BUILDS and RUNS (exit 7).
#   L2  an index entry `lib:../../x` is refused BY NAME (the leaf rule's line), rc 1.
#   L3  a sidecar line `../../w/pwn` and a `requires` entry `../x` are refused by name, rc 1,
#       with no "it IS in the stdlib" claim and nothing written outside lib/.
#   L4  `[deps] stdlib = ["../x"]` is refused by the same line.
#   L5  the producer: a module keeping `include "lib/../evil.cyr"` makes `distlib --modular`
#       refuse by name and write no index.
# Mutation ledger (MEASURED via CYRIUS_GATE_CLI, each mutant built from cbt/):
#   the e696746d CLI                                  -> L1 L2 L3 L4 L5 red
#   `lib:` entries back on the dep-name rule           -> L1 red (it refuses the `/` leaf)
#   no leaf check in _dep_pull_leaves                  -> L3 red
#   no leaf check on [deps] stdlib                     -> L4 red
#   no leaf check in the --modular index emit          -> L5 red
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-"$ROOT/build/cycc"}
OS=$(uname -s 2>/dev/null || echo unknown)
G=deps_leaf_name_one_rule
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'chmod -R u+w "$W" 2>/dev/null || true; rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
V=$(tr -d '[:space:]' < "$ROOT/VERSION")

nohost() {
    if [ "$OS" = Linux ]; then echo "FAIL: $G: $1"; exit 1; fi
    echo "SKIP: $G: $1 (pass CYRIUS_GATE_CLI=<built cyrius> to run here)"; exit 77
}
[ -x "$CC" ] || nohost "build/cycc missing"
if [ -n "${CYRIUS_GATE_CLI:-}" ]; then
    [ -x "$CYRIUS_GATE_CLI" ] || { echo "FAIL: $G: CYRIUS_GATE_CLI=$CYRIUS_GATE_CLI is not executable"; exit 1; }
    cp "$CYRIUS_GATE_CLI" "$W/cyrius"
else
    ( cd "$ROOT" && cat cbt/cyrius.cyr | "$CC" > "$W/cyrius" 2>/dev/null ) || nohost "could not build cbt/cyrius.cyr"
    [ -s "$W/cyrius" ] || nohost "cbt/cyrius.cyr built an EMPTY binary"
fi
chmod +x "$W/cyrius"
"$W/cyrius" --version >/dev/null 2>&1 || nohost "the CLI under test does not execute here"
H="$W/home"; mkdir -p "$H/versions/$V/bin" "$H/versions/$V/lib" "$H/deps"
cp -r "$ROOT/lib/." "$H/versions/$V/lib/"
cp "$W/cyrius" "$H/versions/$V/bin/cyrius"; cp "$CC" "$H/versions/$V/bin/cycc"
chmod +x "$H/versions/$V/bin/cyrius" "$H/versions/$V/bin/cycc"
printf '%s\n' "$V" > "$H/current"; ln -s "$H/versions/$V/bin" "$H/bin"; ln -s "$H/versions/$V/lib" "$H/lib"
CY="$H/versions/$V/bin/cyrius"
export CYRIUS_HOME="$H"
[ -f "$H/lib/unicode/categories.cyr" ] || { echo "FAIL: $G: the stdlib has no unicode/categories.cyr to test the / leaf with"; exit 1; }

run() {   # $1 = dir, $2.. = verb; sets rc, writes $1.out / $1.err
    d=$1; shift
    rc=0; if ( cd "$d" && "$CY" "$@" > "$d.out" 2> "$d.err" ); then rc=0; else rc=$?; fi
}
consumer() {  # $1 = dir; stdin = the [deps.*] blocks; main calls $2() and exits with it
    mkdir -p "$1/src"
    { printf '[package]\nname = "c"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/c"\n\n' "$V"; cat; } > "$1/cyrius.cyml"
    printf 'fn main(): i64 { return %s(); }\nvar r = main();\nsyscall(60, r);\n' "$2" > "$1/src/main.cyr"
}
outside_clean() { [ ! -e "$W/w" ] && [ ! -e "$W/x.cyr" ] && [ ! -e "$W/evil.cyr" ]; }
LEAF_TAIL="which is not a stdlib leaf name ([A-Za-z0-9_/-], no leading, trailing or doubled /) — refused"

# ── L1: the modular route carries a `/` leaf end to end ──────────────────────────────────
MP="$W/modp"; mkdir -p "$MP/src"
printf '[package]\nname = "modp"\nversion = "0.1.0"\nlanguage = "cyrius"\n\n[lib]\nmodules = ["src/a.cyr"]\n' > "$MP/cyrius.cyml"
printf 'include "lib/unicode/categories.cyr"\nfn modp_a_fn(): i64 { return 7; }\n' > "$MP/src/a.cyr"
run "$MP" distlib --modular; rcp=$rc
P="$W/l1"; consumer "$P" modp_a_fn <<EOF
[deps.modp]
path = "$MP"
modular = ["a"]
EOF
run "$P" deps; rcd=$rc
rcb=1; rcx=1
if [ "$rcd" -eq 0 ]; then
    run "$P" build; rcb=$rc
    if [ "$rcb" -eq 0 ] && [ -x "$P/build/c" ]; then rcx=0; "$P/build/c" || rcx=$?; fi
fi
if [ "$rcp" -eq 0 ] && grep -qxF 'a = ["lib:unicode/categories"]' "$MP/dist/modp/index.cyml" \
   && [ "$rcd" -eq 0 ] && [ -f "$P/lib/unicode/categories.cyr" ] && [ -f "$P/lib/modp_a.cyr" ] && [ "$rcb" -eq 0 ] && [ "$rcx" -eq 7 ]; then
    ok "L1 distlib --modular writes lib:unicode/categories; the consumer resolves it, vendors lib/unicode/, builds, and the program exits 7"
else bad "L1 (distlib rc=$rcp deps rc=$rcd build rc=$rcb run=$rcx): idx=[$(grep '^a' "$MP/dist/modp/index.cyml" 2>/dev/null)] $(head -2 "$P.err")"; fi

# ── L2: a hostile index entry is refused by the leaf rule, by name ───────────────────────
HP="$W/hostp"; mkdir -p "$HP/dist/hostp"
printf 'fn hostp_a_fn(): i64 { return 5; }\n' > "$HP/dist/hostp/a.cyr"
printf '[modular]\na = ["lib:../../x"]\n' > "$HP/dist/hostp/index.cyml"
P="$W/l2"; consumer "$P" hostp_a_fn <<EOF
[deps.hostp]
path = "$HP"
modular = ["a"]
EOF
run "$P" deps
if [ "$rc" -eq 1 ] && grep -qxF "error: the modular index of hostp names '../../x', $LEAF_TAIL" "$P.err" && outside_clean; then
    ok "L2 an index entry lib:../../x: refused by the leaf rule's line, rc 1, nothing outside lib/"
else bad "L2 (rc=$rc): $(head -3 "$P.err")"; fi

# ── L3: a sidecar line and a `requires` entry are leaf names too ─────────────────────────
SP="$W/sidep"; mkdir -p "$SP/dist"
printf 'fn sidep_fn(): i64 { return 6; }\n' > "$SP/dist/sidep.cyr"
printf '# sidecar\nstring\n../../w/pwn\n' > "$SP/dist/sidep.deps"
P="$W/l3a"; consumer "$P" sidep_fn <<EOF
[deps.sidep]
path = "$SP"
modules = ["dist/sidep.cyr"]
EOF
run "$P" deps; rca=$rc
P="$W/l3b"; consumer "$P" sidep_fn <<EOF
[deps.sidep]
path = "$SP"
modules = ["dist/sidep.cyr"]
requires = ["../x"]
EOF
run "$P" deps; rcb=$rc
if [ "$rca" -eq 1 ] && grep -qxF "error: dep sidep names '../../w/pwn', $LEAF_TAIL" "$W/l3a.err" \
   && [ "$rcb" -eq 1 ] && grep -qxF "error: dep sidep names '../x', $LEAF_TAIL" "$W/l3b.err" \
   && ! grep -q 'it IS in the stdlib' "$W/l3a.err" "$W/l3b.err" && [ -f "$W/l3a/lib/string.cyr" ] && outside_clean; then
    ok "L3 a sidecar line ../../w/pwn and requires = [\"../x\"]: refused by name, rc 1, no false 'it IS in the stdlib', the good leaf still vendored"
else bad "L3 (rca=$rca rcb=$rcb): $(head -2 "$W/l3a.err") | $(head -2 "$W/l3b.err")"; fi

# ── L4: [deps] stdlib entries are leaves ──────────────────────────────────────────────────
P="$W/l4"; mkdir -p "$P/src"
printf '[package]\nname = "c"\nversion = "0.0.1"\nlanguage = "cyrius"\ncyrius = "%s"\n\n[deps]\nstdlib = ["string", "../x"]\n' "$V" > "$P/cyrius.cyml"
run "$P" deps
if [ "$rc" -eq 1 ] && grep -qxF "error: [deps] stdlib names '../x', $LEAF_TAIL" "$P.err" && [ -f "$P/lib/string.cyr" ] && outside_clean; then
    ok "L4 [deps] stdlib = [\"string\", \"../x\"]: ../x refused by the same line, rc 1; string still vendored"
else bad "L4 (rc=$rc): $(head -2 "$P.err")"; fi

# ── L5: the producer refuses to write an index row the rule would refuse ──────────────────
EP="$W/evilp"; mkdir -p "$EP/src"
printf '[package]\nname = "evilp"\nversion = "0.1.0"\nlanguage = "cyrius"\n\n[lib]\nmodules = ["src/a.cyr"]\n' > "$EP/cyrius.cyml"
printf 'include "lib/../evil.cyr"\nfn evilp_a(): i64 { return 1; }\n' > "$EP/src/a.cyr"
run "$EP" distlib --modular
if [ "$rc" -eq 1 ] && grep -qF "distlib --modular: an include names a stdlib leaf that is not a safe name" "$EP.err" \
   && grep -qF ": ../evil (allowed: [A-Za-z0-9_/-]) — no index written" "$EP.err" && [ ! -f "$EP/dist/evilp/index.cyml" ]; then
    ok "L5 distlib --modular with include \"lib/../evil.cyr\": refused by name, rc 1, no index written"
else bad "L5 (rc=$rc): $(head -2 "$EP.err") idx=[$(cat "$EP/dist/evilp/index.cyml" 2>/dev/null | tail -1)]"; fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
[ "$pass" -ge 5 ] || { echo "FAIL: $G: only $pass axes ran (floor 5)"; exit 1; }
echo "PASS: $G — one leaf rule for the producer and every consumer route; a / leaf resolves, a .. leaf is refused by name"
