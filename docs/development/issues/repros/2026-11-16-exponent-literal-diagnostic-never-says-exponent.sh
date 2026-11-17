#!/usr/bin/env bash
# Repro: an exponent literal (`1e-14`, `1.5e3`), which the guide says Cyrius does not have ("no exponent form (`1e-9`):
# spell small constants out"), is refused with diagnostics that never say so: `1e-14` first draws "an integer stored
# into an f64/f32 slot keeps its integer bits (write a float literal)" on the `1`, then "expected ';', got identifier
# 'e'"; `1.5e3` gives "expected ';', got identifier 'e3'".
# Exits 1 while the defect is present: the build fails and no diagnostic names the exponent form.
#
#   bash docs/development/issues/repros/2026-11-16-exponent-literal-diagnostic-never-says-exponent.sh; echo $?
set -u
root=$(cd "$(dirname "$0")/../../../.." && pwd)
w=$root/build/upstream-repros/e-literal
rm -rf "$w"
mkdir -p "$w"
cat > "$w/e.cyr" <<'CYR'
fn main(): i64 {
    var tol: f64 = 1e-14;
    var big: f64 = 1.5e3;
    return 0;
}

var r = main();
sys_exit_group(r);
CYR
cd "$root" || exit 2
out=$(cyrius build "$w/e.cyr" "$w/e" 2>&1)
rc=$?
diag=$(printf "%s\n" "$out" | grep -o -E "(warning|error):<source>.*")
printf '%s\n' "$diag"
if [ "$rc" -eq 0 ]; then
    echo "repro: the exponent literals compiled (exponent notation is supported now: check the values)"
    exit 0
fi
if printf '%s\n' "$diag" | grep -q -i 'exponent'; then
    echo "repro: fixed (a diagnostic names the exponent form)"
    exit 0
fi
echo "repro: DEFECT PRESENT (refused, but no diagnostic says exponent notation is unsupported)"
exit 1
