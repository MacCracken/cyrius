#!/bin/sh
# integer_literal_overflow_refused.sh — 6.6.10: a decimal, hex or octal integer literal whose value
# does not fit in 64 bits is a compile ERROR naming <file>:<line>:<col>; every value up to
# 2^64 - 1 is still accepted, in all three bases.
#
# ⛔ WHY. LEXDEC, LEXHEX and LEXOCT accumulated `val * 10 + d` / `val << 4 | d` / `val << 3 | d`
# with no check, so an out-of-range literal compiled to a DIFFERENT number with no diagnostic:
# `18446744073709551617` was 1, `0x10000000000000001` was 1, `99999999999999999999` was
# 0x6bc75e2d630fffff, and a 25-digit octal literal wrapped. The one such literal in the whole
# ecosystem (programs/cyrld.cyr, `r_add - 0x10000000000000000`) was a no-op that only compiled
# BECAUSE of the wrap; it was deleted in the same change, and row G keeps cyrld building.
#
# 2^63 .. 2^64 - 1 stays legal: it is how a bit pattern with the sign bit set is written
# (`0x8000000000000000`), and `-9223372036854775808` lexes its magnitude first.
#
#   A  accepted: 2^64-1 in decimal, hex, octal, and with `_` separators; 2^63; many leading zeros
#   B  refused (decimal): 2^64, 99999999999999999999, 2^64 spelled with `_`
#   C  refused (hex): 0x10000000000000000, 0x10000000000000001, with `_` separators
#   D  refused (octal): 0o2000000000000000000000 (2^64), a 25-digit octal literal
#   E  the diagnostic names the literal: `error:<file>:<line>:<col>: integer literal ...`
#   F  a FLOAT literal is not an integer literal: a 20-digit integer part before `.5` compiles
#   G  programs/cyrld.cyr compiles
#
# Mutations: drop the `ovf` test in LEXDEC -> B RED (rc 0); in LEXHEX -> C RED; in LEXOCT -> D
# RED; refuse in LEXDEC before the `.` check -> F RED; restore the cyrld line -> G RED.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: integer_literal_overflow_refused: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: integer_literal_overflow_refused: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

# accept <literal> <want exit code (low byte)>
accept() {
    printf 'var x = %s;\nsyscall(60, x & 255);\n' "$1" > "$T/a.cyr"
    rc=0
    "$CC" < "$T/a.cyr" > "$T/a.bin" 2> "$T/a.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "accept $1: rc $rc: $(grep '^error' "$T/a.err" | head -1)"; return; fi
    chmod +x "$T/a.bin"
    e=0; (ulimit -c 0; "$T/a.bin") || e=$?
    if [ "$e" -eq "$2" ]; then ok "accept $1 (exit $e)"; else bad "accept $1: exit $e, want $2"; fi
}
# refuse <literal>
refuse() {
    printf 'var x = %s;\nsyscall(60, 0);\n' "$1" > "$T/r.cyr"
    rc=0
    "$CC" < "$T/r.cyr" > "$T/r.bin" 2> "$T/r.err" || rc=$?
    if [ "$rc" -eq 0 ]; then bad "refuse $1: compiled (rc 0) -- the literal wrapped silently"; return; fi
    if grep -q '^error:.*:1:9: integer literal does not fit in 64 bits' "$T/r.err"; then
        ok "refuse $1 (rc $rc)"
    else
        bad "refuse $1: rc $rc but no located diagnostic: $(head -1 "$T/r.err")"
    fi
}

echo "  -- A accepted"
accept 18446744073709551615 255
accept 0xFFFFFFFFFFFFFFFF 255
accept 0o1777777777777777777777 255
accept 18_446_744_073_709_551_615 255
accept 0xFFFF_FFFF_FFFF_FFFF 255
accept 9223372036854775808 0
accept 0x8000000000000001 1
accept 000000000000000000000000000000042 42
accept 0x0000000000000000000000000000002A 42

echo "  -- B refused (decimal)"
refuse 18446744073709551616
refuse 18446744073709551617
refuse 99999999999999999999
refuse 18_446_744_073_709_551_616

echo "  -- C refused (hex)"
refuse 0x10000000000000000
refuse 0x10000000000000001
refuse 0x1_0000_0000_0000_0000

echo "  -- D refused (octal)"
refuse 0o2000000000000000000000
refuse 0o7777777777777777777777777

echo "  -- E the diagnostic names file, line and column"
printf 'var a = 1;\nvar b = 2;\nfn f(): i64 {\n    return a +   0x10000000000000000;\n}\nsyscall(60, f());\n' > "$T/e.cyr"
rc=0; "$CC" < "$T/e.cyr" > "$T/e.bin" 2> "$T/e.err" || rc=$?
if [ "$rc" -ne 0 ] && grep -q '^error:.*:4:18: integer literal does not fit in 64 bits' "$T/e.err"; then
    ok "error names 4:18"
else
    bad "want 'error:<file>:4:18: integer literal does not fit in 64 bits', rc $rc: $(head -1 "$T/e.err")"
fi

echo "  -- F a float literal's integer part may exceed 2^64"
printf 'var x = 99999999999999999999.5;\nif (x == 0x4415AF1D78B58C40) { syscall(60, 7); }\nsyscall(60, 1);\n' > "$T/f.cyr"
rc=0; "$CC" < "$T/f.cyr" > "$T/f.bin" 2> "$T/f.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "99999999999999999999.5: rc $rc: $(head -1 "$T/f.err")"
else
    chmod +x "$T/f.bin"; e=0; (ulimit -c 0; "$T/f.bin") || e=$?
    if [ "$e" -eq 7 ]; then ok "99999999999999999999.5 compiles to 0x4415AF1D78B58C40"
    else bad "99999999999999999999.5: exit $e, want 7 (bits 0x4415AF1D78B58C40)"; fi
fi

echo "  -- G programs/cyrld.cyr (the one >= 2^64 literal in the ecosystem, removed) compiles"
rc=0; "$CC" < programs/cyrld.cyr > "$T/cyrld" 2> "$T/g.err" || rc=$?
if [ "$rc" -eq 0 ]; then ok "cyrld compiles"; else bad "cyrld: rc $rc: $(grep '^error' "$T/g.err" | head -1)"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL: integer_literal_overflow_refused: $fails row(s)"; exit 1; fi
echo "PASS: integer_literal_overflow_refused"
