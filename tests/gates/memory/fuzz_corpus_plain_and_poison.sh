#!/bin/sh
# Gate: EVERY fuzz/*.fcyr harness passes plain AND under `cyrius fuzz --poison`, in bounded time,
# before a tag (6.7.18; issues/archived/2026-10-22-network-parsers-unfuzzed-and-bounds-mode-blind-to-raw-loads.md,
# acceptance 4).
#
# ⛔ WHY. The harnesses ran in CI only (`./build/cyrius fuzz`) and, plain, in one check-driver gate
# (`_fuzz_harness_gate`, retired into this one): nothing ran them under the allocator poison mode,
# so a harness whose parser wrote one byte past a heap block (exit 86 under --poison) or read freed
# memory was first seen after a push — and the network parsers' harnesses (6.7.18) exist to be run
# under it. A gate that walks a corpus must also know the corpus is THERE: an emptied or moved
# fuzz/ reads as "0 failed".
#
# AXES
#   1  floor: fuzz/ holds at least FLOOR harnesses (recursive find — never a flat glob)
#   2  plain: `cyrius fuzz fuzz` exits 0 and reports "N passed, 0 failed" with N = axis 1's count,
#      so every harness ran (a harness the walk skipped is a count mismatch, not a pass)
#   3  --poison: the same — alloc(), arenas and fl blocks redzoned, an overwrite exit 86
#   4  bounded: each harness runs under `--timeout=` (FUZZ_HARNESS_SECS, default 120) and each run
#      under an outer deadline (FUZZ_RUN_SECS, default 900): a hung harness is a named FAIL,
#      never a stuck check.sh
#   5  anti-vacuous: a one-harness corpus whose harness faults (SIGSEGV) FAILs both runs, named
#   6  the --poison run earns its place: a harness that writes one byte past a heap block passes
#      plain (the retired gate's only run) and FAILs under --poison
#
# The A/B differential (`--poison=ab`, the over-read detector) is pinned per mechanism by
# poison_ab_differential.sh; every harness here passes it too (6.7.18), at twice the cost.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=fuzz_corpus_plain_and_poison
FLOOR=16   # 6.7.18: + the folds' parser harnesses (sigil_x509, bayan_json, sandhi_hpack / _headers / _dns)
HSECS=${FUZZ_HARNESS_SECS:-120}
RSECS=${FUZZ_RUN_SECS:-900}
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $NAME: no compiler at $CC"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT INT TERM
FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
_ok() { echo "  ok: $1"; }
CLI=${CYRIUS_BIN:-}
if [ -z "$CLI" ]; then
    ( cd "$ROOT" && "$CC" < cbt/cyrius.cyr > "$T/cyrius" 2>/dev/null ) && chmod +x "$T/cyrius" \
        || { echo "SKIP: $NAME: cbt/cyrius.cyr did not build"; exit 77; }
    CLI="$T/cyrius"
fi
TO=""
command -v timeout > /dev/null 2>&1 && TO="timeout $RSECS"

# fz DIR OUT MODE... — `cyrius fuzz` in DIR (no deps resolve: nothing is written), bounded.
fz() {
    _d=$1; _o=$2; shift 2
    ( cd "$_d" && CYRIUS_RESOLVED=1 $TO "$CLI" fuzz --timeout="$HSECS" "$@" fuzz ) > "$_o" 2>&1
}

echo "axis 1 — the corpus is there:"
N=$(find "$ROOT/fuzz" -name '*.fcyr' | wc -l | tr -d ' ')
if [ "$N" -ge "$FLOOR" ]; then _ok "fuzz/ holds $N harnesses (floor $FLOOR)"
else _fail "fuzz/ holds $N harnesses (floor $FLOOR) — moved, renamed or deleted harnesses would read as '0 failed'"; fi

for mode in plain poison; do
    if [ "$mode" = plain ]; then flag=""; ax=2; else flag="--poison"; ax=3; fi
    echo "axis $ax — every harness, $mode:"
    rc=0; fz "$ROOT" "$T/$mode.out" $flag || rc=$?
    want="=== $N passed, 0 failed ==="
    if [ "$rc" = 124 ]; then _fail "the $mode run passed its ${RSECS}s deadline (axis 4) — a harness hangs"
    elif [ "$rc" = 0 ] && grep -qxF "$want" "$T/$mode.out"; then _ok "$mode: '$want'"
    else
        _fail "$mode: rc $rc, wanted '$want': $(grep -E 'FAIL|passed,' "$T/$mode.out" | tr '\n' ' ' | cut -c1-400)"
    fi
done

echo "axis 5 — a faulting harness fails both runs:"
mkdir -p "$T/bad/fuzz"
cat > "$T/bad/fuzz/faults.fcyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var p = 8;
    store64(p, 1);                     # a write to address 8: SIGSEGV
    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
EOF
ln -s "$ROOT/lib" "$T/bad/lib"
for mode in plain poison; do
    if [ "$mode" = plain ]; then flag=""; else flag="--poison"; fi
    rc=0; fz "$T/bad" "$T/bad.$mode.out" $flag || rc=$?
    if [ "$rc" = 1 ] && grep -q 'faults.fcyr.*FAIL\|^FAIL' "$T/bad.$mode.out" && grep -qxF '=== 0 passed, 1 failed ===' "$T/bad.$mode.out"; then
        _ok "$mode: the faulting harness is a FAIL (rc 1, '0 passed, 1 failed')"
    else _fail "$mode: the faulting harness gave rc $rc: $(tr '\n' ' ' < "$T/bad.$mode.out" | cut -c1-300)"; fi
done

echo "axis 6 — a heap overwrite only --poison sees fails the --poison run:"
mkdir -p "$T/over/fuzz"
cat > "$T/over/fuzz/overwrite.fcyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
fn main(): i64 {
    alloc_init();
    var p = alloc(16);
    store8(p + 16, 1);                 # one byte past the block: silent plain, exit 86 under --poison
    var q = alloc(16);                 # (the next allocation is where the redzone is checked)
    return q - q;
}
var r = main();
syscall(SYS_EXIT, r);
EOF
ln -s "$ROOT/lib" "$T/over/lib"
rc=0; fz "$T/over" "$T/over.plain.out" || rc=$?
if [ "$rc" = 0 ] && grep -qxF '=== 1 passed, 0 failed ===' "$T/over.plain.out"; then _ok "plain: the overwrite passes unseen (why the plain run is not enough)"
else _fail "plain: the overwrite gave rc $rc (premise: a plain run does not see it): $(tr '\n' ' ' < "$T/over.plain.out" | cut -c1-300)"; fi
rc=0; fz "$T/over" "$T/over.poison.out" --poison || rc=$?
if [ "$rc" = 1 ] && grep -qxF '=== 0 passed, 1 failed ===' "$T/over.poison.out"; then _ok "--poison: the overwrite is a FAIL (exit 86 in the harness)"
else _fail "--poison: the overwrite gave rc $rc: $(tr '\n' ' ' < "$T/over.poison.out" | cut -c1-300)"; fi

if [ "$FAILS" = 0 ]; then echo "PASS: $NAME ($N harnesses, plain and --poison, each bounded at ${HSECS}s)"; exit 0; fi
echo "FAIL: $NAME ($FAILS)"
exit 1
