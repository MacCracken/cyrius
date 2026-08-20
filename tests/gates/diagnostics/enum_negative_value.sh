#!/bin/sh
# v6.5.32 — a negative enum value is ACCEPTED, and rejected only where it cannot mean anything.
#
# ⛔ `enum E { B = -1; }` was `error: expected number, got '-'`, and `B = 0 - 1` is an
# expression an enum body will not take either — so a negative constant could not be spelled
# at all. Sentinels (-1 for "none", negative errno families) are ordinary. v6.5.31 recorded
# this as a language limitation instead of fixing it, in the repo that owns the parser.
#
# ⚠ WHY A GATE AND NOT ONLY A .tcyr. Two of the three behaviours here are COMPILE FAILURES —
# a test that must not build, and a diagnostic that must name the reason. A .tcyr can only
# assert on a program that runs, so the value semantics live in
# `tests/tcyr/crossos/enum_negative_values.tcyr` and the rejection lives here.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
cd "$ROOT"
T=$(mktemp --suffix=.cyr); O=$(mktemp); E=$(mktemp)
trap 'rm -f "$T" "$O" "$E"' EXIT
fail=0
build() { rc=0; "$CC" < "$T" > "$O" 2>"$E" || rc=$?; }

# --- axis 1: a negative enum value COMPILES ---
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
enum E { NONE = -1; ZERO = 0; }
fn main(): i64 { if (NONE < ZERO) { return 0; } return 9; }
var e = main();
syscall(60, e);
EOF
build
if [ "$rc" -ne 0 ]; then
    echo "  FAIL axis 1: 'enum E { NONE = -1; }' does not compile"
    grep -m1 '^error' "$E" | sed 's/^/      /' || true
    fail=1
else
    chmod +x "$O" 2>/dev/null || true
    erc=0; "$O" >/dev/null 2>&1 || erc=$?
    if [ "$erc" -ne 0 ]; then
        echo "  FAIL axis 1: compiled but -1 did not compare less than 0 (exit $erc) — the fold table is masking the sign"
        fail=1
    else
        echo "  ok axis 1: a negative enum value compiles and keeps its sign"
    fi
fi

# --- axis 2: a negative enum used as an ARRAY SIZE is a hard error, naming the reason ---
# Making negatives spellable made this reachable for the first time. Silent acceptance of a
# nonsensical size is exactly the failure mode this release line keeps removing.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
enum Sz { NEG = -8; }
fn main(): i64 { var buf[NEG]; return 0; }
var e = main();
syscall(60, e);
EOF
build
if [ "$rc" -eq 0 ]; then
    echo "  FAIL axis 2: a LOCAL array sized by a negative enum constant compiled rc=0"
    fail=1
elif grep -q "must not be negative" "$E"; then
    echo "  ok axis 2: a local negative array size is rejected and says why"
else
    echo "  FAIL axis 2: rejected, but not for the stated reason: $(head -c 140 "$E")"
    fail=1
fi

# --- axis 3: the same at TOP LEVEL — a separate code path with its own copy of the check ---
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
enum Sz2 { NEG = -8; }
var gbuf[NEG];
syscall(60, 0);
EOF
build
if [ "$rc" -eq 0 ]; then
    echo "  FAIL axis 3: a GLOBAL array sized by a negative enum constant compiled rc=0"
    fail=1
elif grep -q "must not be negative" "$E"; then
    echo "  ok axis 3: a global negative array size is rejected too"
else
    echo "  FAIL axis 3: rejected, but not for the stated reason: $(head -c 140 "$E")"
    fail=1
fi

# --- axis 4 (ANTI-VACUOUS): a POSITIVE enum array size must still work ---
# Axes 2-3 assert rejections; a check that rejected every enum-sized array would satisfy both
# while breaking the documented `enum Sz { N = 16; } var buf[N];` idiom outright.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
enum Ok2 { N = 16; }
fn main(): i64 { var buf[N]; store64(&buf, 7); return load64(&buf); }
var e = main();
syscall(60, e);
EOF
build
if [ "$rc" -ne 0 ]; then
    echo "  FAIL axis 4 (anti-vacuous): a POSITIVE enum array size stopped working"
    grep -m1 '^error' "$E" | sed 's/^/      /' || true
    fail=1
else
    chmod +x "$O" 2>/dev/null || true
    erc=0; "$O" >/dev/null 2>&1 || erc=$?
    if [ "$erc" -ne 7 ]; then
        echo "  FAIL axis 4 (anti-vacuous): positive enum-sized array ran wrong (exit $erc, expected 7)"
        fail=1
    else
        echo "  ok axis 4: a positive enum array size still works"
    fi
fi

# --- axis 5 (STRUCTURAL): every enum_const_val reader goes through the shared decoder ---
# There were FIVE hand-rolled `& 0x7FFFFFFFFFFFFFFF` copies across three files. Fixing four of
# them would have been this cycle's `_cfo` lesson a third time, so this fails if any site
# re-grows its own mask.
raw=$(grep -c '_vecv_base' src/frontend/parse_types.cyr src/frontend/parse_decl.cyr src/frontend/parse_expr.cyr | awk -F: '{s+=$2} END{print s}')
dec=$(grep -c 'ENUM_CONST_VAL(' src/frontend/parse_types.cyr src/frontend/parse_decl.cyr src/frontend/parse_expr.cyr | awk -F: '{s+=$2} END{print s}')
if [ "$raw" -lt 5 ]; then
    echo "  FAIL axis 5 (premise): only $raw _vecv_base sites found — the search is wrong, not the tree"
    fail=1
elif [ "$dec" -lt 5 ]; then
    echo "  FAIL axis 5 (structural): $raw enum_const_val sites but only $dec route through ENUM_CONST_VAL — a hand-rolled mask has been reintroduced, and it will silently corrupt negative values"
    fail=1
else
    echo "  ok axis 5: all $dec enum_const_val readers route through the shared decoder"
fi

[ "$fail" -eq 0 ] || { echo "FAIL: enum-negative-value"; exit 1; }
echo "PASS: enum-negative-value — negative enum values work, negative array sizes are rejected, one shared decoder"
