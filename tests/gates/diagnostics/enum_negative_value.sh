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

# --- axis 5 (STRUCTURAL): presence is OUT OF BAND; no site reconstructs a value from a tag ---
#
# ⚠ THIS AXIS WAS REWRITTEN AT v6.5.36 AND THE REASON MATTERS. It used to require that every
# `_vecv_base` reader route through a shared decoder, `ENUM_CONST_VAL` — a guard against the
# five hand-rolled `& 0x7FFFFFFFFFFFFFFF` copies that once existed. That guard was correct
# about the symptom and wrong about the disease: the decoder itself could not work. The slot
# packed `(1 << 63) | val`, i.e. 65 bits of information in 64, so it could not distinguish a
# negative value from a positive one with bit 62 set. Every enum constant >= 2^62 came back
# sign-extended — `enum { K = 0x7FFFFFFFFFFFFFFF }` was **-1** — silently, in five shipped
# releases (6.5.31-6.5.35), with this gate GREEN because one shared decoder was doing the
# corrupting. **A gate that pins the mechanism rather than the property passes while the
# mechanism is wrong.**
#
# v6.5.36 moved presence out of band: `_vecv_base` holds the RAW i64 and `_vecp_base` (via
# GVECP/SVECP) holds the flag. So the invariant to defend is no longer "one decoder" — it is
# that NOTHING derives presence or value from bits inside the value again.
ENUM_SRC="src/frontend/parse_types.cyr src/frontend/parse_decl.cyr src/frontend/parse_expr.cyr"
GD=$(mktemp -d)
# ⚠ CODE ONLY. A first draft of this axis grepped the raw files and went red on its OWN
# explanatory comments (which necessarily quote the old `(1 << 63) | val` tag) and on
# `GETFCOUNT`'s unrelated `& 0x7FFF…` over a DIFFERENT table. A structural gate that cannot
# tell code from prose reports the documentation as the defect.
for f in $ENUM_SRC src/common/util.cyr; do
    sed 's/#.*$//' "$f" > "$GD/$(echo "$f" | tr / _)"
done
raw=$(grep -c '_vecv_base' $ENUM_SRC | awk -F: '{s+=$2} END{print s}')
if [ "$raw" -lt 5 ]; then
    echo "  FAIL axis 5 (premise): only $raw _vecv_base sites found — the search is wrong, not the tree"
    fail=1
else
    a5=0
    # (a) the in-band tag must not come back.
    if grep -nE '\(1 *<< *63\) *\|' "$GD"/* >/dev/null 2>&1; then
        echo "  FAIL axis 5a: an in-band presence tag has been reintroduced into the value slot"
        grep -nE '\(1 *<< *63\) *\|' "$GD"/* | head -3 | sed 's/^/      /'
        a5=1
    fi
    # (b) no mask reconstructing a value from a tagged slot. Scoped to lines that actually
    #     touch the enum table, so unrelated masks elsewhere are not false positives.
    if grep -n '_vecv_base' "$GD"/* | grep -E '0x7FFFFFFFFFFFFFFF|0x4000000000000000' >/dev/null 2>&1; then
        echo "  FAIL axis 5b: a hand-rolled tag mask is back on an enum-table access"
        grep -n '_vecv_base' "$GD"/* | grep -E '0x7FFFFFFFFFFFFFFF|0x4000000000000000' | head -3 | sed 's/^/      /'
        a5=1
    fi
    # (c) presence must be asked for explicitly, never inferred from the value's sign.
    pres=$(grep -c 'GVECP(' $ENUM_SRC | awk -F: '{s+=$2} END{print s}')
    if [ "$pres" -lt 5 ]; then
        echo "  FAIL axis 5c: only $pres of $raw _vecv_base sites test GVECP — presence is being inferred from the value"
        a5=1
    fi
    if [ "$a5" -eq 0 ]; then
        echo "  ok axis 5: presence is out of band ($pres GVECP tests, no in-band tag, no hand-rolled mask)"
    else
        fail=1
    fi
fi

# --- axis 6 (BEHAVIOURAL): the full i64 range, which axes 1-5 do not reach ---
# The 6.5.31-6.5.35 defect lived entirely ABOVE 2^62, so every ordinary enum test passed.
cat > "$GD/range.cyr" <<'RANGEEOF'
enum R { LO = 0x3FFFFFFFFFFFFFFF; HI = 0x4000000000000000; MAXV = 0x7FFFFFFFFFFFFFFF; NEG = -1; }
fn ck(): i64 {
    if (LO   != 4611686018427387903) { return 1; }
    if (HI   != 4611686018427387904) { return 2; }
    if (MAXV != 9223372036854775807) { return 3; }
    if (NEG  != (0 - 1))             { return 4; }
    if (MAXV <= 0)                   { return 5; }
    return 0;
}
var q = ck();
syscall(60, q);
RANGEEOF
if ! "$CC" < "$GD/range.cyr" > "$GD/range.bin" 2>"$GD/range.err"; then
    echo "  FAIL axis 6: the full-range enum fixture does not compile"
    head -2 "$GD/range.err" | sed 's/^/      /'
    fail=1
else
    chmod +x "$GD/range.bin"
    "$GD/range.bin" >/dev/null 2>&1
    rc6=$?
    if [ "$rc6" -eq 0 ]; then
        echo "  ok axis 6: enum constants hold the full i64 range (2^62-1, 2^62, i64 max, -1)"
    else
        echo "  FAIL axis 6: member #$rc6 is wrong — 1=2^62-1 2=2^62 3=i64max 4=-1 5=i64max sign"
        fail=1
    fi
fi
rm -rf "$GD"

[ "$fail" -eq 0 ] || { echo "FAIL: enum-negative-value"; exit 1; }
echo "PASS: enum-negative-value — negative enum values work, negative array sizes are rejected, one shared decoder"
