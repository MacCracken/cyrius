#!/bin/sh
# 6.6.10: a TOP-LEVEL destructure (`var a, b = f();` after the first top-level
# statement, the PARSE_PROG arm of parse_decl.cyr) wrote its 2nd/3rd name at
# GVCNT+1 / GVCNT+2 BEFORE SVCNT grew the var family. The GVCNT < _var_cap
# invariant covers only the first name, so at the cap the others landed past the
# table: the initial tables are contiguous 8192-slot bands, so varn[8192] aliased
# var_sizes[0] and vars[8192] aliased var_types[0] (the name was lost -> "undefined
# variable 'db'", or, with the name unused, g0 silently read 0 and the binary grew
# 48 KB); at the grown cap (16384) the write landed in the next alloc'd table.
# Fix: SVCNT before the name stores. CHANGELOG [6.6.10]
#
# Every row compiles a fixture of N globals + `var z = 1; z = 2;` (so the
# destructure takes the PARSE_PROG path) and asserts the EXIT VALUE — a lost name
# is a compile error and a miscompile is a wrong value; both fail the row.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: toplevel_destructure_var_cap: build/cycc missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: toplevel_destructure_var_cap: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT

fail=0
# row N TAIL WANT LABEL
row() {
    n=$1; tail=$2; want=$3; label=$4
    {
        echo 'fn pr(): (i64, i64) { return (4, 9); }'
        echo 'fn pr3(): (i64, i64, i64) { return (4, 9, 2); }'
        awk -v n="$n" 'BEGIN { for (i = 0; i < n; i++) printf "var g%d = %d;\n", i, i + 1 }'
        echo 'var z = 1; z = 2;'
        echo "$tail"
    } > "$D/f.cyr"
    if ! "$CC" < "$D/f.cyr" > "$D/f.bin" 2> "$D/f.err"; then
        echo "FAIL: $label (n=$n): compile failed:"; head -3 "$D/f.err"; fail=1; return 0
    fi
    chmod +x "$D/f.bin"
    rc=0; "$D/f.bin" || rc=$?
    if [ "$rc" != "$want" ]; then
        echo "FAIL: $label (n=$n): exit $rc, want $want"; fail=1
    fi
}

U2='var da, db = pr(); syscall(60, da*10+db+g0);'
N2='var da, db = pr(); syscall(60, da*10+g0);'
U3='var da, db, dc = pr3(); syscall(60, da*10+db+dc+g0);'
N3='var da, db, dc = pr3(); syscall(60, da*10+g0);'

# Initial-band cap (8192): N globals + z put da at 8191 (arity 2) / 8190 (arity 3).
row 8190 "$U2" 50 "arity 2, 2nd name used, at the 8192 band"
row 8190 "$N2" 41 "arity 2, 2nd name unused (was a silent miscompile)"
row 8189 "$U3" 52 "arity 3, all names used, dc past the band"
row 8190 "$U3" 52 "arity 3, all names used, db and dc past the band"
row 8189 "$N3" 41 "arity 3, names unused (was a silent miscompile)"
# Grown cap (16384): the past-cap write landed in the next alloc'd table.
row 16382 "$U2" 50 "arity 2, used, at the grown cap"
row 16382 "$N2" 41 "arity 2, unused, at the grown cap"
# Control: well below the cap.
row 10 "$U3" 52 "arity 3 control, far from the cap"

[ "$fail" = 0 ] || exit 1
echo "PASS: top-level destructure grows the var table before storing its names (8 rows, both caps; 6.6.10)"
