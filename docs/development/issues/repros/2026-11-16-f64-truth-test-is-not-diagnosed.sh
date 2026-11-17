#!/usr/bin/env bash
# Repro: `if (x)` and `!x` on an f64 compile with no diagnostic and test the raw bits, so −0.0 (0x8000000000000000) is
# true and `!(-0.0)` is 0, where `x != 0.0` is false for both zeros. Every other f64/integer mix the f64 hygiene
# warnings cover is diagnosed at 6.7.18 (rasayan M0 probe 12, traps 1–6).
# Exits 1 while the defect is present: the build is warning-free AND the truth tests take the bit-pattern branch.
#
#   bash docs/development/issues/repros/2026-11-16-f64-truth-test-is-not-diagnosed.sh; echo $?   # from the repo root
set -u
root=$(cd "$(dirname "$0")/../../../.." && pwd)
w=$root/build/upstream-repros/f64-truth-test
rm -rf "$w"
mkdir -p "$w"
cat > "$w/t.cyr" <<'CYR'
# The truth of a typed f64 parameter, and its negation.
fn truth(x: f64): i64 {
    if (x) { return 1; }
    return 0;
}

fn negation(x: f64): i64 {
    if (!x) { return 1; }
    return 0;
}

fn main(): i64 {
    var z: f64 = 0.0;
    var nz: f64 = -z;
    var eq = 0;
    if (nz == 0.0) { eq = 1; }
    # IEEE: -0.0 == 0.0, so a numeric truth test would give truth 0 and negation 1 for -0.0.
    var t = truth(nz);
    var n = negation(nz);
    print("-0.0 == 0.0: ", 13);
    fmt_int(eq);
    print(", if (-0.0): ", 13);
    fmt_int(t);
    print(", if (!-0.0): ", 14);
    fmt_int(n);
    println("");
    if (t == 1 && n == 0) { return 1; }
    return 0;
}

var r = main();
sys_exit_group(r);
CYR
cd "$root" || exit 2
build=$(cyrius build "$w/t.cyr" "$w/t" 2>&1)
rc=$?
[ "$rc" -eq 0 ] || { printf '%s\n' "$build"; echo "repro: the build failed (rc $rc)"; exit 2; }
diag=$(printf '%s\n' "$build" | grep -v -E '^\s*lib/|rm <file>|footprint|^note' | grep -c -i -E 'warning|error')
"$w/t"
bits=$?
echo "diagnostics on the truth tests: $diag"
if [ "$diag" -eq 0 ] && [ "$bits" -eq 1 ]; then
    echo "repro: DEFECT PRESENT (an f64 truth test compiles silently and tests the bits)"
    exit 1
fi
echo "repro: fixed (diagnosed, or the test is numeric)"
exit 0
