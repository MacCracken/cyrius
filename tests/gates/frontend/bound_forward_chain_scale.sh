#!/bin/sh
# check: serial — a timing/scaling measurement; the parallel check.sh runs it alone, after its pool (6.7.0)
# bound_forward_chain_scale.sh — 6.7.15. The bounded-forward judgement costs about nothing per generic, at any depth.
#
# THE DEFECT (issues/2026-10-17-bounded-forward-judgement-capped-at-64-deep.md). A generic forwarding its T to a
# generic whose i64 base is bad for its bound has no i64 instance either (6.7.14, `_bnd_base_bad` -> `_bbs_fwd_bad`).
# The judgement walked the forwards afresh at every asking (each base, each call site), so a chain of N forwarders
# cost N^2 scans, and a depth cap of 64 kept that bounded by answering "not bad" past it: a valid 66-deep chain was
# refused at a definition. The verdict is memoised per generic now and the cap is gone (the correctness rows are
# trait_bounds_checked.sh F12-F15e); this gate is the cost half. Measured (2026-10-18, x86_64, best of 3):
#
#     shape                                        capped (6.7.14)   uncapped, no memo   memoised
#     1500 forwards, never called                  895 ms (refused)  4,797 ms            644 ms
#     the same, defined deepest first              896 ms (refused)  5,359 ms            640 ms
#     3000 forwards called at f64 (nesting refusal) 3,412 ms          32,966 ms           2,356 ms
#     the same chains with no bound (the floor)    721 / 721 / 2,543 ms
#
# ⚠ THE ACCEPTANCE IS A RATIO, NOT A WALL-CLOCK BOUND (the globals_scale_linear.sh rule): each bounded chain against
# the SAME chain with the bound removed (no judgement runs at all), best of 3 each (T3 2); the bounded one must cost under
# 2x it — memoised ~0.9x, a quadratic judgement 6-14x. The chain without a bound is itself superlinear in the number
# of generic definitions (a pre-existing cost, filed), which a ratio against it cancels out. Timings are DATA: no
# `set -e`.
#
# ROWS: T1 a 1500-deep chain never called (each base is judged at its definition) in source order, T2 defined deepest
# first (the first judgement walks the whole chain), T3 the filed 3000-deep chain called at f64, whose one error is
# the instance-nesting refusal (no definition refused).
#
# MUTATION PROOF (2026-10-18, a one-edit scratch copy of src/ each, CYCC= its cycc): `_bbm_get` answering -1 (no memo,
# no cap) -> RED T1 T2 T3 (7.2x / 7.1x / 15.3x); the 6.7.14 compiler -> RED T1 T2 (refused at o65's definition) and T3
# (two errors).
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=bound_forward_chain_scale
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
cd "$ROOT" || exit 1

# chain <n> <order: fwd|rev> <bound: 1|0> <call: 0|1>: o0 -> gb, oK -> oK-1, gb bounded by Show (only impl Show for f64)
# or not bounded at all; never called, or o<n-1>(h) at f64.
chain() {
    if [ "$3" = 1 ]; then
        printf 'include "lib/syscalls.cyr"\ntrait Show { fn show(self): i64; }\nimpl Show for f64 { fn show(self): i64 { return 5; } }\nfn gb<T: Show>(x: T): i64 { return x.show(); }\n'
    else
        printf 'include "lib/syscalls.cyr"\nfn gb<T>(x: T): i64 { return 5; }\n'
    fi
    awk -v n="$1" -v o="$2" 'BEGIN{
        if (o == "rev") { for (k = n - 1; k >= 1; k--) printf "fn o%d<T>(x: T): i64 { return o%d(x); }\n", k, k - 1; print "fn o0<T>(x: T): i64 { return gb(x); }" }
        else { print "fn o0<T>(x: T): i64 { return gb(x); }"; for (k = 1; k < n; k++) printf "fn o%d<T>(x: T): i64 { return o%d(x); }\n", k, k - 1 } }'
    if [ "$4" = 1 ]; then printf 'fn main(): i64 { var h: f64 = 1.5; return o%d(h); }\nsyscall(60, main());\n' $(($1 - 1))
    else printf 'syscall(60, 7);\n'; fi
}
best() {  # best-of-<$2> wall ms for compiling $1; RC = the last compile's exit status
    b=99999999
    for _ in $(seq "$2"); do
        s=$(date +%s%N)
        RC=0; "$CC" < "$1" > "$1.bin" 2> "$1.err" || RC=$?
        e=$(( ($(date +%s%N) - s) / 1000000 ))
        [ "$e" -lt "$b" ] && b=$e
    done
    echo "$b" > "$1.ms"
    return 0
}

NFAIL=0
row() {  # <id> <n> <order> <call> <what> <runs>
    chain "$2" "$3" 1 "$4" > "$D/$1.b.cyr"
    chain "$2" "$3" 0 "$4" > "$D/$1.u.cyr"
    best "$D/$1.b.cyr" "$6"; RB=$RC
    best "$D/$1.u.cyr" "$6"
    TB=$(cat "$D/$1.b.cyr.ms"); TU=$(cat "$D/$1.u.cyr.ms")
    if [ "$4" = 0 ]; then
        if [ "$RB" -ne 0 ]; then
            echo "  FAIL: [$1] $5: refused (rc $RB): $(grep -m1 '^error' "$D/$1.b.cyr.err")"
            NFAIL=$((NFAIL + 1)); return
        fi
    else
        ne=$(grep -c '^error' "$D/$1.b.cyr.err" || true)
        if [ "$RB" -eq 0 ] || [ "$ne" -ne 1 ] || ! grep -q "nesting too deep (over 256 levels" "$D/$1.b.cyr.err"; then
            echo "  FAIL: [$1] $5: not the nesting refusal alone (rc $RB, $ne errors): $(grep '^error' "$D/$1.b.cyr.err" | head -2 | tr '\n' '|')"
            NFAIL=$((NFAIL + 1)); return
        fi
    fi
    [ "$TU" -lt 1 ] && TU=1
    R10=$(( TB * 10 / TU ))
    if [ "$R10" -ge 20 ]; then
        echo "  FAIL: [$1] $5: ${TB}ms against ${TU}ms with no bound — ${R10}/10x (limit 2.0x): the judgement is walking the chain again"
        NFAIL=$((NFAIL + 1))
    else
        echo "  ok: [$1] $5: ${TB}ms against ${TU}ms with no bound — ratio ${R10}/10 (limit 2.0)"
    fi
}
row T1 1500 fwd 0 "1500 forwards, never called" 3
row T2 1500 rev 0 "1500 forwards defined deepest first, never called" 3
row T3 3000 fwd 1 "the filed 3000-deep chain called at f64" 2
if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: $G: $NFAIL rows"
    exit 1
fi
echo "PASS $G (the bounded-forward judgement of a 1500- / 3000-deep chain costs under 2x the same chain with no bound, either definition order)"
exit 0
