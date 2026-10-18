#!/bin/sh
# check: serial — a timing/scaling measurement; the parallel check.sh runs it alone, after its pool (6.7.0)
# dce_seed_pass_linear.sh — 6.7.15. FIXUP's dead-code seed pass costs O(call sites + fns log fns),
# not O(call sites x fns), on the x86 and the aarch64 backend — and it answers exactly as before.
#
# THE DEFECT (issues/2026-10-16-dce-seed-pass-host-scan-quadratic.md). Every x86 and aarch64
# build runs the reachability walk (the `N unreachable fns` note needs it, CYRIUS_DCE or not). Its
# seed pass asks, for each call to a fn start, whether the call site lies inside a fn (else it is
# a root), and asked `_dce_host_fn` — a scan of the whole fn table — each time. The filed program
# (n live fns, n dead fns, main calling each live one once) spent, on a box at load ~14:
#
#     n         2,000    4,000    8,000    16,000     fixup (CYRIUS_PROF, x86)
#     6.7.14    113 ms   403 ms   1,984 ms 9,934 ms   — x88 for 8x the fns
#     6.7.15     29 ms    48 ms      48 ms   114 ms   — x3.9
#
# and cycc's own self-compile spent fixup=1,267 ms of its compile in it (169 ms after). The aarch64
# cross compiler, wall clock: 340 ms -> 8,696 ms (x25) before, 184 ms -> 745 ms (x4) after.
# `_dce_cover_build` (backend/common/runtime.cyr) merges every fn's [start, end) into disjoint
# ranges once per FIXUP and `_dce_in_any_fn` binary-searches them.
#
# ⚠ THE ACCEPTANCE IS A RATIO, NOT A WALL-CLOCK BOUND (the lexid_buckets_by_content.sh rule): the
# two sizes are compiled back to back, best of 5 each, so shared load cancels. 8x the fns must cost
# under 10x in FIXUP — ~4-6x here, the quadratic ~50-90x. Timings are DATA: no `set -e`.
#
# ROWS
#   L1  x86: the filed generator at n = 2,000 and 16,000 — FIXUP (CYRIUS_PROF's fixup=) under 10x;
#       both compile, the 16,000 binary exits 16000 & 255 = 128 and the note counts 16000
#       unreachable fns (every d<i>: main is a root, so every l<i> is live).
#   L2  aarch64 (the cross compiler from src/main_aarch64.cyr): CYRIUS_PROF is wired in main.cyr
#       alone, and the whole compile grows ~9x for 8x the fns on both backends (the front end's
#       gvar phase is a little worse than linear), too close to a growth limit. So the cross
#       compiler's wall clock on the 16,000-fn program is held against the x86 compiler's on the
#       same input, interleaved, best of 5: the front ends are the same code, and with L1 green
#       the x86 time is linear. Under 3x (measured 0.8x; 6.7.14's aarch64 seed pass 5-7x). The
#       same note; the 16,000 binary exits 128 under qemu-aarch64 when it is installed.
#   E   exactness, x86 and aarch64: a call after a generic instance emitted INSIDE a dead fn
#       (`_instantiate_generic_fn` nests the instance's range in its host's; CYRIUS_SYMS shows
#       gid$i8 starting inside outer(), or the row proves nothing) lies inside the host, so its
#       callee is no root — `only_y` and the instance itself are listed dead — and the call from
#       the top level keeps `main` live (exit 42). Merging ranges must keep the outer end.
#
# MUTATION PROOF (6.7.15, each on a scratch copy of src/): the 6.7.14 runtime.cyr and both fixups
# (the per-site `_dce_host_fn` scan) -> L1 RED (FIXUP 133 -> 7,829 ms, x58.8; L2 reads 0.9x then,
# both backends equally slow — L1 is the x86 row); only the 6.7.14 aarch64 fixup -> L2 RED alone
# (6,106 vs 720 ms, 8.4x); `_dce_cover_merge` taking each later range's end even when it is the
# shorter one (a nested instance cut its host's range short) -> E RED on x86 and aarch64 (`only_y`
# and `gid$i8` not dead).
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: dce_seed_pass_linear: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: dce_seed_pass_linear: $CC missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: dce_seed_pass_linear: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT

"$CC" < "$ROOT/src/main.cyr" > "$D/stage1" 2> "$D/s1.err" && [ -s "$D/stage1" ] || {
  echo "FAIL: dce_seed_pass_linear: cannot build src/main.cyr"; sed -n 1,3p "$D/s1.err"; exit 1; }
chmod +x "$D/stage1"
"$D/stage1" < "$ROOT/src/main_aarch64.cyr" > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ] || {
  echo "FAIL: dce_seed_pass_linear: cannot build src/main_aarch64.cyr"; exit 1; }
chmod +x "$D/cc_a64"

gen() {  # the filed generator, verbatim: n live fns, n dead fns, main calling each live one once
  awk -v n=$1 'BEGIN { for (i = 0; i < n; i++) { printf "fn d%d(): i64 { return %d; }\n", i, i; printf "fn l%d(x): i64 { return x + 1; }\n", i }
  print "fn main(): i64 { var x = 0;"; for (i = 0; i < n; i++) printf "  x = l%d(x);\n", i
  print "  return x & 255; }"; print "var e = main();"; print "syscall(60, e);" }'
}
gen 2000 > "$D/q1.cyr"
gen 16000 > "$D/q2.cyr"

NFAIL=0
fail() { echo "  FAIL: $*"; NFAIL=$((NFAIL + 1)); }

fixup_best() {  # best-of-5 FIXUP ms (CYRIUS_PROF) compiling $1 to $1.x86; -1 when a compile fails or prints no fixup=
  b=99999999
  for _ in 1 2 3 4 5; do
    CYRIUS_PROF=1 "$D/stage1" < "$1" > "$1.x86" 2> "$1.x86.err" || { echo -1; return; }
    f=$(sed -n 's/.*[( ]fixup=\([0-9]*\).*/\1/p' "$1.x86.err" | head -1)
    [ -n "$f" ] || { echo -1; return; }
    [ "$f" -lt "$b" ] && b=$f
  done
  echo "$b"
}
ms_since() { echo $(( ($(date +%s%N) - $1) / 1000000 )); }
wall_pair() {  # best-of-5 wall ms of the aarch64 cross and of the x86 compiler on $1, interleaved:
  #              sets WA / WX (-1 when a compile fails); the outputs are $1.a64 and $1.x86w
  WA=99999999; WX=99999999
  for _ in 1 2 3 4 5; do
    s=$(date +%s%N)
    "$D/cc_a64" < "$1" > "$1.a64" 2> "$1.a64.err" || { WA=-1; return; }
    e=$(ms_since "$s"); [ "$e" -lt "$WA" ] && WA=$e
    s=$(date +%s%N)
    "$D/stage1" < "$1" > "$1.x86w" 2> /dev/null || { WX=-1; return; }
    e=$(ms_since "$s"); [ "$e" -lt "$WX" ] && WX=$e
  done
}
note_is() {  # <errfile> <n>: the note counts exactly n unreachable fns
  grep -q "^note: $2 unreachable fns " "$1"
}

# ── L1: x86 ──────────────────────────────────────────────────────────────────────────────
F1=$(fixup_best "$D/q1.cyr")
F2=$(fixup_best "$D/q2.cyr")
if [ "$F1" -lt 0 ] || [ "$F2" -lt 0 ]; then
  fail "L1 x86: a generator compile failed or CYRIUS_PROF printed no fixup= ($(head -c 200 "$D/q2.cyr.x86.err"))"
else
  [ "$F1" -lt 1 ] && F1=1
  R10=$(( F2 * 10 / F1 ))
  if [ "$R10" -ge 100 ]; then
    fail "L1 x86: FIXUP ${F1}ms at 2,000 fns -> ${F2}ms at 16,000 — ${R10}/10x (limit 10x): the seed pass is scanning the fn table per call site again"
  else
    echo "  ok: L1 x86 FIXUP ${F1}ms -> ${F2}ms for 2,000 -> 16,000 fns — ${R10}/10x (limit 10x)"
  fi
  note_is "$D/q2.cyr.x86.err" 16000 || fail "L1 x86: the note does not count 16000 unreachable fns: $(grep '^note:' "$D/q2.cyr.x86.err")"
  chmod +x "$D/q2.cyr.x86"; got=0; "$D/q2.cyr.x86" || got=$?
  [ "$got" = 128 ] || fail "L1 x86: the 16,000-fn program exits $got, want 128"
fi

# ── L2: aarch64 ──────────────────────────────────────────────────────────────────────────
wall_pair "$D/q2.cyr"
if [ "$WA" -lt 0 ] || [ "$WX" -lt 0 ]; then
  fail "L2 aarch64: a 16,000-fn compile failed ($(head -c 200 "$D/q2.cyr.a64.err"))"
else
  [ "$WX" -lt 1 ] && WX=1
  R10=$(( WA * 10 / WX ))
  if [ "$R10" -ge 30 ]; then
    fail "L2 aarch64: the cross compiler takes ${WA}ms on 16,000 fns against the x86 compiler's ${WX}ms — ${R10}/10x (limit 3x): its seed pass is scanning the fn table per call site again"
  else
    echo "  ok: L2 aarch64 ${WA}ms vs x86 ${WX}ms on 16,000 fns — ${R10}/10x (limit 3x)"
  fi
  note_is "$D/q2.cyr.a64.err" 16000 || fail "L2 aarch64: the note does not count 16000 unreachable fns: $(grep '^note:' "$D/q2.cyr.a64.err")"
  if command -v qemu-aarch64 > /dev/null 2>&1; then
    chmod +x "$D/q2.cyr.a64"; got=0; timeout 60 qemu-aarch64 "$D/q2.cyr.a64" || got=$?
    [ "$got" = 128 ] || fail "L2 aarch64: the 16,000-fn program exits $got under qemu-aarch64, want 128"
  else
    echo "  SKIP: L2 aarch64 run — qemu-aarch64 not installed (the timing and the note rows ran)"
  fi
fi

# ── E: exactness — a call after a nested generic instance is still inside its host ─────────
cat > "$D/nest.cyr" <<'EOF'
fn gid<T>(x: T) { var y: T = x; return y; }
fn only_y(): i64 { return 7; }
fn outer(): i64 { var a = gid<i8>(3); return only_y() + a; }
fn main(): i64 { return 42; }
var r = main();
syscall(60, r);
EOF
sym() {  # <symfile> <name>: the fn's start, as a decimal number
  a=$(awk -v n="$2" '$2 == n { print $1 }' "$1" | head -1)
  [ -n "$a" ] && echo $((0x$a))
}
erow() {  # <leg> <compiler> <runner...>
  leg=$1; cc=$2; shift 2
  CYRIUS_SYMS="$D/nest.$leg.syms" CYRIUS_DCE_VERBOSE=1 "$cc" < "$D/nest.cyr" > "$D/nest.$leg" 2> "$D/nest.$leg.err" || {
    fail "E $leg: the probe did not compile: $(head -c 200 "$D/nest.$leg.err")"; return; }
  so=$(sym "$D/nest.$leg.syms" outer); si=$(sym "$D/nest.$leg.syms" 'gid$i8'); sm=$(sym "$D/nest.$leg.syms" main)
  if [ -z "$so" ] || [ -z "$si" ] || [ -z "$sm" ] || [ "$si" -le "$so" ] || [ "$si" -ge "$sm" ]; then
    fail "E $leg: gid\$i8 does not start inside outer() (CYRIUS_SYMS: $(tr '\n' ' ' < "$D/nest.$leg.syms")) — the probe has no nested range, the row proves nothing"; return
  fi
  for f in only_y 'gid$i8'; do
    grep -qxF "  dead: $f" "$D/nest.$leg.err" || fail "E $leg: $f, called only from the dead outer() after the instance nested in it, is not dead: $(tr '\n' ' ' < "$D/nest.$leg.err")"
  done
  if grep -qxF '  dead: main' "$D/nest.$leg.err"; then fail "E $leg: main, called from the top level, is listed dead"; fi
  if [ $# -gt 0 ]; then
    chmod +x "$D/nest.$leg"; got=0; "$@" "$D/nest.$leg" || got=$?
    [ "$got" = 42 ] || fail "E $leg: the probe exits $got, want 42"
  fi
}
erow x86 "$D/stage1" env
if command -v qemu-aarch64 > /dev/null 2>&1; then
  erow aarch64 "$D/cc_a64" timeout 20 qemu-aarch64
else
  erow aarch64 "$D/cc_a64"
  echo "  SKIP: E aarch64 run — qemu-aarch64 not installed (the dead-list rows ran)"
fi
[ "$NFAIL" -eq 0 ] && echo "  ok: E only_y and gid\$i8 dead after the instance nested in outer(), main live (x86, aarch64)"

if [ "$NFAIL" -gt 0 ]; then
  echo "FAIL: dce_seed_pass_linear: $NFAIL rows"
  exit 1
fi
echo "PASS dce_seed_pass_linear (the DCE seed pass is linear in the fn count on x86 and aarch64, and exact)"
exit 0
