#!/bin/sh
# cx_indirect_call.sh — v6.5.13. `callptr` works on the cx backend.
#
# WHAT THIS PINS. Three separate defects had to be fixed together, and any one of them
# regressing puts cx fn-pointers back to silently broken:
#   1. `ELOAD_FN_ADDR` was a return-0 STUB, so `&fn` materialised as 0 — every fn pointer
#      was null before anything tried to call it.
#   2. `main_cx.cyr` never set `_fixup_base`, so the shared ELOAD_FN_ADDR path computed an
#      address near NULL and SIGSEGV'd the compiler. That is WHY (1) was a stub.
#   3. `ECALLIND` hard-errored ("not supported on the cx backend"). Now opcode 105 (0x69).
#
# ⚠ THE ACCEPTANCE IS INDIRECT == DIRECT, not indirect == expected. cx has a SEPARATE
# pre-existing multiply defect (`x * 2` returns x; `a*100+b` returns 51 for 3,7), so
# asserting expected values here would fail for reasons that have nothing to do with
# callptr. Comparing the two call forms isolates exactly this feature — and it is what
# revealed the multiply bug was pre-existing rather than caused by this work.
#
# ⚠ OPCODE 105 IS PERMANENT and was chosen with a scan covering BOTH notations:
#     grep -oE 'op == (0x[0-9A-Fa-f]+|[0-9]+)' programs/cxvm.cyr
# A decimal-only scan reports 98/99 free when they are pushc/popc — and an arm added for
# 98 shadows pushc, silently corrupting every program that saves a register. That mistake
# cost real time; do not repeat it.
# ⚠ NO `set -e`. These programs exit with their RESULT (42, 51, …) — a non-zero exit is
# the DATA, not a failure — and `set -e` would kill the script at the first case, before
# any bookkeeping. Same trap CLAUDE.md records for CI shell-loop gates.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT

cat src/main_cx.cyr | ./build/cycc > "$D/cc" 2>/dev/null; chmod +x "$D/cc"
cat programs/cxvm.cyr | ./build/cycc > "$D/vm" 2>/dev/null; chmod +x "$D/vm"

pass=0; fail=0
eqcase() {  # $1 body  $2 params  $3 direct-args  $4 indirect-args
    printf 'fn t(%s): i64 { return %s; }\nfn main(): i64 { return t(%s); }\nvar r = main();\nsyscall(60, r);\n' "$2" "$1" "$3" > "$D/d.cyr"
    printf 'fn t(%s): i64 { return %s; }\nfn main(): i64 { var f = &t; return callptr(f, %s); }\nvar r = main();\nsyscall(60, r);\n' "$2" "$1" "$4" > "$D/i.cyr"
    cat "$D/d.cyr" | "$D/cc" > "$D/d.cyx" 2>/dev/null
    DR=0; timeout 30 "$D/vm" < "$D/d.cyx" >/dev/null 2>&1 || DR=$?
    cat "$D/i.cyr" | "$D/cc" > "$D/i.cyx" 2>/dev/null
    IR=0; timeout 30 "$D/vm" < "$D/i.cyx" >/dev/null 2>&1 || IR=$?
    if [ "$DR" = "$IR" ]; then printf '  ok: %-16s direct=%s indirect=%s\n' "$1" "$DR" "$IR"; pass=$((pass+1))
    else printf '  FAIL: %-16s direct=%s indirect=%s\n' "$1" "$DR" "$IR"; fail=$((fail+1)); fi
}

echo "axis 1 — callptr result matches the same fn called directly:"
eqcase "x + 1"       "x"       "41"       "41"
eqcase "x - 1"       "x"       "43"       "43"
eqcase "99"          "x"       "0"        "0"
eqcase "a + b"       "a, b"    "20, 22"   "20, 22"
eqcase "a + b + c"   "a, b, c" "10,20,12" "10,20,12"

echo "axis 2 — &fn MATERIALISES (the return-0 stub returned 0 for every fn):"
printf 'fn t(x): i64 { return x; }\nfn main(): i64 { var f = &t; return f; }\nvar r = main();\nsyscall(60, r);\n' > "$D/p.cyr"
cat "$D/p.cyr" | "$D/cc" > "$D/p.cyx" 2>/dev/null
PV=0; timeout 30 "$D/vm" < "$D/p.cyx" >/dev/null 2>&1 || PV=$?
if [ "$PV" -gt 0 ]; then printf '  ok: &fn is a non-zero code offset (%s)\n' "$PV"; pass=$((pass+1))
else printf '  FAIL: &fn is 0 — ELOAD_FN_ADDR is stubbed again\n'; fail=$((fail+1)); fi

echo "axis 3 — the compiler does not SIGSEGV recording a fn-pointer fixup (_fixup_base wired):"
RC=0; cat "$D/p.cyr" | "$D/cc" > /dev/null 2>&1 || RC=$?
if [ "$RC" -eq 0 ]; then printf '  ok: cx compile clean (rc=0)\n'; pass=$((pass+1))
else printf '  FAIL: cx compile rc=%s (139 = _fixup_base unset)\n' "$RC"; fail=$((fail+1)); fi

echo "axis 4 — NO DUPLICATE opcode arm in cxvm's dispatch (radix-blind):"
# ⛔ THIS AXIS IS THE ONE THAT WOULD HAVE SAVED THE MOST TIME. cxvm's chain mixes radix:
# 54 arms decimal (…96, 97, <gap>, 100, 101…) and only 0x62/0x63/0x69 in hex — so a
# decimal-only reader sees 98/99 as a free gap when they are pushc/popc. Adding an
# `op == 98` arm ABOVE the `op == 0x62` arm shadows pushc, which every guest fn prologue
# emits as its frame-pointer save, and the VM silently does nothing for EVERY program.
# Proven equivalent: `op == 98` and `op == 0x62` with the same body compile byte-identically.
# The trap was already written up in backend/cx/emit.cyr — but nothing enforced it.
dups=$(grep -oE 'op == (0x[0-9A-Fa-f]+|[0-9]+)' programs/cxvm.cyr \
       | awk '{v=$3; print (v ~ /^0x/) ? strtonum(v) : v+0}' | sort -n | uniq -d)
if [ -z "$dups" ]; then
    printf '  ok: every dispatch arm is a distinct opcode (both radixes normalised)\n'; pass=$((pass+1))
else
    printf '  FAIL: duplicate cxvm dispatch opcode(s): %s\n' "$(echo $dups)"; fail=$((fail+1))
fi

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
echo "PASS: cx callptr — indirect calls match direct, &fn materialises, no compiler fault"
