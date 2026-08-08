#!/bin/sh
# tests/gates/ir-opt/reloadelim.sh — v6.3.30 redundant-reload elimination gate (O2 category 5).
#
# A 64-bit reload of a local emitted immediately after storing that same local
# (rax still holds it) is skipped at emit time. Fail-safe via CP-adjacency; the
# EPATCH forward-join landings + the 4 loop-top back-edge captures clear the
# store-tracker so a reload reachable via a jump is never skipped. DEFAULT ON;
# CYRIUS_RELOADELIM=0 opts out.
#
# Asserts: (1) the default (reload-elim) cycc self-hosts a fixpoint byte-identically;
# (2) it is STRICTLY SMALLER than the CYRIUS_RELOADELIM=0 build (proves the pass fires);
# (3) the reload_elim.tcyr control-flow hazard suite passes (loops / forward-joins /
# continue must NOT skip a reachable reload); (4) a sample of tcyr produce IDENTICAL
# runtime exit codes reload-elim on vs off (behavior-preserving — no live value dropped).
set -u
cd "$(dirname "$0")/../../.." || exit 2
TMP="${TMPDIR:-/tmp}/reloadelim.$$"
mkdir -p "$TMP" || exit 2
trap 'rm -rf "$TMP"' EXIT

# (1) default (reload-elim) cycc self-hosts byte-identical.
cat src/main.cyr | build/cycc > "$TMP/on"  2>/dev/null || { echo "FAIL: build reload-elim cycc"; exit 1; }
chmod +x "$TMP/on"
cat src/main.cyr | "$TMP/on" > "$TMP/on2" 2>/dev/null || { echo "FAIL: reload-elim cycc self-host"; exit 1; }
cmp -s "$TMP/on" "$TMP/on2" || { echo "FAIL: reload-elim cycc not a self-host fixpoint"; exit 1; }

# (2) reload-elim < opted-out (CYRIUS_RELOADELIM=0).
CYRIUS_RELOADELIM=0 sh -c "cat src/main.cyr | build/cycc > \"$TMP/off\"" 2>/dev/null || { echo "FAIL: build opted-out"; exit 1; }
S_ON=$(wc -c < "$TMP/on"); S_OFF=$(wc -c < "$TMP/off")
if [ "$S_ON" -ge "$S_OFF" ]; then
    echo "FAIL: reload-elim cycc ($S_ON) not smaller than opted-out ($S_OFF) — pass not firing"; exit 1
fi

# (3) control-flow hazard suite passes AND is behavior-identical to opted-out.
cat tests/tcyr/compiler/reload_elim.tcyr | build/cycc > "$TMP/re_on" 2>/dev/null; chmod +x "$TMP/re_on" 2>/dev/null
"$TMP/re_on" >/dev/null 2>&1 || { echo "FAIL: reload_elim.tcyr hazard suite (reload-elim on)"; exit 1; }
CYRIUS_RELOADELIM=0 sh -c "cat tests/tcyr/compiler/reload_elim.tcyr | build/cycc > \"$TMP/re_off\"" 2>/dev/null; chmod +x "$TMP/re_off" 2>/dev/null
"$TMP/re_off" >/dev/null 2>&1 || { echo "FAIL: reload_elim.tcyr hazard suite (opted-out)"; exit 1; }

# (4) behavior-preserving: exit codes identical on vs off across a control-flow-heavy sample.
for t in tests/tcyr/compiler/reload_elim.tcyr tests/tcyr/lang/core.tcyr tests/tcyr/lang/closures.tcyr \
         tests/tcyr/math/bigint.tcyr tests/tcyr/memory/alloc_collections.tcyr tests/tcyr/stdlib/chrono.tcyr; do
    [ -f "$t" ] || continue
    cat "$t" | "$TMP/on"  > "$TMP/pa" 2>/dev/null; chmod +x "$TMP/pa" 2>/dev/null
    CYRIUS_RELOADELIM=0 sh -c "cat \"$t\" | build/cycc > \"$TMP/pb\"" 2>/dev/null; chmod +x "$TMP/pb" 2>/dev/null
    "$TMP/pa" >/dev/null 2>&1; ea=$?
    "$TMP/pb" >/dev/null 2>&1; eb=$?
    if [ "$ea" != "$eb" ]; then
        echo "FAIL: $t exit differs reload-elim=$ea opted-out=$eb"; exit 1
    fi
done

echo "OK: reload-elim self-hosts, shrinks cycc ($S_OFF -> $S_ON B), behavior-preserving"
exit 0
