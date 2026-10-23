#!/bin/sh
# the jump-target table overflow bug (v6.3.21) regression: a function exceeding the 1023-entry x86 jump-target
# table MUST hard-error, not silently drop targets (which lets LASE — Load-After-
# Store Elim, CYRIUS_IR=3 — mis-eliminate a load that is live via the unrecorded
# target → wrong codegen). Also asserts the boundary: a function just UNDER the cap
# still compiles. The table + LASE are x86-only.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}   # 6.7.16: CYCC= a mutant's cycc, as the other gates take it
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 77; }
T=$(mktemp) && [ -f "$T" ] || { echo "FAIL: jump_target_cap: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
E=$(mktemp) && [ -f "$E" ] || { echo "FAIL: jump_target_cap: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
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
    echo "FAIL: a >1023-jump-target function compiled — should hard-error (the jump-target table overflow bug)"; exit 1
fi
grep -q '1023 jump targets' "$E" || { echo "FAIL: overflow gave the wrong error:"; cat "$E"; exit 1; }

# Under the cap → must still compile clean (no false positive).
gen 1000 > "$T"
"$CC" < "$T" > /dev/null 2>&1 || { echo "FAIL: a 1000-branch function (under the cap) failed to compile"; exit 1; }

# 6.7.16 — the cap is a fn's OWN targets. A generic instance is emitted inline in the fn whose call reaches it, and its
# targets were merged into that fn's table: one fn calling 300 distinct generics at f64 (about 5 targets each) was
# refused here although it has no branch of its own. An instance's range is opaque to the enclosing fn now
# (`_jt_merge`, `_jir_in`, src/frontend/parse/fn.cyr) and its targets stay its own; the program must run (300).
# Mutant (2026-10-20, CYCC= its cycc): the 6.3.35 merge back -> RED here ("1023 jump targets"). On every host:
# tests/tcyr/crossos/generic_forward_chain_deep.tcyr (W).
genw() { # <n distinct generics, each called once from main at f64>
    i=0; while [ "$i" -lt "$1" ]; do echo "fn w$i<T>(x: T): i64 { if (sizeof(T) == 8) { return 1; } return 0; }"; i=$((i + 1)); done
    echo 'fn main(): i64 {'
    echo '  var h: f64 = 1.5;'
    echo '  var s = 0;'
    i=0; while [ "$i" -lt "$1" ]; do echo "  s = s + w$i(h);"; i=$((i + 1)); done
    echo '  return s - 250;'
    echo '}'
}
genw 300 > "$T"
"$CC" < "$T" > "$T.bin" 2> "$E" || { echo "FAIL: one fn instantiating 300 generics was refused: $(grep -m1 error "$E")"; rm -f "$T.bin"; exit 1; }
chmod +x "$T.bin"
rc=0; "$T.bin" || rc=$?
rm -f "$T.bin"
[ "$rc" -eq 50 ] || { echo "FAIL: one fn instantiating 300 generics exited $rc, want 50"; exit 1; }

echo "PASS: >1023 jump targets hard-errors, 1000 compiles (the jump-target table overflow bug); 300 generic instances inside one fn are not its targets (6.7.16)"
