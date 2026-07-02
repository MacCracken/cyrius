#!/bin/sh
# v6.3.27 gate — cross-BB liveness fixpoint (ir_liveness_cfg).
#
# The IR pipeline's per-BB DCE seeds each block's exit conservatively (live=3,
# both RAX/RCX). v6.3.27 adds a CFG backward-dataflow fixpoint that computes the
# PRECISE per-BB live-out as the union of successors' live-in. This is pure
# ANALYSIS (writes only the ir_live_in/out arrays; no codegen) and the reusable
# substrate v6.3.28 copy-prop + v6.3.29 cross-BB DSE consume.
#
# Asserts, on a program with real control flow (if/else + returns):
#   (1) BEHAVIORAL SAFETY — CYRIUS_IR-compiled binary produces the SAME result
#       as the default build (analysis must never change behavior).
#   (2) CONVERGENCE — the fixpoint converges well under the 64-iteration cap.
#   (3) PRECISION — at least one exit/return BB gets live_out==0 (proof the
#       fixpoint is more precise than the DCE's conservative "always 3" seed).
#
# Skips off Linux/x86_64 or without build/cycc.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CYCC="$ROOT/build/cycc"

uname_s=$(uname -s 2>/dev/null || echo unknown)
uname_m=$(uname -m 2>/dev/null || echo unknown)
if [ "$uname_s" != "Linux" ] || [ "$uname_m" != "x86_64" ]; then
    echo "SKIP: IR liveness gate is Linux/x86_64 only (host: $uname_s/$uname_m)"; exit 0
fi
if [ ! -x "$CYCC" ]; then echo "SKIP: build/cycc not built"; exit 0; fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cfg.cyr" <<'EOF'
fn classify(x): i64 {
    if (x > 10) { return 100; }
    if (x > 0)  { return 10; }
    if (x == 0) { return 0; }
    return 0 - 1;
}
fn sum_to(n): i64 {
    var s = 0; var i = 0;
    while (i < n) { s = s + i; i = i + 1; }
    return s;
}
fn main(): i64 {
    return classify(50) + classify(5) + classify(0) + classify(0 - 7) + sum_to(5);
}
EOF
# expected: 100 + 10 + 0 + (-1) + (0+1+2+3+4=10) = 119

# (1) behavioral safety: default vs CYRIUS_IR must agree
"$CYCC" < "$TMP/cfg.cyr" > "$TMP/def" 2>/dev/null; chmod +x "$TMP/def"
set +e; "$TMP/def"; def_rc=$?; set -e
CYRIUS_IR=1 "$CYCC" < "$TMP/cfg.cyr" > "$TMP/ir" 2>/dev/null; chmod +x "$TMP/ir"
set +e; "$TMP/ir"; ir_rc=$?; set -e
if [ "$def_rc" != "119" ]; then
    echo "FAIL: default build gave $def_rc (expected 119) — test program or compiler broken"; exit 1
fi
if [ "$ir_rc" != "$def_rc" ]; then
    echo "FAIL: CYRIUS_IR build gave $ir_rc but default gave $def_rc — liveness analysis changed behavior"; exit 1
fi
echo "  PASS: behavioral safety — default==CYRIUS_IR ($def_rc)"

# (2)+(3) convergence + precision, from the liveness report on stderr
CYRIUS_IR=1 CYRIUS_IR_LIVENESS=1 "$CYCC" < "$TMP/cfg.cyr" > /dev/null 2>"$TMP/live"
report=$(grep "IR liveness:" "$TMP/live" | head -1)
if [ -z "$report" ]; then
    echo "FAIL: no 'IR liveness:' report emitted under CYRIUS_IR_LIVENESS=1"
    sed 's/^/  /' "$TMP/live" | head -5; exit 1
fi
echo "  report: $report"
iters=$(echo "$report" | sed -n 's/.* iters=\([0-9]*\).*/\1/p')
exit0=$(echo "$report" | sed -n 's/.* exit0=\([0-9]*\).*/\1/p')
bbs=$(echo "$report" | sed -n 's/.*bbs=\([0-9]*\).*/\1/p')
if [ -z "$iters" ] || [ "$iters" -lt 1 ] || [ "$iters" -ge 64 ]; then
    echo "FAIL: fixpoint iters=$iters — did not converge under the 64 cap (bail fired = a bug)"; exit 1
fi
echo "  PASS: convergence — $iters iters over $bbs BBs (< 64 cap)"
if [ -z "$exit0" ] || [ "$exit0" -lt 1 ]; then
    echo "FAIL: exit0=$exit0 — no BB got live_out==0; fixpoint not more precise than the DCE seed"; exit 1
fi
echo "  PASS: precision — $exit0 exit/return BBs have live_out==0"

# (4) spill-interval detection: the arithmetic in classify()/main() spills RAX
# via PUSH..POP (the binop shuttle) — the finder must detect ≥1 promotable
# interval (analysis-only; allocation/rewrite deferred to the re-emit-path slot).
spills=$(echo "$report" | sed -n 's/.* spills=\([0-9]*\).*/\1/p')
if [ -z "$spills" ] || [ "$spills" -lt 1 ]; then
    echo "FAIL: spills=$spills — no PUSH..POP spill interval detected in binop-heavy code"; exit 1
fi
echo "  PASS: spill detection — $spills clean intra-BB PUSH..POP intervals found"

echo "PASS: cross-BB liveness fixpoint + spill detection: converges, precise, behavior-safe (v6.3.27)"
exit 0
