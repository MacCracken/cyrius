#!/usr/bin/env bash
# Repro: `f()?;` on a #must_use function that returns a Result warns "#must_use result of 'f' is discarded", although
# `?` consumes the result: it propagates the Err (tag and payload) and continues on Ok. The program below proves the
# propagation is right at run time, so the warning is a false positive on correct code.
# Exits 1 while the defect is present: the build warns about the discarded result AND the propagation is correct.
#
#   bash docs/development/issues/repros/2026-11-16-must-use-warns-on-question-mark-propagation.sh; echo $?   # from the repo root
set -u
root=$(cd "$(dirname "$0")/../../../.." && pwd)
w=$root/build/upstream-repros/must-use-question-mark
rm -rf "$w"
mkdir -p "$w"
cat > "$w/t.cyr" <<'CYR'
include "lib/result.cyr"

# Refuses a negative x with Err(7).
#must_use
fn check(x): Result {
    if (x < 0) { return Err(7); }
    return Ok(0);
}

# check(x)?, then Ok(x + 1): Rust's `check(x)?; Ok(x + 1)`.
fn outer(x): Result {
    check(x)?;
    return Ok(x + 1);
}

fn main(): i64 {
    var t, v = outer(0 - 5);
    var t2, v2 = outer(3);
    if (is_err_result(t) == 1 && v == 7 && is_ok(t2) == 1 && v2 == 4) { return 0; }
    return 1;
}
var rc = main();
sys_exit_group(rc);
CYR
cd "$root" || exit 2
out=$(cyrius build "$w/t.cyr" "$w/t" 2>&1)
warned=$(printf '%s\n' "$out" | grep -c "#must_use result of 'check' is discarded")
if [ ! -x "$w/t" ]; then
    printf '%s\n' "$out"
    echo "repro: the program did not build"
    exit 2
fi
"$w/t"
right=$?
echo "warnings on check(x)?: $warned; propagation correct at run time: $([ "$right" -eq 0 ] && echo yes || echo no)"
if [ "$warned" -ge 1 ] && [ "$right" -eq 0 ]; then
    echo "repro: DEFECT PRESENT (the ? consumes the #must_use result, and the build still says it is discarded)"
    exit 1
fi
if [ "$right" -ne 0 ]; then
    echo "repro: the propagation itself is wrong (a different defect)"
    exit 2
fi
echo "repro: fixed (no warning, propagation correct)"
exit 0
