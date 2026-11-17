#!/usr/bin/env bash
# Repro: the guide's 6.6.10 "Float builtin results in arithmetic" note says that `==`, `!=`, `<` … on a builtin's
# result "remain INTEGER compares of the bit patterns (so `f64_neg(z) == z` is 0 for z = 0.0, and `f64_neg(a) <
# f64_neg(b)` is wrong for negative values …)". At 6.7.18 both compares are IEEE: `f64_neg(z) == z` is 1 for z = +0.0
# and `f64_neg(1.0) < f64_neg(2.0)` is 0, the same as with the results bound to `: f64` locals (rasayan M0 probe 12,
# trap 11). A reader following the note writes `f64_eq` / `f64_lt` where they are not needed, or distrusts code that
# is right.
# Exits 1 while the defect is present: the compiler gives the IEEE answers AND the guide still carries the note.
# The guide is read from the cyrius checkout beside this repository (CYRIUS_GUIDE=… to point elsewhere; in the
# cyrius repository itself it is docs/guides/cyrius-guide.md).
#
#   bash docs/development/issues/repros/2026-11-16-guide-builtin-result-compare-note-is-stale.sh; echo $?
set -u
root=$(cd "$(dirname "$0")/../../../.." && pwd)
guide=${CYRIUS_GUIDE:-$root/../cyrius/docs/guides/cyrius-guide.md}
[ -f "$guide" ] || { echo "repro: no guide at $guide (set CYRIUS_GUIDE)"; exit 2; }
w=$root/build/upstream-repros/builtin-compare
rm -rf "$w"
mkdir -p "$w"
cat > "$w/c.cyr" <<'CYR'
# The two compares the guide's note describes, on builtin results directly.
fn main(): i64 {
    var z: f64 = 0.0;
    var a: f64 = 1.0;
    var b: f64 = 2.0;
    var eq = 0;
    if (f64_neg(z) == z) { eq = 1; }
    var lt = 0;
    if (f64_neg(a) < f64_neg(b)) { lt = 1; }
    print("f64_neg(+0.0) == +0.0: ", 23);
    fmt_int(eq);
    print(" (IEEE 1, the note says 0); f64_neg(1.0) < f64_neg(2.0): ", 57);
    fmt_int(lt);
    println(" (IEEE 0)");
    if (eq == 1 && lt == 0) { return 1; }
    return 0;
}

var r = main();
sys_exit_group(r);
CYR
cd "$root" || exit 2
cyrius build "$w/c.cyr" "$w/c" > "$w/build.log" 2>&1 || { cat "$w/build.log"; exit 2; }
"$w/c"
ieee=$?
note=0
tr '\n' ' ' < "$guide" | grep -q 'remain INTEGER compares of the bit patterns' && note=1
echo "guide note present: $note ($guide)"
if [ "$ieee" -eq 1 ] && [ "$note" -eq 1 ]; then
    echo "repro: DEFECT PRESENT (the compares are IEEE; the guide says they are integer compares)"
    exit 1
fi
echo "repro: fixed (the note is gone, or the compares changed: re-check the note against the compiler)"
exit 0
