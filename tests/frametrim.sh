#!/bin/sh
# tests/frametrim.sh — v6.3.29 callee-saved frame-trim gate.
#
# A #regalloc fn saves+restores ALL _cur_fn_regalloc callee-saved regs (rbx,r12-r15)
# but the linear-scan picker often uses fewer; the trim NOPs the dead save/restore
# pairs (harvested by the compactor). DEFAULT ON; CYRIUS_FRAMETRIM=0 opts out.
#
# Asserts: (1) the default (trimmed) cycc self-hosts a fixpoint byte-identically;
# (2) the trimmed cycc is STRICTLY SMALLER than the CYRIUS_FRAMETRIM=0 build (proves
# the pass fires); (3) a set of programs produce IDENTICAL runtime exit codes trimmed
# vs untrimmed (behavior-preserving — the ABI-critical property: no callee-saved reg
# is wrongly dropped).
set -u
cd "$(dirname "$0")/.." || exit 2
TMP="${TMPDIR:-/tmp}/frametrim.$$"
mkdir -p "$TMP" || exit 2
trap 'rm -rf "$TMP"' EXIT

# (1) default (trimmed) cycc self-hosts byte-identical.
cat src/main.cyr | build/cycc > "$TMP/on"  2>/dev/null || { echo "FAIL: build trimmed cycc"; exit 1; }
chmod +x "$TMP/on"
cat src/main.cyr | "$TMP/on" > "$TMP/on2" 2>/dev/null || { echo "FAIL: trimmed cycc self-host"; exit 1; }
cmp -s "$TMP/on" "$TMP/on2" || { echo "FAIL: trimmed cycc not a self-host fixpoint"; exit 1; }

# (2) trimmed < untrimmed (CYRIUS_FRAMETRIM=0).
CYRIUS_FRAMETRIM=0 sh -c "cat src/main.cyr | build/cycc > \"$TMP/off\"" 2>/dev/null || { echo "FAIL: build untrimmed"; exit 1; }
S_ON=$(wc -c < "$TMP/on"); S_OFF=$(wc -c < "$TMP/off")
if [ "$S_ON" -ge "$S_OFF" ]; then
    echo "FAIL: trimmed cycc ($S_ON) not smaller than untrimmed ($S_OFF) — pass not firing"; exit 1
fi

# (3) behavior-preserving: exit codes identical trimmed vs untrimmed across a sample.
for t in tests/tcyr/alloc_collections.tcyr tests/tcyr/bigint.tcyr tests/tcyr/closures.tcyr \
         tests/tcyr/core.tcyr tests/tcyr/derive_serialize_roundtrip.tcyr tests/tcyr/chrono.tcyr; do
    [ -f "$t" ] || continue
    cat "$t" | "$TMP/on"  > "$TMP/pa" 2>/dev/null; chmod +x "$TMP/pa" 2>/dev/null
    CYRIUS_FRAMETRIM=0 sh -c "cat \"$t\" | build/cycc > \"$TMP/pb\"" 2>/dev/null; chmod +x "$TMP/pb" 2>/dev/null
    "$TMP/pa" >/dev/null 2>&1; ea=$?
    "$TMP/pb" >/dev/null 2>&1; eb=$?
    if [ "$ea" != "$eb" ]; then
        echo "FAIL: $t exit differs trimmed=$ea untrimmed=$eb"; exit 1
    fi
done

echo "OK: frame-trim self-hosts, shrinks cycc ($S_OFF -> $S_ON B), behavior-preserving"
exit 0
