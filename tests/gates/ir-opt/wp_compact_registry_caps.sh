#!/bin/sh
# Gate: the whole-program compaction registries (util.cyr, v6.5.68) — the source registry
# grows instead of declining, and a registry that does saturate is NAMED on every path.
#
# THE TWO DEFECTS (6.6.20, closeout heap audit HEAP-08).
#
#  1. WPJS, the rel32/disp32 SOURCE registry, was a fixed 49,152 slots at S+0x60000, and
#     cycc's own build fills 43,028 of them (88 %) under CYRIUS_IR=3 and CYRIUS_DCE=1 alike.
#     One source past the cap set _wpjs_ovf and wp_compact declined the WHOLE pass — the dead
#     bytes stayed NOP-filled. The 49,153rd source now moves the registry to alloc'd storage,
#     doubling (_wpjs_grow); _wpjs_ovf means only that the alloc failed.
#
#  2. On the CYRIUS_IR=3 path (main.cyr, after the IR fixpoint) a saturated registry declined
#     wp_compact with no word at all; only the CYRIUS_DCE=1 path named it (6.6.18). Both now
#     take the reason from one helper, _wp_registry_why (backend/common/runtime.cyr).
#
# Axes:
#   1  CYRIUS_DCE=1 on a program with ~50,100 rel32 sources and a dead fn: compaction runs
#      (no "compaction declined"), and the eliminated binary still computes the right answer —
#      the sources recorded PAST the old cap were repaired too, or the calls would land wrong.
#   2  the same program under CYRIUS_IR=3: wp-compact reclaims the IR passes' NOP bytes (it
#      declined in silence before), and the binary still computes the right answer.
#   3  CYRIUS_IR=3 on 4,097 switch jump tables (the WPSW cap is 4,096): stderr names the cap
#      ("wp-compact declined: more than 4096 switch tables") and the binary is still correct.
#   4  the source-heavy program under CYRIUS_IR=3 CYRIUS_DCE=1: the IR seam compacts, then
#      FIXUP's dead-code pass compacts AGAIN, so the registry must have been rebased to the
#      first pass's layout (wp_compact's re-entrancy loop) — the binary still exits 180.
#   5  CYRIUS_IR=3 on 4,200 LASE sites: the NOP-run registry (4,096) saturates and the seam
#      names it as NOP runs, not "dead-code runs" (at the seam they are the IR passes' runs;
#      FIXUP's dead-code pass comes later). This is the case 48 of the 482 tcyr files hit
#      under CYRIUS_IR=3 (the TLS, sandhi and ws programs and the large-source tests). It pins
#      a CLIFF: when the 4,096-run merge on the roadmap backlog lands, axis 5 compacts
#      instead — re-measure it then.
#
# THE THREE READERS. Growing the registry moved it off S+0x60000, so every loop that walks it
# must go through _wpjs_base: wp_compact's stage 1 (axes 1, 2), its re-entrancy rebase (axis 4)
# and the per-fn NOP-compaction adjust in parse_fn.cyr (axes 1, 2). That last one only runs
# for a fn that leaves NOP runs, so every g fn carries a hot loop local: the fn then leaves
# NOP runs, and the per-fn pass shifts that fn's registry entries — the last fns' entries
# sit above index 49,152, in the storage the registry grew into.
# Mutation-proven: on the pre-fix compiler axes 1 and 2 report "more than 49152 rel32/disp32
# sources" / no reclaim, and axis 3 finds no decline note; with any one of the three readers
# put back to the fixed S+0x60000 base, a compacted binary exits 0 or crashes instead of 180.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: wp_compact_registry_caps: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: wp_compact_registry_caps: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fails=0
ok()   { echo "  ok: $1"; }
bad()  { echo "  FAIL: $1"; fails=$((fails + 1)); }

# ── the source-heavy program: 100 fns × 501 calls each = 50,100 call sites (+ the 100 calls
# in the top level), every one a rel32 source. Per fn 501 stays under the per-fn 1,024
# jump_src table, so only the WHOLE-PROGRAM registry is under test. `dead_*` is never
# called, so CYRIUS_DCE=1 has a run to compact. 50,100 & 255 = 180.
awk 'BEGIN {
    print "fn inc(x): i64 { return x + 1; }"
    print "fn dead_a(x): i64 { var y = x * 3; y = y + 7; return y * y; }"
    print "fn dead_b(x): i64 { var y = x * 5; y = y - 9; return y + x; }"
    for (f = 0; f < 100; f++) {
        printf "fn g%d(r): i64 {\n", f
        print "    var a = r; var i = 0;"
        print "    while (i < 2) { a = a + i; i = i + 1; }"
        print "    a = a - 1;"
        for (k = 0; k < 501; k++) { print "    r = inc(r);" }
        print "    return r + a - a;"
        print "}"
    }
    print "var r = 0;"
    for (f = 0; f < 100; f++) { printf "r = g%d(r);\n", f }
    print "syscall(60, r & 255);"
}' > "$D/many_sources.cyr"
NSRC=$(grep -c 'inc(r)' "$D/many_sources.cyr")
[ "$NSRC" -gt 49152 ] || bad "premise: the program has only $NSRC call sites, not past the old 49,152 cap"

run_exit() { "$1"; echo $?; }

# ── axis 1: CYRIUS_DCE=1 ────────────────────────────────────────────────────────────────
if CYRIUS_DCE=1 "$CC" < "$D/many_sources.cyr" > "$D/a1" 2> "$D/a1.err"; then
    chmod +x "$D/a1"
    if grep -q 'compaction declined' "$D/a1.err"; then
        bad "axis 1: CYRIUS_DCE=1 declined compaction: $(grep 'declined' "$D/a1.err")"
    elif grep -q 'bytes of dead code eliminated' "$D/a1.err"; then
        ok "axis 1: CYRIUS_DCE=1 compacted past 49,152 sources ($(grep -o '[0-9]* bytes of dead code eliminated' "$D/a1.err"))"
    else
        bad "axis 1: no elimination note: $(cat "$D/a1.err")"
    fi
    rc=$(run_exit "$D/a1")
    [ "$rc" = 180 ] && ok "axis 1: the compacted binary exits 180" || bad "axis 1: the compacted binary exits $rc, expected 180 — a source past the old cap was not repaired"
else
    bad "axis 1: compile failed: $(head -3 "$D/a1.err")"
fi

# ── axis 2: CYRIUS_IR=3 ─────────────────────────────────────────────────────────────────
if CYRIUS_IR=3 "$CC" < "$D/many_sources.cyr" > "$D/a2" 2> "$D/a2.err"; then
    chmod +x "$D/a2"
    # The IR passes leave a few NOP bytes here (LASE), so a working pass RECLAIMS them; the
    # pre-fix seam declined silently and printed no wp-compact line at all.
    if grep -q 'wp-compact declined' "$D/a2.err"; then
        bad "axis 2: CYRIUS_IR=3 declined: $(grep 'declined' "$D/a2.err")"
    elif grep -q '^wp-compact: [0-9]* bytes reclaimed' "$D/a2.err"; then
        ok "axis 2: CYRIUS_IR=3 compacted past 49,152 sources ($(grep -o '^wp-compact: [0-9]* bytes reclaimed' "$D/a2.err"))"
    else
        bad "axis 2: CYRIUS_IR=3 reclaimed nothing and said nothing: $(grep -v '^warning' "$D/a2.err" | head -3)"
    fi
    rc=$(run_exit "$D/a2")
    [ "$rc" = 180 ] && ok "axis 2: the IR=3 binary exits 180" || bad "axis 2: the IR=3 binary exits $rc, expected 180"
else
    bad "axis 2: compile failed: $(head -3 "$D/a2.err")"
fi

# ── axis 3: 4,097 switch jump tables under CYRIUS_IR=3 ──────────────────────────────────
# Four dense cases reach the x86 table path (parse.cyr: >= 4 cases, density >= 1/3).
awk 'BEGIN {
    for (f = 0; f < 4097; f++) {
        printf "fn s%d(x): i64 {\n    switch (x) {\n", f
        print "        case 0: { return 1; }"
        print "        case 1: { return 2; }"
        print "        case 2: { return 3; }"
        print "        case 3: { return 4; }"
        print "    }"
        print "    return 0;"
        print "}"
    }
    print "var t = 0;"
    for (f = 0; f < 4097; f += 1024) { printf "t = t + s%d(%d);\n", f, f % 4 }
    print "syscall(60, t);"
}' > "$D/many_switches.cyr"
# s0(0)=1 + s1024(0)=1 + s2048(0)=1 + s3072(0)=1 + s4096(0)=1 = 5
if CYRIUS_IR=3 "$CC" < "$D/many_switches.cyr" > "$D/a3" 2> "$D/a3.err"; then
    chmod +x "$D/a3"
    if grep -q 'wp-compact declined: more than 4096 switch tables' "$D/a3.err"; then
        ok "axis 3: the IR=3 seam names the saturated switch-table registry"
    else
        bad "axis 3: 4,097 switch tables under CYRIUS_IR=3 and no decline note: $(grep -v '^note\|^warning' "$D/a3.err" | head -3)"
    fi
    rc=$(run_exit "$D/a3")
    [ "$rc" = 5 ] && ok "axis 3: the binary exits 5" || bad "axis 3: the binary exits $rc, expected 5"
else
    bad "axis 3: compile failed: $(head -3 "$D/a3.err")"
fi

# ── axis 4: CYRIUS_IR=3 CYRIUS_DCE=1 — two compactions, the second over a rebased registry ─
if CYRIUS_IR=3 CYRIUS_DCE=1 "$CC" < "$D/many_sources.cyr" > "$D/a4" 2> "$D/a4.err"; then
    chmod +x "$D/a4"
    if grep -q 'declined' "$D/a4.err"; then
        bad "axis 4: CYRIUS_IR=3 CYRIUS_DCE=1 declined: $(grep 'declined' "$D/a4.err")"
    elif grep -q 'bytes of dead code eliminated' "$D/a4.err"; then
        ok "axis 4: CYRIUS_IR=3 CYRIUS_DCE=1 compacted twice past 49,152 sources"
    else
        bad "axis 4: no elimination note: $(grep -v '^warning' "$D/a4.err" | head -3)"
    fi
    rc=$(run_exit "$D/a4")
    [ "$rc" = 180 ] && ok "axis 4: the twice-compacted binary exits 180" || bad "axis 4: the twice-compacted binary exits $rc, expected 180 — the registry was not rebased to the first pass's layout"
else
    bad "axis 4: compile failed: $(head -3 "$D/a4.err")"
fi

# ── axis 5: 4,200 NOP runs under CYRIUS_IR=3 — the run registry saturates, named ─────────
# `r = r + 3 * 4;` is one LASE site, so one NOP run, each; 512 per fn keeps every fn small.
awk 'BEGIN {
    n = 4200; per = 512; nf = int((n + per - 1) / per); left = n
    for (f = 0; f < nf; f++) {
        printf "fn h%d(r): i64 {\n", f
        c = (left > per) ? per : left; left -= c
        for (k = 0; k < c; k++) { print "    r = r + 3 * 4;" }
        print "    return r;"
        print "}"
    }
    print "var r = 0;"
    for (f = 0; f < nf; f++) { printf "r = h%d(r);\n", f }
    print "syscall(60, r & 255);"
}' > "$D/many_runs.cyr"
# 4,200 × 12 = 50,400; & 255 = 224
if CYRIUS_IR=3 "$CC" < "$D/many_runs.cyr" > "$D/a5" 2> "$D/a5.err"; then
    chmod +x "$D/a5"
    if grep -q 'wp-compact declined: more than 4096 NOP runs' "$D/a5.err"; then
        ok "axis 5: the IR=3 seam names the saturated NOP-run registry"
    else
        bad "axis 5: 4,200 IR NOP runs under CYRIUS_IR=3 and no NOP-run decline note: $(grep -v '^note\|^warning' "$D/a5.err" | head -3)"
    fi
    rc=$(run_exit "$D/a5")
    [ "$rc" = 224 ] && ok "axis 5: the binary exits 224" || bad "axis 5: the binary exits $rc, expected 224"
else
    bad "axis 5: compile failed: $(head -3 "$D/a5.err")"
fi

if [ "$fails" -gt 0 ]; then
    echo "FAIL: wp_compact_registry_caps — $fails check(s)"
    exit 1
fi
echo "PASS: wp_compact_registry_caps — the source registry grows past 49,152; a saturated registry is named under CYRIUS_IR=3"
