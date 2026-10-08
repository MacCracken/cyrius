#!/bin/sh
# check: serial — a timing/scaling measurement; the parallel check.sh runs it alone, after its pool (6.7.0)
# globals_scale_linear.sh — 6.6.9 bite 1. Compile time is LINEAR in the number of globals.
#
# THE DEFECT (issue 2026-09-20, measured at 6.6.8). The global var table had no name index:
# `_findvar_core` (every global reference, plus the sit_shadow probe, CHKDUPVAL,
# CHK_ENUM_SHADOW and the enum pass-2 store) and `_gv_prior` (the one-global-per-name fold)
# each walked EVERY registered global with STREQ. Each new top-level global or enum member paid
# at least two full walks, so N registrations cost O(N²):
#
#     shape                  10k       20k
#     constant globals     1185 ms   4879 ms     (99 % of it in the gvar phase)
#     enum members         1212 ms   5060 ms
#     deferred `= f(N)`    refused past 4096 ("too many initialized globals")
#
# Fixed with an alloc'd FNV-1a name index (parse_types.cyr, _fvh_*), a growing gvar_toks and a
# per-name supersede list (parse_decl.cyr). After: 20k constants 90 ms, 20k enum members 78 ms,
# 20k deferred 135 ms.
#
# ⚠ THE ACCEPTANCE IS A RATIO, NOT A WALL-CLOCK BOUND (the lexid_buckets_by_content.sh rule):
# an absolute ms bound measures the box. Each shape is compiled at N and 2N back to back, best
# of 3 each, and 2N must cost under 3x N — linear is ~2x, quadratic ~4x. Timings are DATA:
# no `set -e`.
#
# ROWS: constant globals, enum members, deferred initializers (`var gN = f(N);` — the filed
# repro's shape, which also needs the 4096 cap gone), REFERENCES (N globals each read once
# from a fn body — FINDVAR's reverse walk made every read of an early global O(N)), and
# REDECLARATIONS (N deferred globals, then each redeclared `= 7;` — every constant
# redeclaration calls `_gv_supersede`, which at 6.6.8 scanned EVERY deferred entry with
# `_gv_entry_hit`. The cap bounded that scan at 4096; lifting the cap exposed it as the next
# quadratic, and the per-name `_gvx_*` list is what keeps it linear).
#
# MUTATION PROOF (6.6.9): `_findvar_core` restored to the reverse STREQ walk (index kept for
# `_gv_prior`) -> RED on the const/enum/defer/ref rows (~4.0x each); `_gv_supersede` restored
# to the 6.6.8 O(entries) `_gv_entry_hit` scan (reading `_gvt(S)`, so it stays CORRECT past
# 4096 — the program still exits 14) -> RED on the redecl row only (10k 3,431 ms -> 20k
# 13,828 ms, 4.0x; the tree reads 111 -> 212 ms); the 6.6.8 compiler -> RED on all five (the
# deferred and redecl rows refuse past 4096).
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: globals_scale_linear: $CC missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: globals_scale_linear: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
N=10000

gen() {  # gen shape n > file
    case "$1" in
      const) awk -v n="$2" 'BEGIN{for(i=0;i<n;i++) printf "var g%d = %d;\n", i, i+1; printf "syscall(60, g%d & 255);\n", n-1}' ;;
      enum)  awk -v n="$2" 'BEGIN{print "enum E {"; for(i=0;i<n;i++) printf "    E%d = %d;\n", i, i+1; print "}"; printf "syscall(60, E%d & 255);\n", n-1}' ;;
      defer) awk -v n="$2" 'BEGIN{print "fn f(n: i64): i64 { return n + 1; }"; for(i=0;i<n;i++) printf "var g%d = f(%d);\n", i, i; printf "syscall(60, g%d & 255);\n", n-1}' ;;
      ref)   awk -v n="$2" 'BEGIN{for(i=0;i<n;i++) printf "var g%d = %d;\n", i, i+1
                 print "fn sum(): i64 {"; print "    var s = 0;"
                 for(i=0;i<n;i++) printf "    s = s + g%d;\n", i
                 print "    return s;"; print "}"; print "syscall(60, sum() & 255);"}' ;;
      redecl) awk -v n="$2" 'BEGIN{print "fn f(n: i64): i64 { return n + 1; }"
                 for(i=0;i<n;i++) printf "var g%d = f(%d);\n", i, i
                 for(i=0;i<n;i++) printf "var g%d = 7;\n", i
                 printf "syscall(60, (g0 + g%d) & 255);\n", n-1}' ;;
    esac
}
want() {  # the exit code each program must produce at size $2
    case "$1" in
      ref) echo $(( ($2 * ($2 + 1) / 2) & 255 )) ;;
      redecl) echo 14 ;;
      *)   echo $(( $2 & 255 )) ;;
    esac
}
best() {  # best-of-3 wall ms for compiling $1 (-1 if any compile fails)
    b=99999999
    for _ in 1 2 3; do
        s=$(date +%s%N)
        "$CC" < "$1" > "$1.bin" 2> "$1.err" || { echo -1; return; }
        e=$(( ($(date +%s%N) - s) / 1000000 ))
        [ "$e" -lt "$b" ] && b=$e
    done
    echo "$b"
}

NFAIL=0
for shape in const enum defer ref redecl; do
    gen "$shape" "$N" > "$D/$shape.1.cyr"
    gen "$shape" $((N * 2)) > "$D/$shape.2.cyr"
    T1=$(best "$D/$shape.1.cyr")
    T2=$(best "$D/$shape.2.cyr")
    if [ "$T1" -lt 0 ] || [ "$T2" -lt 0 ]; then
        echo "  FAIL: [$shape] the compile failed: $(grep -h -m1 -i error "$D/$shape.1.cyr.err" "$D/$shape.2.cyr.err" 2>/dev/null | head -1)"
        NFAIL=$((NFAIL + 1)); continue
    fi
    # the fast path must still be the RIGHT path: run the 2N program
    chmod +x "$D/$shape.2.cyr.bin"
    "$D/$shape.2.cyr.bin"; rc=$?
    w=$(want "$shape" $((N * 2)))
    if [ "$rc" != "$w" ]; then
        echo "  FAIL: [$shape] the $((N * 2))-global program exited $rc, want $w"
        NFAIL=$((NFAIL + 1)); continue
    fi
    [ "$T1" -lt 1 ] && T1=1
    R10=$(( T2 * 10 / T1 ))
    if [ "$R10" -gt 30 ]; then
        echo "  FAIL: [$shape] ${N} -> $((N * 2)) globals costs ${R10}/10x (${T1}ms -> ${T2}ms, limit 3.0x) — registration or lookup is scanning the whole var table again"
        NFAIL=$((NFAIL + 1))
    else
        echo "  ok: [$shape] ${T1}ms -> ${T2}ms for ${N} -> $((N * 2)) — ratio ${R10}/10 (limit 3.0)"
    fi
done
if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: globals_scale_linear: $NFAIL rows"
    exit 1
fi
echo "PASS globals_scale_linear (const / enum / deferred / reference / redeclaration compile time linear in the global count)"
exit 0
