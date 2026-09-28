#!/bin/sh
# Gate: gvar_toks — the deferred global-initializer table — GROWS past 4096 entries (6.6.9 bite 1).
#
# THE DEFECT (measured at 6.6.8). Every top-level global that does not take the static-init
# path registers one entry in gvar_toks, a FIXED 4096-entry table at 0x729000 — and the
# static-init path takes a NONZERO constant only (gvar_initval uses 0 as "no value"). So not
# just a computed initializer (`var g = f();`) but `var g = 0;`, a string literal, a byte-array
# literal and a top-level destructure all counted, and the 4097th was refused:
#
#     error:<source>:4098:11: too many initialized globals (max 4096)
#
# "initialized" was wrong about what it counted, the guide documented the counting rule wrongly
# in both directions, and the filed quadratic-globals repro (20,000 `var gN = f(N);`) could not
# pass with the cap in place. The table now starts in its 0x729000 region and moves to alloc'd
# storage, doubling, on the 4097th entry (the _grow_one shape); the per-entry slot record
# (_gv_ent_base) grows with it, and the redeclaration supersede scan — which walked EVERY entry
# per constant redeclaration and was bounded only by the cap — reads a per-name list instead.
#
# This file was gvar_toks_cap_guards_the_store.sh (6.6.6 bite 19e), which pinned the cap. Its
# lesson carries over as axis 5: the bytes past the 0x729000 region are FREE up to TS, so a
# store that runs past the region without growing changes NOTHING observable — measured here,
# a mutant with the grow removed compiles and runs 5,000, 20,000 and 120,000 deferred globals
# correctly. That is why the growth itself is pinned statically.
#
# AXES
#   1. ACCEPTANCE — each registration shape at 5000 entries compiles (rc 0, no cap text) and
#      the program reads the right values back: a computed init, `= 0`, a string literal, a
#      byte-array literal and a top-level destructure. Plus the filed repro at 20,000.
#   2. SUPERSEDE PAST 4096 — a constant redeclaration of an entry above 4096 (target 0 of a plain
#      init, and target 1 of a destructure) wins from program start while every earlier deferred
#      initializer still RUNS (its side effect counted).
#   3. KERNEL REPLAY PAST 4096 — a `kernel;` build replays the declaration zone after the
#      program registered its own globals; past 4096 entries it must still compile and store
#      into the declaration-zone slot (row K of global_redeclaration_one_definition.sh, at
#      scale: the binary must not change when the program's later `var` is renamed).
#   4. NO CAP — no "too many initialized globals" text is left in the compiler source.
#   5. STATIC — the one growing store path: exactly one gvar_cnt bump and one gvar_toks store
#      in parse_decl.cyr, both inside _gv_defer; _gv_defer grows the table past its cap; the
#      fixed 0x729000 base appears in code only as _gvt's initial value; _gv_ent_set and the
#      supersede list grow too; _gv_supersede walks the per-name list and never reads
#      gvar_cnt (its runtime twin is globals_scale_linear.sh's redecl row).
#
# MUTATION LEDGER (6.6.9, each on a scratch copy of src built with the tree's cycc):
#   1. real tree -> GREEN
#   2. the grow line removed from _gv_defer -> RED axis 5 only, 3 checks (axes 1-3 stay GREEN,
#      see above — the reason axis 5 exists)
#   3. `_gv_supersede` returns 0 immediately -> RED axis 2 (exit 19: g4500, g10 and db4700 all
#      keep their deferred value)
#   4. the 6.6.8 parse_decl.cyr (the cap) -> RED axes 1-5 (32 checks)
#   5. `_gv_supersede` restored to the 6.6.8 O(entries) `_gv_entry_hit` scan over `_gvt(S)`
#      (correct past 4096, quadratic) -> RED axis 5 only, 2 checks (axes 1-3 stay GREEN;
#      globals_scale_linear.sh's redecl row reads it at 4.0x)
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: gvar_toks_grows_past_4096: $CC missing"; exit 1; }
SRC="$ROOT/src/frontend/parse_decl.cyr"
[ -f "$SRC" ] || { echo "FAIL: $SRC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

# build + run one fixture: $1 name, $2 expected exit code of the program
run() {
    rm -f "$WORK/$1.bin"
    set +e; "$CC" < "$WORK/$1.cyr" > "$WORK/$1.bin" 2> "$WORK/$1.err"; rc=$?; set -e
    if [ "$rc" != "0" ]; then bad "$1: compiler exited $rc: $(grep -m1 -i error "$WORK/$1.err" || true)"; return 0; fi
    grep -q 'too many initialized globals' "$WORK/$1.err" && bad "$1: the cap message is still printed"
    chmod +x "$WORK/$1.bin"
    set +e; "$WORK/$1.bin" > /dev/null 2>&1; xr=$?; set -e
    [ "$xr" = "$2" ] || bad "$1: the program exited $xr, want $2"
    return 0
}

# ── axis 1: every shape past 4096 compiles and reads back ─────────────────────────────
N=5000
awk -v n=$N 'BEGIN{print "fn gtf(n: i64): i64 { return n + 1; }"
    for(i=0;i<n;i++) printf "var gtg%d = gtf(%d);\n", i, i
    printf "syscall(60, (gtg%d + gtg0 + gtg4200) & 255);\n", n-1}' > "$WORK/plain.cyr"
run plain $(( (N + 1 + 4201) & 255 ))
awk -v n=$N 'BEGIN{for(i=0;i<n;i++) printf "var gtz%d = 0;\n", i
    printf "gtz%d = 7;\nsyscall(60, gtz%d + gtz0 + gtz4500);\n", n-1, n-1}' > "$WORK/zero.cyr"
run zero 7
awk -v n=$N 'BEGIN{for(i=0;i<n;i++) printf "var gts%d = \"ab\";\n", i
    printf "syscall(60, load8(gts%d) + load8(gts0 + 1) - 190);\n", n-1}' > "$WORK/str.cyr"
run str $(( 97 + 98 - 190 ))
awk -v n=$N 'BEGIN{for(i=0;i<n;i++) printf "var gta%d[4] = { 1, 2, 3, %d };\n", i, i % 200
    printf "syscall(60, load8(&gta%d + 3) + load8(&gta0 + 2) + load8(&gta4321 + 3));\n", n-1}' > "$WORK/arr.cyr"
run arr $(( ((N - 1) % 200 + 3 + 4321 % 200) & 255 ))
awk -v n=$N 'BEGIN{print "fn gtp(): (i64, i64) { return (4, 9); }"
    for(i=0;i<n;i++) printf "var gtd%d, gte%d = gtp();\n", i, i
    printf "syscall(60, gtd%d * 10 + gte%d + gte0);\n", n-1, n-1}' > "$WORK/destr.cyr"
run destr 58
# the filed repro's shape and size (issue 2026-09-20: `var gN = f(N);` x 20,000)
awk 'BEGIN{print "fn f(n: i64): i64 { return n + 1; }"
    for(i=0;i<20000;i++) printf "var g%d = f(%d);\n", i, i
    print "syscall(60, (g19999 + g0) & 255);"}' > "$WORK/filed.cyr"
run filed $(( (20000 + 1) & 255 ))

# ── axis 2: a constant redeclaration past 4096 still supersedes ───────────────────────
awk -v n=$N 'BEGIN{print "var cnt = 0;"
    print "fn bump(v: i64): i64 { cnt = cnt + 1; return v; }"
    print "fn gtp(): (i64, i64) { return (4, 9); }"
    for(i=0;i<n;i++) printf "var g%d = bump(%d);\n", i, i + 1
    for(i=0;i<n;i++) printf "var da%d, db%d = gtp();\n", i, i
    print "var g4500 = 77;"
    print "var g10 = 66;"
    print "var db4700 = 55;"
    print "var r = 0;"
    print "if (g4500 != 77) { r = r | 1; }"
    print "if (g10 != 66) { r = r | 2; }"
    printf "if (cnt != %d) { r = r | 4; }\n", n
    printf "if (g%d != %d) { r = r | 8; }\n", n - 1, n
    print "if (db4700 != 55) { r = r | 16; }"
    print "if (da4700 != 4) { r = r | 32; }"
    print "syscall(60, r);"}' > "$WORK/sup.cyr"
run sup 0

# ── axis 3: a kernel replay past 4096 ─────────────────────────────────────────────────
for v in 1 2; do
    awk -v n=$N -v v=$v 'BEGIN{print "kernel;"; print "fn f5() { return 5; }"
        for(i=0;i<n;i++) printf "var g%d = f5();\n", i
        print "var z = 0;"; print "z = 1;"
        if (v == 1) { print "var g4800 = 3;"; print "z = g4800;" } else { print "var c = 3;"; print "z = c;" }}' > "$WORK/k$v.cyr"
    set +e; "$CC" < "$WORK/k$v.cyr" > "$WORK/k$v" 2> "$WORK/k$v.err"; krc=$?; set -e
    [ "$krc" = "0" ] || bad "axis 3: the $N-global kernel build (variant $v) exited $krc: $(grep -m1 -i error "$WORK/k$v.err" || true)"
done
if [ -s "$WORK/k1" ] && [ -s "$WORK/k2" ]; then
    cmp -s "$WORK/k1" "$WORK/k2" || bad "axis 3: the kernel replay past 4096 stored into the program's later declaration"
else
    bad "axis 3: no kernel binary"
fi

# ── axis 4: no cap left in the compiler ───────────────────────────────────────────────
# code lines only: the comment that records the retired message is history, not the cap
grep -rn 'too many initialized globals' "$ROOT/src" 2>/dev/null | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' > "$WORK/cap.txt" || true
if [ -s "$WORK/cap.txt" ]; then
    bad "axis 4: the cap message is still in the compiler: $(head -1 "$WORK/cap.txt")"
fi

# ── axis 5: the one growing store path ────────────────────────────────────────────────
awk '
  /^fn [A-Za-z_0-9]+\(/ { fn = $2; sub(/\(.*/, "", fn) }
  /^[ \t]*#/ { next }
  /S64\(S \+ 0x19A000, / { bumps++; if (fn != "_gv_defer") printf "BUMP_OUTSIDE %s %d\n", fn, NR }
  /, sti\);/ && /S64\(/ { stores++; if (fn != "_gv_defer") printf "STORE_OUTSIDE %s %d\n", fn, NR }
  /0x729000/ { fixed++; if (fn != "_gvt") printf "FIXED_OUTSIDE %s %d\n", fn, NR }
  END { printf "COUNTS %d %d %d\n", bumps, stores, fixed }
' "$SRC" > "$WORK/a5.txt"
while read -r kind fn ln; do
    case "$kind" in
      BUMP_OUTSIDE)  bad "axis 5: gvar_cnt bumped outside _gv_defer ($fn, parse_decl.cyr:$ln)" ;;
      STORE_OUTSIDE) bad "axis 5: gvar_toks stored outside _gv_defer ($fn, parse_decl.cyr:$ln)" ;;
      FIXED_OUTSIDE) bad "axis 5: the fixed 0x729000 base used outside _gvt ($fn, parse_decl.cyr:$ln)" ;;
    esac
done < "$WORK/a5.txt"
set -- $(grep '^COUNTS' "$WORK/a5.txt")
[ "$2" = "1" ] || bad "axis 5: $2 gvar_cnt bumps in parse_decl.cyr, want exactly 1 (in _gv_defer)"
[ "$3" = "1" ] || bad "axis 5: $3 gvar_toks registration stores, want exactly 1 (in _gv_defer)"
[ "$4" = "1" ] || bad "axis 5: the 0x729000 base appears $4 times in code, want exactly 1 (_gvt)"
body() { awk -v f="$1" '$0 ~ "^fn " f "\\(" {on=1} on {print} on && /^}/ {exit}' "$SRC"; }
body _gv_defer > "$WORK/defer.txt"
grep -q 'if (gc >= _gvt_cap)' "$WORK/defer.txt" || bad "axis 5: _gv_defer no longer tests the count against _gvt_cap"
grep -q '_grow_one(b, _gvt_cap)' "$WORK/defer.txt" || bad "axis 5: _gv_defer no longer grows the table"
grep -q '_gvt_cap = _gvt_cap \* 2' "$WORK/defer.txt" || bad "axis 5: _gv_defer no longer doubles _gvt_cap"
grep -q '_gvx_note(S, gc, sti)' "$WORK/defer.txt" || bad "axis 5: _gv_defer no longer records the entry's names for _gv_supersede"
body _gv_ent_set | grep -q '_grow_one(_gv_ent_base, _gv_ent_cap)' || bad "axis 5: _gv_ent_set no longer grows with the table"
body _gvx_rec1 | grep -q '_gvx_grow()' || bad "axis 5: the supersede list no longer grows"
# _gv_supersede reads the per-name list, never the whole table: with the cap gone, a scan
# bounded by gvar_cnt (0x19A000) is O(entries) per constant redeclaration — quadratic, and
# still CORRECT, so only this axis and globals_scale_linear.sh's redecl row can see it.
body _gv_supersede > "$WORK/sup.txt"
grep -q '0x19A000' "$WORK/sup.txt" && bad "axis 5: _gv_supersede reads gvar_cnt (0x19A000) — it is scanning every deferred entry again"
grep -q '_nm_get(S, _gvx_m, noff)' "$WORK/sup.txt" || bad "axis 5: _gv_supersede no longer walks the per-name _gvx list"

if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: gvar_toks_grows_past_4096: $NFAIL checks"
    exit 1
fi
echo "PASS: gvar_toks grows past 4096 (5 shapes at $N + the 20,000 repro run; supersede and kernel replay past 4096; one growing store path)"
exit 0
