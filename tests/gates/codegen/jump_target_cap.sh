#!/bin/sh
# CVE-09 (v6.3.21) regression: a function exceeding the 1023-entry x86 jump-target
# table MUST hard-error, not silently drop targets (which lets LASE — Load-After-
# Store Elim, CYRIUS_IR=3 — mis-eliminate a load that is live via the unrecorded
# target → wrong codegen). Also asserts the boundary: a function just UNDER the cap
# still compiles. The table + LASE are x86-only.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
T=$(mktemp); E=$(mktemp)
trap 'rm -f "$T" "$E"' EXIT

gen() { # <n-branches>
    echo 'fn main(): i64 {'
    echo '  var x = 0;'
    i=0; while [ "$i" -lt "$1" ]; do echo "  if (x == $i) { x = x + 1; }"; i=$((i + 1)); done
    echo '  return x;'
    echo '}'
}

# >1023 jump targets → must hard-error (non-zero) with the cap message.
gen 1100 > "$T"
if "$CC" < "$T" > /dev/null 2>"$E"; then
    echo "FAIL: a >1023-jump-target function compiled — should hard-error (CVE-09)"; exit 1
fi
grep -q '1023 jump targets' "$E" || { echo "FAIL: overflow gave the wrong error:"; cat "$E"; exit 1; }

# Under the cap → must still compile clean (no false positive).
gen 1000 > "$T"
"$CC" < "$T" > /dev/null 2>&1 || { echo "FAIL: a 1000-branch function (under the cap) failed to compile"; exit 1; }

echo "PASS: >1023 jump targets hard-errors, 1000 compiles (CVE-09)"
