#!/bin/sh
# check: serial — a timing/scaling measurement; the parallel check.sh runs it alone, after its pool (6.7.0)
# generic_definitions_scale_linear.sh — 6.7.16. Compile time is LINEAR in the number of generic fn definitions.
#
# THE DEFECT (issues/archived/2026-10-18-generic-definitions-compile-time-superlinear.md). A type parameter named in a generic
# fn's signature (`x: T`, `p: *T`) resolves through `_tn_resolve_at`, which tried every other reading first: an enum
# of that name declared further down (`_declared_later`, a scan of every token from the cursor to the end of the
# file), then an enclosing fn body (`_arr_fn_tparam`, a walk back over every earlier fn) — and only then the
# signature's own `<T>`. Each signature cost O(tokens), so N definitions cost O(N^2). Fixed: `_tn_param_check` asks
# the fn's captured type parameters first, `_tn_tparam` reads the signature before the bodies, and `_declared_later`
# reads an index of the declarations' positions (`_dlx_pos`). No verdict changes: each test only accepts. Measured
# (2026-10-20, x86_64, 1500 -> 3000 definitions, best of 1):
#
#     shape                                       before                   after
#     `fn oK<T>(x: T)` never called (the filed)   400 -> 1,507 ms (3.8x)   36 -> 62 ms (1.7x)
#     `fn oK<T>(x: *T)` never called              1,577 -> 6,225 ms (3.9x) 38 -> 67 ms
#     `fn oK<A, B>(x: A, y: B)` never called      1,017 -> 4,003 ms (3.9x) 41 -> 74 ms
#     a forwarding chain, never called            473 -> 1,785 ms (3.8x)   44 -> 80 ms
#     each generic called once at f64             979 -> 3,682 ms (3.8x)   111 -> 212 ms
#     the filed shape, CYRIUS_MONOMORPH=0         395 -> 1,502 ms (3.8x)   36 -> 62 ms
#     the non-generic control                     34 -> 60 ms
#
# ⚠ THE ACCEPTANCE IS A RATIO, NOT A WALL-CLOCK BOUND (the globals_scale_linear.sh rule): each shape is compiled at N
# and 2N, and 2N must cost under 3x N — linear is ~2x, quadratic ~4x. The two sizes are timed INTERLEAVED, five rounds
# of N-then-2N, best of each: a check.sh run beside other loads once caught one size alone in a burst (the `called` row
# 271 -> 973 ms, 3.5x, where a quiet box reads 128 -> 248 -> 495 ms for 1500 / 3000 / 6000). Timings are DATA: no
# `set -e`. Each 2N program is also RUN (exit 7): the fast path must still be the right path.
#
# MUTATION PROOF (2026-10-20, a one-edit scratch copy of src/ each, CYCC= its cycc): `_declared_later` restored to its
# scan -> RED ptr 3.8x, mono0 3.5x (a `*T` and an uncaptured T resolve through `_tn_resolve_at`); `_tn_tparam` reading
# the bodies first -> RED ptr 3.8x, mono0 3.6x; the compiler before the fix (41ca7d41c) -> RED on all six (3.7-3.9x).
# `_tn_param_check` asking `_tn_resolve_at` first again stays GREEN: the other two make that shortcut redundant.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=generic_definitions_scale_linear
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
N=1500

gen() {  # gen <shape> <n> > file — every program exits 7
    case "$1" in
      param|mono0) awk -v n="$2" 'BEGIN{for(i=0;i<n;i++) printf "fn o%d<T>(x: T): i64 { return 5; }\n", i; print "syscall(60, 7);"}' ;;
      ptr)   awk -v n="$2" 'BEGIN{for(i=0;i<n;i++) printf "fn o%d<T>(x: *T): i64 { return 5; }\n", i; print "syscall(60, 7);"}' ;;
      two)   awk -v n="$2" 'BEGIN{for(i=0;i<n;i++) printf "fn o%d<A, B>(x: A, y: B): i64 { return 5; }\n", i; print "syscall(60, 7);"}' ;;
      chain) awk -v n="$2" 'BEGIN{print "fn o0<T>(x: T): i64 { return 5; }"
                 for(i=1;i<n;i++) printf "fn o%d<T>(x: T): i64 { return o%d(x); }\n", i, i-1; print "syscall(60, 7);"}' ;;
      called) awk -v n="$2" 'BEGIN{for(i=0;i<n;i++) printf "fn o%d<T>(x: T): i64 { return sizeof(T); }\nfn c%d(): i64 { var h: f64 = 1.5; return o%d(h); }\n", i, i, i
                 print "syscall(60, c0() - 1);"}' ;;
    esac
}
once() {  # wall ms for compiling $2 under shape $1 (-1 if the compile fails)
    s=$(date +%s%N)
    if [ "$1" = mono0 ]; then
        CYRIUS_MONOMORPH=0 "$CC" < "$2" > "$2.bin" 2> "$2.err" || { echo -1; return; }
    else
        "$CC" < "$2" > "$2.bin" 2> "$2.err" || { echo -1; return; }
    fi
    echo $(( ($(date +%s%N) - s) / 1000000 ))
}
pair() {  # "T1 T2" for shape $1: the best of 5 interleaved rounds (N, then 2N); "-1 -1" if a compile fails
    b1=99999999; b2=99999999
    for _ in 1 2 3 4 5; do
        t=$(once "$1" "$D/$1.1.cyr"); [ "$t" -lt 0 ] && { echo "-1 -1"; return; }; [ "$t" -lt "$b1" ] && b1=$t
        t=$(once "$1" "$D/$1.2.cyr"); [ "$t" -lt 0 ] && { echo "-1 -1"; return; }; [ "$t" -lt "$b2" ] && b2=$t
    done
    echo "$b1 $b2"
}

NFAIL=0
for shape in param ptr two chain called mono0; do
    gen "$shape" "$N" > "$D/$shape.1.cyr"
    gen "$shape" $((N * 2)) > "$D/$shape.2.cyr"
    P=$(pair "$shape")
    T1=${P% *}
    T2=${P#* }
    if [ "$T1" -lt 0 ] || [ "$T2" -lt 0 ]; then
        echo "  FAIL: [$shape] the compile failed: $(grep -h -m1 -i error "$D/$shape.1.cyr.err" "$D/$shape.2.cyr.err" 2>/dev/null | head -1)"
        NFAIL=$((NFAIL + 1)); continue
    fi
    chmod +x "$D/$shape.2.cyr.bin"
    "$D/$shape.2.cyr.bin"; rc=$?
    if [ "$rc" != 7 ]; then
        echo "  FAIL: [$shape] the $((N * 2))-definition program exited $rc, want 7"
        NFAIL=$((NFAIL + 1)); continue
    fi
    [ "$T1" -lt 1 ] && T1=1
    R10=$(( T2 * 10 / T1 ))
    if [ "$R10" -gt 30 ]; then
        echo "  FAIL: [$shape] ${N} -> $((N * 2)) generic definitions costs ${R10}/10x (${T1}ms -> ${T2}ms, limit 3.0x) — a signature's type parameter is scanning the file again"
        NFAIL=$((NFAIL + 1))
    else
        echo "  ok: [$shape] ${T1}ms -> ${T2}ms for ${N} -> $((N * 2)) — ratio ${R10}/10 (limit 3.0)"
    fi
done
if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: $G: $NFAIL rows"
    exit 1
fi
echo "PASS $G (generic fn definitions — T, *T, two parameters, a forwarding chain, called at f64, CYRIUS_MONOMORPH=0 — compile in time linear in their count)"
exit 0
