#!/bin/sh
# Gate: the IR tables live in one alloc()'d arena that GROWS — an IR build compiles what the
# default build compiles (6.7.14, docs/development/issues/2026-10-08-ir-heap-bands-fixed-offsets-and-caps.md).
#
# THE DEFECT. The IR family was six fixed S + 0x… bands of the compiler arena with hard caps:
# ir_nodes (1,048,576 nodes), ir_cp, ir_blocks (131,072 BBs), ir_live_in / ir_live_out and
# ir_state. A program the default pipeline compiled stopped under CYRIUS_IR with
# "error: IR node buffer full" (or "IR block table full"), rc 1. The tables are now carved from
# one alloc() that IR_SENABLE takes, nodes + CP growing 2x together in ir_emit and BBs +
# live-in + live-out together in ir_bb_new; the state is four globals (src/common/ir.cyr).
#
# Axes:
#   1  the filed repro (400 fns x 500 statements, 3.0 MB, its generator verbatim): default,
#      CYRIUS_IR=1 and CYRIUS_IR=3 compile it (rc 0) and the binaries exit 203; the IR builds
#      record MORE than the old 1,048,576-node cap, so the node table grew past it. And the
#      grown IR is the recorded IR: the IR=3 build's LASE / applied bytes / DSE are exactly 8x
#      those of the same generator at 50 fns, which never grows.
#   2  a BB-heavy program (150 fns x 500 `if (y) { y = 0; }`): ~150,000 BBs, past the old
#      131,072 cap, at ~450,000 nodes — under the old node cap, so the pre-fix compiler stopped
#      on the BLOCK table. IR=1 and IR=3 compile it and the binaries exit 203; its IR=3 LASE is
#      exactly 6x that of 25 fns (25,126 BBs, no grow).
#   3  cycc's own build: CYRIUS_IR=1 is analysis-only, so its output equals the default build;
#      CYRIUS_IR=3's cycc compiles src/main.cyr to the default build byte-identical. The arena
#      starts at 262,144 nodes / 32,768 BBs, so both tables grow here too.
#   4  structural: no S + 0x literal of a retired band left in src/ code, and no heap-map row in
#      src/main.cyr names one.
# Mutation-proven: on the pre-fix compiler (CYCC=<6.7.14-open cycc>) axes 1 and 2 fail with
# rc 1 ("IR node buffer full" / "IR block table full"); on the pre-fix tree axis 4 lists the
# literals and the six rows; a grow that skips the CP copy fails axis 1's scale (152,400 B
# applied, not 600,000), and one that skips the BB copy fails axis 2's (19 LASE, not 150) —
# both mutants pass every other axis, cycc's own IR=3 build included.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=ir_arena_grows
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# build <name> <IR mode, 0 = default> <source>: compile, recording rc in <name>.rc. The five
# large builds are independent, so they run in the background and are checked after `wait`.
build() {
    rc=0
    if [ "$2" = 0 ]; then timeout 300 "$CC" < "$3" > "$T/$1" 2> "$T/$1.err" || rc=$?
    else CYRIUS_IR=$2 timeout 300 "$CC" < "$3" > "$T/$1" 2> "$T/$1.err" || rc=$?; fi
    echo "$rc" > "$T/$1.rc"
}
# check <name> <IR mode> <want exit> <min nodes> <min BBs>: rc, stderr and a non-empty output
# BEFORE running it (an empty output file runs as an empty shell script and exits 0), then the
# exit code and the "ir:" counts.
check() {
    rc=$(cat "$T/$1.rc" 2> /dev/null || echo missing)
    if [ "$rc" != 0 ]; then bad "$1: rc $rc: $(grep '^error' "$T/$1.err" 2> /dev/null | head -1)"; return; fi
    if [ ! -s "$T/$1" ]; then bad "$1: rc 0 but an empty output"; return; fi
    chmod +x "$T/$1"
    got=0; timeout 60 "$T/$1" > /dev/null 2>&1 || got=$?
    if [ "$got" -ne "$3" ]; then bad "$1: exit $got, want $3"; return; fi
    if [ "$2" = 0 ]; then ok "$1: rc 0, exit $got"; return; fi
    line=$(grep '^ir: ' "$T/$1.err" | head -1)
    n=$(echo "$line" | sed -n 's/^ir: \([0-9]*\) nodes, \([0-9]*\) BBs.*/\1/p')
    b=$(echo "$line" | sed -n 's/^ir: \([0-9]*\) nodes, \([0-9]*\) BBs.*/\2/p')
    if [ -z "$n" ] || [ -z "$b" ]; then bad "$1: no 'ir: N nodes, B BBs' line on stderr"; return; fi
    if [ "$n" -le "$4" ]; then bad "$1: $n nodes, not past $4 — the input no longer tests the grow"; return; fi
    if [ "$b" -le "$5" ]; then bad "$1: $b BBs, not past $5 — the input no longer tests the grow"; return; fi
    ok "$1: rc 0, exit $got, $n nodes, $b BBs"
}

# ── axes 1 and 2: the builds (independent, so in the background) ─────────────────────────
REPRO=docs/development/issues/repros/2026-10-08-ir-heap-bands-fixed-offsets-and-caps.sh
HAVE_BIG=0
if [ ! -f "$REPRO" ]; then bad "axis 1: the filed repro generator $REPRO is missing"
else
    sh "$REPRO" > "$T/big.cyr"
    # the same generator at 50 fns (an eighth): 175,728 nodes, inside the arena's first 262,144
    sed 's/f < 400/f < 50/' "$REPRO" | sh > "$T/big50.cyr"
    sz=$(wc -c < "$T/big.cyr")
    sz50=$(wc -c < "$T/big50.cyr")
    if [ "$sz" -lt 3000000 ]; then bad "axis 1: the generator wrote $sz bytes, not the filed 3.0 MB"
    elif [ "$sz50" -ge 500000 ]; then bad "axis 1: the 50-fn variant is $sz50 bytes — the generator's fn count did not change"
    else HAVE_BIG=1; fi
fi
# bbs <n fns>: `if (y) { y = 0; }` x 500 per fn — 2 BBs and 6 nodes a statement
bbs() {
    awk -v nf="$1" 'BEGIN {
        print "var x = 0;"
        for (f = 0; f < nf; f++) {
            printf "fn g%d(a) { var y = a;\n", f
            for (i = 0; i < 500; i++) print "    if (y) { y = 0; }"
            print "    return y; }"
        }
        print "x = g0(9) + 203;"
        print "syscall(60, x & 255);"
    }'
}
bbs 150 > "$T/bbs.cyr"
bbs 25 > "$T/bbs25.cyr"     # 25,126 BBs, inside the arena's first 32,768
if [ "$HAVE_BIG" = 1 ]; then
    build big_def 0 "$T/big.cyr" &
    build big_ir1 1 "$T/big.cyr" &
    build big_ir3 3 "$T/big.cyr" &
    build big50_ir3 3 "$T/big50.cyr" &
fi
build bbs_ir1 1 "$T/bbs.cyr" &
build bbs_ir3 3 "$T/bbs.cyr" &
build bbs25_ir3 3 "$T/bbs25.cyr" &
wait

# irstat <name> <field regex>: the number before/inside the field on the "ir:" line, 0 if absent
irstat() {
    v=$(grep '^ir: ' "$T/$1.err" 2> /dev/null | head -1 | sed -n "s/.*[ (]\([0-9][0-9]*\)$2.*/\1/p")
    echo "${v:-0}"
}
# scale <big> <small> <k> <what>: the grown build's LASE / applied bytes / DSE are exactly k times
# the never-grown build's. The fns are identical, so the passes find the same per fn — unless a
# grow dropped or misplaced part of a table: CP not copied, LASE applies 152,400 B, not 600,000;
# BBs not copied, 19 LASE, not 150 (both measured on mutants).
scale() {
    for fld in ' LASE' 'B applied' ' DSE'; do
        vb=$(irstat "$1" "$fld"); vs=$(irstat "$2" "$fld")
        if [ "$vs" -eq 0 ] && [ "$fld" = ' LASE' ]; then bad "$4: the $2 build reports no LASE — nothing to compare"; return; fi
        if [ "$vb" -ne $((vs * $3)) ]; then bad "$4: $1's '$fld' count is $vb, want $3 x $2's $vs — a grow lost recorded IR"; return; fi
    done
    ok "$4: $1's LASE / applied / DSE ($(irstat "$1" ' LASE') / $(irstat "$1" 'B applied') / $(irstat "$1" ' DSE')) are exactly $3 x $2's"
}

# ── axis 1: the filed repro ──────────────────────────────────────────────────────────────────
if [ "$HAVE_BIG" = 1 ]; then
    check big_def 0 203 0 0
    check big_ir1 1 203 1048576 0
    check big_ir3 3 203 1048576 0
    check big50_ir3 3 203 0 0
    scale big_ir3 big50_ir3 8 "axis 1"
fi
# ── axis 2: past the old BLOCK cap, under the old node cap ──────────────────────────────────
check bbs_ir1 1 203 0 131072
check bbs_ir3 3 203 0 131072
check bbs25_ir3 3 203 0 0
scale bbs_ir3 bbs25_ir3 6 "axis 2"
n=$(irstat bbs_ir1 ' nodes')
if [ "$n" -ge 1048576 ]; then bad "axis 2: $n nodes — past the old node cap too, so it no longer isolates the BB table"; fi

# ── axis 3: cycc's own build under IR=1 and IR=3 ────────────────────────────────────────────
rc=0; timeout 120 "$CC" < src/main.cyr > "$T/cycc_def" 2> "$T/cycc_def.err" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$T/cycc_def" ]; then bad "axis 3: the default self-compile failed (rc $rc)"
else
    rc=0; CYRIUS_IR=1 timeout 120 "$CC" < src/main.cyr > "$T/cycc_ir1" 2> "$T/cycc_ir1.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "axis 3: CYRIUS_IR=1 self-compile rc $rc: $(grep '^error' "$T/cycc_ir1.err" | head -1)"
    elif ! cmp -s "$T/cycc_ir1" "$T/cycc_def"; then bad "axis 3: CYRIUS_IR=1 output differs from the default build (IR=1 is analysis-only)"
    else ok "axis 3: CYRIUS_IR=1 self-compile == the default build ($(grep '^ir: ' "$T/cycc_ir1.err" | cut -d, -f1-2))"; fi
    rc=0; CYRIUS_IR=3 timeout 120 "$CC" < src/main.cyr > "$T/cycc_ir3" 2> "$T/cycc_ir3.err" || rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$T/cycc_ir3" ]; then bad "axis 3: CYRIUS_IR=3 self-compile rc $rc: $(grep '^error' "$T/cycc_ir3.err" | head -1)"
    else
        chmod +x "$T/cycc_ir3"
        rc=0; timeout 120 "$T/cycc_ir3" < src/main.cyr > "$T/cycc_ir3_self" 2> /dev/null || rc=$?
        if [ "$rc" -ne 0 ]; then bad "axis 3: the CYRIUS_IR=3-built cycc failed to compile src/main.cyr (rc $rc)"
        elif ! cmp -s "$T/cycc_ir3_self" "$T/cycc_def"; then bad "axis 3: the CYRIUS_IR=3-built cycc's output differs from the default build"
        else ok "axis 3: the CYRIUS_IR=3-built cycc reproduces the default build"; fi
    fi
fi

# ── axis 4: structural ──────────────────────────────────────────────────────────────────────
NSRC=$(find src -name '*.cyr' | wc -l)
if [ "$NSRC" -lt 30 ]; then bad "axis 4: found $NSRC sources under src/ — the scan is broken"
else
    LIT=$(find src -name '*.cyr' | sort | xargs awk '
        { code = $0
          if (code ~ /^[ \t]*#/) { next }
          gsub(/"([^"\\]|\\.)*"/, "\"\"", code)
          sub(/#.*/, "", code)
          if (code ~ /S[ \t]*\+[ \t]*0x(5E9D000|6E9D000|B3A000|207B000|217B000|F3A0[0-9A-Fa-f][0-9A-Fa-f])([^0-9A-Fa-f]|$)/) {
              print FILENAME ":" FNR ": " $0 } }')
    if [ -n "$LIT" ]; then bad "axis 4: a retired IR band is still addressed in src/:"; echo "$LIT" | head -10 | sed 's/^/      /'
    else ok "axis 4: no S + 0x literal of a retired IR band in $NSRC sources"; fi
    ROWS=$(grep -nE '^#   0x[0-9A-Fa-f]+ +ir_(nodes|cp|blocks|state|live_in|live_out)' src/main.cyr || true)
    if [ -n "$ROWS" ]; then bad "axis 4: src/main.cyr's heap map still maps an IR band:"; echo "$ROWS" | sed 's/^/      /'
    else ok "axis 4: no IR band row in src/main.cyr's heap map"; fi
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G: $fails check(s) failed"; exit 1; fi
echo "PASS: $G — the IR arena grows: the filed repro and a 150k-BB program build under CYRIUS_IR=1/3, cycc's IR builds are sound, no fixed IR band left"
