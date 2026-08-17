#!/bin/sh
# v6.5.25 — `cyrius deps` must resolve a dep's sidecar stdlib leaves out of the PINNED
# SNAPSHOT, not out of the consumer's own half-populated `./lib`.
#
# THE BUG (filed from bote CI; also agnosai and majra). `_dep_find_stdlib_dir()`'s
# "am I the cyrius source repo?" branch tested `file_exists("src/main.cyr")` — which is TRUE
# for essentially every cyrius project, since `src/main.cyr` is the default entry the init
# templates generate. So for a downstream repo that branch fired, found the consumer's OWN
# `./lib` (the `[deps].stdlib` phase has already copied into it by that point), and returned
# it AS "the stdlib". The version-pinned snapshot was never consulted. Any sidecar leaf not
# already in `./lib` therefore looked absent, and `cyrius deps` reported
#   error: dep libro requires 'bench' but it is not in the cyrius stdlib
# about a module that ships in the stdlib — pointing maintainers at deleting a correct
# `[deps].stdlib` declaration.
#
# ⭐ IT WAS A FUNCTIONAL FAILURE, NOT A DIAGNOSTIC ONE. It was filed as a misleading
# message and a first pass "fixed" it by rewriting the message — which left the resolve
# still broken and merely reworded the false claim. Measured on the real bote tree: 3 errors
# before (bench, test via libro; patra via majra), 0 after, with all three leaves copied in.
# The message was the symptom; the wrong directory was the bug.
#
# ⚠ Same `file_exists("src/main.cyr")` ≠ cyrius-repo conflation that was fixed in
# `cyrius audit` at v6.4.63 and originally at v6.0.1. `_dep_is_cyrius_source_repo()` exists
# for exactly this and matches `[package].name` exactly. Third occurrence of this shape.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
command -v cyrius >/dev/null 2>&1 || { echo "SKIP: cyrius CLI not on PATH"; exit 0; }
PIN=$(cat "$ROOT/VERSION")
SNAP="$HOME/.cyrius/versions/$PIN/lib"
[ -d "$SNAP" ] || { echo "SKIP: pinned snapshot $SNAP not installed"; exit 0; }
# Two real stdlib leaves that the filing itself names.
for m in bench test; do
    [ -f "$SNAP/$m.cyr" ] || { echo "SKIP: $SNAP/$m.cyr absent — cannot test snapshot resolution"; exit 0; }
done
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fail=0

# --- fixture: a dep package carrying a dist/<pkg>.deps sidecar naming stdlib leaves ---
# git+path+tag+modules is the real downstream shape (bote's [deps.libro]); the local `path`
# means the resolve never touches the network.
mkdir -p "$W/fakedep/dist"
printf 'fn fakedep_marker(): i64 { return 1; }\n' > "$W/fakedep/dist/fakedep.cyr"
printf '# cyrius dep sidecar\nbench\ntest\n'      > "$W/fakedep/dist/fakedep.deps"
cat > "$W/fakedep/cyrius.cyml" <<EOF
[package]
name = "fakedep"
version = "1.0.0"
language = "cyrius"
EOF

# --- fixture: the CONSUMER. Has src/main.cyr (the old false positive) and is NOT cyrius. ---
#
# ⛔ THE `[deps].stdlib` LIST BELOW IS LOAD-BEARING, AND ITS ABSENCE MADE THE FIRST VERSION
# OF THIS GATE VACUOUS — it passed against the pre-fix CLI, caught only by mutation-testing.
# The old `file_exists("src/main.cyr")` branch only does damage once `./lib` ALREADY looks
# like a stdlib: `_dep_dir_has_stdlib("./lib")` has to return 1 for the branch to return
# "./lib". With an empty `./lib` (the first fixture) it returned 0, the old code fell through
# to the pinned snapshot on its own, and the bug never reproduced.
#
# So the fixture must mirror the real bote shape: a `[deps].stdlib` list that the earlier
# resolve phase copies into `./lib`, making it *look* like a stdlib, and a sidecar naming
# DIFFERENT leaves. Anti-vacuity survives because `bench` and `test` are deliberately NOT in
# this list (axis 4 enforces that), so they can only arrive via the sidecar.
mkdir -p "$W/consumer/src" "$W/consumer/lib"
printf 'fn main(): i64 { return 0; }\n' > "$W/consumer/src/main.cyr"
cat > "$W/consumer/cyrius.cyml" <<EOF
[package]
name = "consumer"
version = "0.1.0"
language = "cyrius"
cyrius = "$PIN"

[build]
entry = "src/main.cyr"
output = "build/consumer"

[deps]
stdlib = ["syscalls", "string", "alloc", "vec", "str", "io", "fmt"]

[deps.fakedep]
git = "https://example.invalid/fakedep"
path = "../fakedep"
tag = "1.0.0"
modules = ["dist/fakedep.cyr"]
EOF

OUT="$W/deps.out"
( cd "$W/consumer" && cyrius deps ) > "$OUT" 2>&1 || true

# --- axis 1: the sidecar leaves must actually land in ./lib ---
missing=""
for m in bench test; do
    [ -f "$W/consumer/lib/$m.cyr" ] || missing="$missing $m"
done
if [ -n "$missing" ]; then
    echo "  FAIL axis 1: sidecar stdlib leaves not resolved into ./lib:$missing"
    sed 's/^/      /' "$OUT" | head -8
    fail=1
else
    echo "  ok axis 1: sidecar leaves (bench, test) resolved out of the pinned snapshot into ./lib"
fi

# --- axis 2: the false "not in the cyrius stdlib" claim must be GONE ---
if grep -q "not in the cyrius stdlib" "$OUT"; then
    echo "  FAIL axis 2: still claims a real stdlib module 'is not in the cyrius stdlib'"
    grep "not in the cyrius stdlib" "$OUT" | sed 's/^/      /' | head -3
    fail=1
else
    echo "  ok axis 2: no false 'not in the cyrius stdlib' claim"
fi

# --- axis 3: the resolve must report no errors ---
if grep -qE "[1-9][0-9]* errors?" "$OUT"; then
    echo "  FAIL axis 3: cyrius deps reported errors on a resolvable tree"
    grep -E "[1-9][0-9]* errors?" "$OUT" | sed 's/^/      /' | head -3
    fail=1
else
    echo "  ok axis 3: resolve reports no errors"
fi

# --- axis 4 (ANTI-VACUOUS, two halves) ---
# (a) The tested leaves must NOT be in [deps].stdlib, or they would arrive by the ordinary
#     path and the sidecar would not be under test at all.
# (b) [deps].stdlib must be NON-EMPTY, because that is what populates ./lib and makes it
#     look like a stdlib — the precondition the whole bug needs. Without it this gate passes
#     against the pre-fix CLI, which is precisely how its first version shipped vacuous.
if grep -qE '^stdlib.*"(bench|test)"' "$W/consumer/cyrius.cyml"; then
    echo "  FAIL axis 4a (anti-vacuous): the tested leaves are declared in [deps].stdlib, so the sidecar path is not under test"
    fail=1
elif ! grep -q '^stdlib = \[' "$W/consumer/cyrius.cyml"; then
    echo "  FAIL axis 4b (anti-vacuous): fixture has no [deps].stdlib, so ./lib never looks like a stdlib and the bug cannot reproduce"
    fail=1
elif [ "$(ls "$W/consumer/lib" | wc -l)" -lt 3 ]; then
    echo "  FAIL axis 4b (anti-vacuous): ./lib was not populated by the [deps].stdlib phase, so _dep_dir_has_stdlib(./lib) never becomes true"
    fail=1
else
    echo "  ok axis 4: leaves absent from [deps].stdlib (sidecar-only) AND ./lib was pre-populated ($(ls "$W/consumer/lib" | wc -l) files), so the bug's precondition holds"
fi

# --- axis 5: the cyrius source repo itself must STILL use its own ./lib ---
# The fix narrows branch (a); it must not narrow it out of existence, or dev-mode
# resolution in this very repo would start reading a snapshot instead of the working tree.
if grep -qE '^name[[:space:]]*=[[:space:]]*"cyrius"' "$ROOT/cyrius.cyml"; then
    echo "  ok axis 5: this repo declares [package].name = \"cyrius\", so branch (a) still applies here"
else
    echo "  FAIL axis 5: this repo no longer identifies as name = \"cyrius\" — _dep_is_cyrius_source_repo() would reject it and dev-mode resolution would break"
    fail=1
fi

[ "$fail" -eq 0 ] || { echo "FAIL: deps-stdlib-dir-not-consumer-lib"; exit 1; }
echo "PASS: deps-stdlib-dir-not-consumer-lib — sidecar leaves resolve from the pinned snapshot; downstream repos with src/main.cyr are no longer mistaken for the cyrius repo"
