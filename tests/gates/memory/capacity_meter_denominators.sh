#!/bin/sh
# Gate: every denominator the capacity meter prints equals the cap actually ENFORCED (v6.5.40).
#
# THE DEFECT CLASS — three occurrences, in this one block, at three different times:
#   * `code_size` reported against a stale 1 MiB until v6.4.73. A healthy stiva 3.0.6 build
#     printed `code_size: 2822736 / 1048576` — **269 %** — and `cyrius capacity --json`
#     published that ratio to anything consuming it.
#   * `identifiers` reported against a stale 524288 until v6.5.40, after the pool grew to 8 MB.
#     CI caught it printing `identifiers: 200751 / 524288` while `_capacity_warnings` had
#     already been updated to 8388608 — the two user-facing numbers disagreed with each other.
#   * `var_table` reported against 8192, which is the INITIAL `_var_cap`, not the ceiling.
#     `_var_grow` doubles it and refuses only past 1048576, so the meter over-reported
#     utilization by up to 128x: a project with 20,000 globals read as 244 % while being fine.
#     Latent — nothing had raised a var-heavy build against it.
#
# ⭐ WHY A GATE AND NOT A CAREFUL EDIT. Every one of these is a hand-maintained duplicate of a
# fact the compiler already enforces elsewhere, printed to users as a percentage. The same
# shape this cycle keeps finding wrong (heap-map sizes vs regions, gate counts vs files,
# declared string lengths vs strings, the TLS slot window vs TLOCAL_MAX_SLOTS). A one-off
# correction of a self-drifting value is not a fix — the third occurrence proved that.
#
# ⚠ A WRONG DENOMINATOR IS WORSE THAN A MISSING METER. It reads as authoritative, and both
# directions cause harm: too small tells a healthy project it is at 269 % and provokes a
# pointless refactor; too large hides a real approach to a hard limit until the build fails.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
fail() { echo "FAIL: capacity_meter_denominators: $1"; exit 1; }
num() { grep -oE "$2" "$ROOT/$1" | grep -oE '[0-9]+' | tail -1; }

# ── the caps as ENFORCED, each read from the site that raises the hard error ────────
CAP_FN=$(num      src/frontend/parse_fn.cyr  'if \(nc > [0-9]+\)')
GUARD_ID=$(num    src/frontend/lex.cyr       'if \(npos >= [0-9]+\)')
CAP_VAR=$(num     src/common/util.cyr        'if \(_var_cap \* 2 > [0-9]+\)')
CAP_FIX=$(num     src/frontend/parse_expr.cyr 'fixup table full \([0-9]+\)')
CAP_STR=$(num     src/frontend/lex.cyr       'if \(spos >= [0-9]+\)')
# ⚠ NOT via num(): `_capacity_warnings(S, 67108864, 1)` contains TWO numbers and num()'s
# `tail -1` picks the trailing `1`, silently deriving a cap of 1. Take the first argument.
CAP_CODE=$(grep -oE '_capacity_warnings\(S, [0-9]+, 1\)' "$ROOT/src/main.cyr" \
           | sed -E 's/.*\(S, ([0-9]+), 1\)/\1/' | head -1)
# The identifier GUARD trips 272 bytes early (LEXID inner-loop slack), so the reportable
# pool size is guard + 272. Derived, not transcribed.
CAP_ID=$(( GUARD_ID + 272 ))

for pair in "fn:$CAP_FN" "id:$CAP_ID" "var:$CAP_VAR" "fix:$CAP_FIX" "str:$CAP_STR" "code:$CAP_CODE"; do
    v=${pair#*:}
    [ -n "$v" ] && [ "$v" -gt 0 ] 2>/dev/null \
        || fail "could not derive the ${pair%%:*} cap from its enforcement site — the gate is blind, not the meter correct"
done

# ── axis 1: the meter's printed denominators ───────────────────────────────────────
# Extracted positionally from the CYRIUS_STATS block, in the order it prints them.
# ⚠ Anchored on the emitted STRING LITERALS (`" / N\n"`), not on a sed line-range: a comment
# in this very block mentions 67108864 while explaining the v6.4.73 fix, and a range ending at
# /67108864/ stops on the COMMENT and silently drops the real code_size denominator. (It did
# exactly that on this gate's first run — reporting 5 of 6.)
STATS=$(awk '/cyrius stats:/{f=1} f' "$ROOT/src/main.cyr" | grep -oE '"[[:space:]]/[[:space:]][0-9]+' | grep -oE '[0-9]+' | head -6)
set -- $STATS
[ "$#" -eq 6 ] || fail "axis 1: expected 6 denominators in the CYRIUS_STATS block, found $# — the block changed shape and this gate can no longer read it"
M_FN=$1; M_ID=$2; M_VAR=$3; M_FIX=$4; M_STR=$5; M_CODE=$6

chk() {  # chk <label> <meter> <enforced>
    [ "$2" = "$3" ] || fail "axis 1: the meter prints $1 against $2 but the enforced cap is $3 — users are shown a percentage computed from the wrong denominator"
}
chk fn_table    "$M_FN"   "$CAP_FN"
chk identifiers "$M_ID"   "$CAP_ID"
chk var_table   "$M_VAR"  "$CAP_VAR"
chk fixup_table "$M_FIX"  "$CAP_FIX"
chk string_data "$M_STR"  "$CAP_STR"
chk code_size   "$M_CODE" "$CAP_CODE"

# ── axis 2: _capacity_warnings must agree with the meter ───────────────────────────
# Two independent hand-maintained copies of the same six facts. They DID disagree at 6.5.40 —
# the warning had been updated to the new pool and the meter had not — so a build could warn
# "identifier buffer at 87%" while the meter serenely reported 2%.
W=$(grep -oE 'GFNC\(S\) \* 100 / [0-9]+|GNPOS\(S\) \* 100 / [0-9]+|GVCNT\(S\) \* 100 / [0-9]+|GFCNT\(S\) \* 100 / [0-9]+|GSPOS\(S\) \* 100 / [0-9]+' "$ROOT/src/common/util.cyr" \
     | grep -oE '[0-9]+$' | awk '!seen[NR%2]++ || 1' | awk 'NR%2==1')
set -- $W
[ "$#" -ge 5 ] || fail "axis 2: expected 5 _capacity_warnings denominators, found $#"
chkw() { [ "$2" = "$3" ] || fail "axis 2: _capacity_warnings uses $2 for $1 but the meter prints $3 — the two user-facing numbers disagree"; }
chkw fn_table    "$1" "$M_FN"
chkw identifiers "$2" "$M_ID"
chkw var_table   "$3" "$M_VAR"
chkw fixup_table "$4" "$M_FIX"
chkw string_data "$5" "$M_STR"

echo "PASS: capacity_meter_denominators (all 6 meter denominators equal the enforced caps: fn=$CAP_FN id=$CAP_ID var=$CAP_VAR fix=$CAP_FIX str=$CAP_STR code=$CAP_CODE)"
