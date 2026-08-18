#!/usr/bin/env bash
# Repro: a `[deps].stdlib` entry first reached TRANSITIVELY never gets its
# top-level `include` prepended — the file lands in lib/, the symbols do not.
#
# Two builds. IDENTICAL declared module set. Only the ORDER differs.
#   CASE A: stdlib = [..., "async", "chrono"]   -> undefined clock_now_ns, NO binary
#   CASE B: stdlib = [..., "chrono", "async"]   -> builds
#
# Usage: ./2026-08-17-stdlib-transitive-pull-drops-top-level-include.sh [cycc-version]
# Default version is 6.5.27. Pass 6.5.25 to see it pass (pre-regression).
set -u
V="${1:-6.5.27}"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/src" "$D/build"

cat > "$D/src/main.cyr" <<'EOF'
fn main(): i64 {
    return clock_now_ns();
}
var r = main();
syscall(60, 0);
EOF

case_run() {
    local label="$1" order="$2"
    cat > "$D/cyrius.cyml" <<EOF
[package]
name = "chronorepro"
version = "0.1.0"
language = "cyrius"
cyrius = "$V"

[build]
entry = "src/main.cyr"
output = "build/chronorepro"

[deps]
stdlib = [$order]
EOF
    rm -rf "$D/lib" "$D/build"; mkdir -p "$D/build"
    local out
    out=$(cd "$D" && CYRIUS_NO_WARN_SHADOW_LIB=1 cyrius build src/main.cyr build/chronorepro 2>&1)
    echo "$label  stdlib = [$order]"
    echo "    lib/chrono.cyr vendored : $([ -f "$D/lib/chrono.cyr" ] && echo YES || echo NO)"
    echo "    'undefined clock_now_ns': $(printf '%s' "$out" | grep -c "undefined function 'clock_now_ns'")"
    echo "    binary emitted          : $([ -f "$D/build/chronorepro" ] && echo YES || echo NO)"
}

echo "=== cycc $V ==="
case_run "CASE A (async before chrono)" '"syscalls", "alloc", "async", "chrono"'
echo
case_run "CASE B (chrono before async)" '"syscalls", "alloc", "chrono", "async"'
