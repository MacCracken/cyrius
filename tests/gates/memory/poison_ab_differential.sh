#!/bin/sh
# Gate: `cyrius fuzz --poison=ab` — the A/B poison differential (6.6.18, poison-8) and the
# `--poison` banner that states the real coverage (poison-9).
#
# ⭐ WHY A/B. Poison fills redzones and freed memory with a pattern, which makes an OVERWRITE
# detectable (the pattern changed — exit 86) but leaves an OVERREAD silent: the harness reads
# 0xA5, computes with it and exits 0. Running every harness twice, fill 0xA5 then 0x5A (the B
# leg compiles with `#define CYRIUS_POISON_B`, which lib/poison.cyr reads), turns any read of a
# redzone or of freed memory into a difference between the two legs' stdout — no assertion in
# the harness needed.
#
# Axes
#   1  a harness printing load8(alloc(16) + 16) — one byte past the request — FAILs under
#      `--poison=ab` with "diverged", while plain `--poison` PASSes it. The pair is the proof
#      that A/B adds the detection.
#   2  a deterministic clean harness PASSes under ab (anti-vacuous: "always FAIL" passes 1).
#   3  `--poison=xyz` exits non-zero with a named error (it must not run as plain --poison).
#   4  a harness that exits non-zero in ONE leg only FAILs and names both exit codes.
#   5  CYRIUS_POISON_B is popped after each B leg and -D defines survive: a run over TWO
#      overread harnesses fails BOTH (a leaked B define makes the second one's legs identical),
#      and -D ABPROBE still reaches every leg.
#   6  (poison-9) the `--poison` banner names alloc() and arenas as COVERED, mentions exit 86,
#      and no longer says "NOT covered: alloc()"; the ab run adds its two-fill line.
# Old code (a2c60583): `--poison=ab` is not a value fuzz accepts, there is no differential and
# the banner says alloc() is not covered — axes 1, 3, 4, 5, 6 fail.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: poison_ab_differential: no compiler at $CC"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: poison_ab_differential: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail() { echo "FAIL: poison_ab_differential: $1"; exit 1; }
CLI=${CYRIUS_BIN:-}
if [ -z "$CLI" ]; then
    ( cd "$ROOT" && "$CC" < cbt/cyrius.cyr > "$D/cyrius" 2>/dev/null ) && chmod +x "$D/cyrius" \
        || { echo "SKIP: poison_ab_differential: cbt/cyrius.cyr did not build"; exit 77; }
    CLI="$D/cyrius"
fi
# The harnesses include lib/... — a project whose lib/ is the tree's.
P="$D/p"; mkdir -p "$P/two"; ln -s "$ROOT/lib" "$P/lib"
fz() { ( cd "$P" && CYRIUS_RESOLVED=1 "$CLI" fuzz "$@" 2>&1 ); }

cat > "$P/over.fcyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/fmt.cyr"
fn main(): i64 {
    alloc_init();
    var p = alloc(16);
    fmt_int(load8(p + 16));
    return 0;
}
var r = main();
syscall(60, r);
EOF
cat > "$P/clean.fcyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/fmt.cyr"
fn main(): i64 {
    alloc_init();
    var p = alloc(16);
    store8(p, 7);
    fmt_int(load8(p));
    return 0;
}
var r = main();
syscall(60, r);
EOF
cat > "$P/oneleg.fcyr" <<'EOF'
include "lib/alloc.cyr"
fn main(): i64 {
    alloc_init();
    if (poison_fill() == 90) { return 3; }
    return 0;
}
var r = main();
syscall(60, r);
EOF

# ── axis 1 ───────────────────────────────────────────────────────────────────────────
rc=0; O1=$(fz over.fcyr --poison) || rc=$?
[ "$rc" -eq 0 ] || fail "axis 1 premise: plain --poison did not pass the overread harness (rc $rc) — the pair proves nothing: $(echo "$O1" | grep over)"
rc=0; O1B=$(fz over.fcyr --poison=ab) || rc=$?
[ "$rc" -ne 0 ] || fail "axis 1: --poison=ab passed a harness that reads one byte past its request"
echo "$O1B" | grep -q 'over\.fcyr.*FAIL (A/B diverged at byte' || fail "axis 1: no 'diverged' verdict: $(echo "$O1B" | grep over)"

# ── axis 2 ───────────────────────────────────────────────────────────────────────────
rc=0; O2=$(fz clean.fcyr --poison=ab) || rc=$?
[ "$rc" -eq 0 ] && echo "$O2" | grep -qE '^  clean\.fcyr +PASS$' || fail "axis 2: a deterministic clean harness did not PASS under ab (rc $rc): $(echo "$O2" | grep clean)"

# ── axis 3 ───────────────────────────────────────────────────────────────────────────
rc=0; O3=$(fz clean.fcyr --poison=xyz) || rc=$?
[ "$rc" -ne 0 ] || fail "axis 3: --poison=xyz exited 0"
echo "$O3" | grep -q "unknown --poison mode" || fail "axis 3: --poison=xyz was not refused by name: $(echo "$O3" | head -2)"
echo "$O3" | grep -q 'clean\.fcyr' && fail "axis 3: --poison=xyz ran the harness anyway"

# ── axis 4 ───────────────────────────────────────────────────────────────────────────
rc=0; O4=$(fz oneleg.fcyr --poison=ab) || rc=$?
[ "$rc" -ne 0 ] || fail "axis 4: a harness exiting 3 in the B leg only passed"
echo "$O4" | grep -q 'oneleg\.fcyr.*FAIL (A exit 0, B exit 3)' || fail "axis 4: the verdict does not name both exits: $(echo "$O4" | grep oneleg)"

# ── axis 5 ───────────────────────────────────────────────────────────────────────────
for h in o1 o2; do
    { printf '#ifdef ABPROBE\n'; cat "$P/over.fcyr"; printf '#endif\n'; } > "$P/two/$h.fcyr"
done
rc=0; O5=$(fz two -D ABPROBE --poison=ab) || rc=$?
n5=$(echo "$O5" | grep -c 'FAIL (A/B diverged' || true)
[ "$n5" -eq 2 ] || fail "axis 5: $n5 of 2 overread harnesses diverged in one run — CYRIUS_POISON_B leaked into the next harness or -D ABPROBE was lost: $(echo "$O5" | grep 'two/')"

# ── axis 6 (poison-9) ────────────────────────────────────────────────────────────────
echo "$O1" | grep -q '^poison mode: alloc(), arenas' || fail "axis 6: the --poison banner does not name alloc() and arenas as covered: $(echo "$O1" | grep -i poison | head -2)"
echo "$O1" | grep -q 'exit 86' || fail "axis 6: the banner does not say an overwrite stops the harness with exit 86"
echo "$O1" | grep -q 'NOT covered: alloc()' && fail "axis 6: the banner still says alloc() is not covered"
echo "$O1B" | grep -q -- '--poison=ab: each harness is compiled and run twice (fill 0xA5, then 0x5A)' || fail "axis 6: the ab run does not name its two fills"
echo "$O1" | grep -q -- '--poison=ab: each harness' && fail "axis 6: plain --poison printed the ab line"

echo "PASS: poison_ab_differential (an overread fails A/B and passes plain --poison; clean passes; a bad mode is refused; a one-leg exit fails; the B define never leaks; the banner states the coverage)"
exit 0
