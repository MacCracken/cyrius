#!/bin/sh
# dce_eliminates.sh — v6.5.72. `CYRIUS_DCE=1` REMOVES dead code instead of padding it.
#
# ⛔ WHY. The flag found unreachable functions, overwrote their bodies with 0x90, and reclaimed
# ZERO bytes — while the default-path message told users to "set CYRIUS_DCE=1 to eliminate".
# Measured before this release: 76 unreachable fns, 34,847 bytes, recognised, padded, shipped,
# binary byte-for-byte the same size. The pass's own comment called that an "intentional
# tradeoff" because "code shifting would break cycc==cycc byte-identity" — which v6.5.68
# disproved: compaction is deterministic, so a compacted compiler reaches the same fixpoint.
#
# ⭐ AXIS 2 IS THE LOAD-BEARING ONE. Moving code invalidates every stored code position, and one
# unrepaired table is a silent miscompile. It took four attempts and six distinct causes:
#   1. a binary search (`_wp_inside`) called before its table was sorted;
#   2. `dbase` recomputed after compaction — data does NOT follow code (`.rodata`/`.bss` land at
#      identical vaddrs either way), so recomputing relocated every data reference;
#   3. the fixup patch loop extracted into its own function — which breaks the SEED chain, cybs
#      cannot compile it — so the sites are repaired arithmetically instead;
#   4. the position registries gated on `IR_ENABLED`, correct when written and silently EMPTY
#      for this new consumer;
#   5. the fixup repair placed AFTER the CP shift, so it wrote at post-compaction coordinates
#      into a buffer that had not moved (3 corrupted bodies in a 5-line program, 147 in cycc);
#   6. ftype-3 fixups — absolute function ADDRESSES behind indirect calls — never repaired,
#      which no body-level check can see because every body still decodes.
# A byte count proves the pass ran. Only compiling WITH the result proves it was repaired.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || { echo "FAIL: dce_eliminates: cannot cd to $R"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: dce_eliminates: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL dce_eliminates: no build/cycc"; exit 1; }

"$CC" < "$R/src/main.cyr" > "$T/stage1" 2>"$T/e1" || {
  echo "FAIL dce_eliminates: stage1 build failed"; sed -n 1,3p "$T/e1"; exit 1; }
chmod +x "$T/stage1"

# ── axis 1 — the binary actually SHRINKS ────────────────────────────────────────────────
CYRIUS_DCE=1 "$T/stage1" < "$R/src/main.cyr" > "$T/dce" 2>"$T/e2" || {
  echo "FAIL dce_eliminates axis1: the DCE build failed"; sed -n 1,3p "$T/e2"; exit 1; }
chmod +x "$T/dce"
grep -qa 'bytes of dead code eliminated' "$T/e2" || {
  echo "FAIL dce_eliminates axis1: no elimination line — the pass did not run."; exit 1; }
# 6.6.20: the floor is DERIVED from the bytes the pass reports eliminating, and measured on the
# text segment. The fixed `>= 16384` file-size floor that stood here was cycc's own dead code at
# v6.5.72 (36,864 B reclaimed); the 6.6.20 dead-code pass left ~10 KB to eliminate, and the file
# moves in 4 KB pages, so the same healthy pass read 8,192 and failed. The R E segment's p_filesz
# (program header 0) shrinks by the eliminated bytes, to alignment. CHANGELOG [6.6.20]
ELIM=$(grep -a 'bytes of dead code eliminated' "$T/e2" | grep -o '[0-9][0-9]*' | head -1)
[ "${ELIM:-0}" -gt 0 ] || { echo "FAIL dce_eliminates axis1: the pass reports eliminating ${ELIM:-no} bytes"; exit 1; }
_text_filesz() {   # $1 = ELF64; prints phdr[0].p_filesz, or nothing unless phdr[0] is the R E PT_LOAD
  _ph=$(od -An -t u8 -j 32 -N 8 "$1" | tr -d ' ')
  [ "$(od -An -t u4 -j "$_ph" -N 4 "$1" | tr -d ' ')" = 1 ] || return 0
  [ "$(od -An -t u4 -j $((_ph + 4)) -N 4 "$1" | tr -d ' ')" = 5 ] || return 0
  od -An -t u8 -j $((_ph + 32)) -N 8 "$1" | tr -d ' '
}
TP=$(_text_filesz "$T/stage1"); TD=$(_text_filesz "$T/dce")
[ -n "$TP" ] && [ -n "$TD" ] || { echo "FAIL dce_eliminates axis1: program header 0 is not the R E PT_LOAD"; exit 1; }
SAVED=$(( TP - TD ))
[ $(( SAVED * 2 )) -ge "$ELIM" ] || {
  echo "FAIL dce_eliminates axis1: the text segment shrank $SAVED B ($TP -> $TD) for $ELIM B reported"
  echo "  eliminated — dead code was reported eliminated but did not leave the binary. That is the"
  echo "  pre-v6.5.72 behaviour: NOP-fill."
  exit 1; }

# ── axis 2 — THE REAL ASSERTION: the eliminated compiler WORKS and is byte-exact ─────────
# Exit statuses are captured with `|| rc=$?`, never `cmd; rc=$?`: under `bash -eo pipefail`
# (how CLAUDE.md says gates must also pass) a non-zero `cmd` ends the gate right there — the
# axis-3 probe exits 7 BY DESIGN, so this gate exited 7 silently under bash. CHANGELOG [6.6.20]
rc=0
"$T/dce" < "$R/src/main.cyr" > "$T/dceout" 2>"$T/e3" || rc=$?
[ $rc -eq 0 ] || {
  echo "FAIL dce_eliminates axis2: the eliminated cycc cannot compile (rc=$rc)."
  echo "  rc=139 -> a position table was moved without being repaired."
  echo "  rc=132 -> an indirect call target is stale (ftype-3 fixups)."
  sed -n 1,3p "$T/e3"; exit 1; }
cmp -s "$T/dceout" "$T/stage1" || {
  echo "FAIL dce_eliminates axis2: the eliminated cycc does not reproduce the normal build."
  echo "  Elimination changed WHAT the compiler emits, not just where it sits."
  exit 1; }

# ── axis 3 — the SELF-AUDIT is present and is BASELINE-RELATIVE ──────────────────────────
# The pass walks every surviving live body with the length decoder and refuses to emit if one
# stopped decoding. ⚠ It must compare against a pre-elimination baseline: the first cut
# asserted absolutely and blocked 240 of 301 corpus programs, every one of them for a DECODER
# gap (`fmt_float_buf` uses `0F 3A` roundsd) rather than for corruption. This row pins that a
# float-formatting program — the one that exposed that gap — still compiles under DCE.
cat > "$T/a3.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    alloc_init();
    # `fmt_float` is the point: its body is what carries `0F 3A` (roundsd), the opcode the
    # length decoder bailed on until v6.5.72. The RESULT is irrelevant here — the exit code is
    # fixed so the row compares compile-and-run behaviour, not floating-point formatting.
    var s = fmt_float(f64_div(f64_from(22), f64_from(7)), 4);
    syscall(60, 7);
    return 0;
}
var e = main();
EOF
"$T/stage1" < "$T/a3.cyr" > "$T/a3p" 2>/dev/null || { echo "SKIP dce_eliminates axis3: float probe needs fmt_float"; exit 77; }
# The probe exits 7 by design, so the rc is captured with `|| want=$?` (see axis 2).
chmod +x "$T/a3p"; want=0; "$T/a3p" >/dev/null 2>&1 || want=$?
CYRIUS_DCE=1 "$T/stage1" < "$T/a3.cyr" > "$T/a3d" 2>"$T/a3.err" || {
  echo "FAIL dce_eliminates axis3: a float-formatting program stopped compiling under DCE."
  echo "  If the message names a corrupted body, the audit is firing on a DECODER gap rather"
  echo "  than on real corruption — it must be baseline-relative."
  grep -m2 -a 'error' "$T/a3.err" | sed 's/^/    /'; exit 1; }
chmod +x "$T/a3d"; got=0; "$T/a3d" >/dev/null 2>&1 || got=$?
[ "$got" -eq "$want" ] || { echo "FAIL dce_eliminates axis3: float probe gave $got under DCE, $want without"; exit 1; }

# ── axis 4 — ANTI-VACUOUS: the DEFAULT path is untouched ─────────────────────────────────
"$T/stage1" < "$R/tests/tcyr/lang/regression.tcyr" > "$T/r_new" 2>/dev/null || { echo "FAIL dce_eliminates axis4: probe did not compile"; exit 1; }
"$CC"       < "$R/tests/tcyr/lang/regression.tcyr" > "$T/r_ref" 2>/dev/null || { echo "FAIL dce_eliminates axis4: probe did not compile with build/cycc"; exit 1; }
cmp -s "$T/r_new" "$T/r_ref" || { echo "FAIL dce_eliminates axis4: a DEFAULT-path build changed. Elimination must be inert without CYRIUS_DCE=1."; exit 1; }

# ── axis 5 — 6.7.14: nothing stale in .text's 8-byte pad after the compacted code ─────────
# wp_compact moves the code down and ends it at the moved length; FIXUP rounded that up to 8
# without clearing it, so the pad kept pre-compaction bytes (`00 00 c1 58 48 29` after the exit
# syscall of the filed sy.cyr — a stray instruction past the program's end). The code's last
# nonzero byte must sit exactly ELIM bytes below the plain build's, and .text must end at the
# next 8-byte boundary (W^X; CYRIUS_WX=0 pads to 16 for its data and zeroed it since 6.7.11).
# issues/2026-10-13-wx-compaction-leaves-stale-bytes-in-text-pad.md
_text_ends() {   # $1 = ELF -> "<offset past the last nonzero .text byte> <.text size>"
  set -- "$1" $(readelf -SW "$1" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == ".text") { print $(i + 3), $(i + 4); exit } }')
  [ -n "${3:-}" ] || return 0
  od -An -tx1 -v -j $((0x$2)) -N $((0x$3)) "$1" | tr -s ' ' '\n' | grep -v '^$' \
    | awk '{ n++; if ($1 != "00") l = n } END { print l + 0, n + 0 }'
}
cat > "$T/sy.cyr" <<'EOF'
fn dead_a(x): i64 { var q = x * 3; return q + 1; }
fn live_fn(x): i64 { return x + 100; }
fn main(): i64 { return live_fn(1) - 101; }
var rc = main();
syscall(60, rc);
EOF
"$T/stage1" < "$T/sy.cyr" > "$T/sy0" 2>/dev/null || { echo "FAIL dce_eliminates axis5: sy.cyr did not compile"; exit 1; }
set -- $(_text_ends "$T/sy0"); L0=${1:-}
[ -n "$L0" ] || { echo "FAIL dce_eliminates axis5: no .text section in the plain sy.cyr build"; exit 1; }
for WX in 1 0; do
  CYRIUS_DCE=1 CYRIUS_WX=$WX "$T/stage1" < "$T/sy.cyr" > "$T/sy$WX" 2>"$T/sy$WX.err" || { echo "FAIL dce_eliminates axis5: sy.cyr did not compile under CYRIUS_DCE=1 CYRIUS_WX=$WX"; exit 1; }
  E5=$(grep -a 'bytes of dead code eliminated' "$T/sy$WX.err" | grep -o '[0-9][0-9]*' | head -1)
  [ "${E5:-0}" -gt 0 ] || { echo "FAIL dce_eliminates axis5 (WX=$WX): sy.cyr no longer compacts: $(cat "$T/sy$WX.err")"; exit 1; }
  set -- $(_text_ends "$T/sy$WX"); L1=${1:-0}; N1=${2:-0}
  [ "$L1" = $((L0 - E5)) ] || {
    echo "FAIL dce_eliminates axis5 (WX=$WX): sy.cyr's compacted code ends at .text+$L1, want $((L0 - E5)) (the plain $L0 - $E5 eliminated):"
    echo "  the bytes after the last instruction are stale pre-compaction code, not zero"; exit 1; }
  if [ "$WX" = 1 ]; then
    [ "$N1" = $(( (L1 + 7) / 8 * 8 )) ] || { echo "FAIL dce_eliminates axis5: .text is $N1 B, want $L1 rounded up to 8"; exit 1; }
  fi
done
chmod +x "$T/sy1"; got=0; "$T/sy1" || got=$?
[ "$got" = 0 ] || { echo "FAIL dce_eliminates axis5: the compacted sy.cyr exits $got, want 0"; exit 1; }

# ── axis 6 — 6.7.14: compaction is not capped at 4,096 dead-code runs ─────────────────────
# The run registry was a fixed 4,096 records, and one run past it declined the WHOLE pass: 4,096
# one-line dead fns compacted to 4,456 B, 4,100 left 201,064 B (kybernet's agnos-init, 4,180 dead
# fns: 248,440 -> 1,574,640 B). It grows now (util.cyr _wpnr_grow) and a run abutting the last one
# extends it. 6a: contiguous dead fns (one run). 6b: 4,100 dead fns interleaved with 4,100 live
# ones (4,100 runs, one doubling). 6c: 10,000 dead fns each followed by a top-level statement
# (10,000 runs that never abut, two doublings). Each row removes EVERY byte it NOP-filled: a grow
# that loses runs (the merge scratch sized for 4,096) still builds a correct, merely larger binary.
# 6d: cycc's own CYRIUS_IR=3 build still compacts.
# Mutations (6.7.14, each built from a scratch edit of src/): no grow -> RED 6b (declined); no
# grow and no abutting-run merge -> RED 6a; `_wp_shift` on the fixed S+0xC0000 base -> RED 6b
# (2,121 live bodies corrupted, refused); the merge scratch at a fixed 4,096 -> RED 6b (192 B
# NOP-filled, not removed); the grow copying two of three words -> RED 6b. A grown table without
# room for its scratch is NOT seen: the arena past it is unused, so the overrun lands in nothing.
# issues/2026-10-15-kybernet-dce-compaction-cap-agnos-init.md
compacts6() {   # <row> <src> <want exit> <max bytes>
  CYRIUS_DCE=1 "$T/stage1" < "$2" > "$T/a6.bin" 2> "$T/a6.err" || { echo "FAIL dce_eliminates axis6 $1: the build failed: $(head -2 "$T/a6.err")"; exit 1; }
  if grep -q 'compaction declined' "$T/a6.err"; then echo "FAIL dce_eliminates axis6 $1: $(grep 'declined' "$T/a6.err")"; exit 1; fi
  grep -q 'bytes of dead code eliminated' "$T/a6.err" || { echo "FAIL dce_eliminates axis6 $1: no elimination: $(cat "$T/a6.err")"; exit 1; }
  nop=$(grep -o '([0-9]* bytes NOPed' "$T/a6.err" | grep -o '[0-9][0-9]*')
  eli=$(grep 'bytes of dead code eliminated' "$T/a6.err" | grep -o '[0-9][0-9]*' | head -1)
  [ "$nop" = "$eli" ] || { echo "FAIL dce_eliminates axis6 $1: $nop bytes NOP-filled, only $eli removed — runs were lost"; exit 1; }
  sz=$(wc -c < "$T/a6.bin")
  [ "$sz" -le "$4" ] || { echo "FAIL dce_eliminates axis6 $1: the compacted binary is $sz B, want <= $4"; exit 1; }
  chmod +x "$T/a6.bin"; got=0; "$T/a6.bin" || got=$?
  [ "$got" = "$3" ] || { echo "FAIL dce_eliminates axis6 $1: the compacted binary exits $got, want $3"; exit 1; }
}
awk 'BEGIN { for (i = 0; i < 4100; i++) printf "fn d%d(): i64 { return %d; }\n", i, i;
             print "fn main(): i64 { return 7; }"; print "var e = main();" }' > "$T/g6a.cyr"
compacts6 6a "$T/g6a.cyr" 7 8192
awk 'BEGIN { for (i = 0; i < 4100; i++) { printf "fn d%d(): i64 { return %d; }\n", i, i; printf "fn l%d(x): i64 { return x + 1; }\n", i }
             print "fn main(): i64 { var x = 0;"; for (i = 0; i < 4100; i++) printf "  x = l%d(x);\n", i
             print "  return x & 255; }"; print "var e = main();"; print "syscall(60, e);" }' > "$T/g6b.cyr"
compacts6 6b "$T/g6b.cyr" 4 400000
awk 'BEGIN { print "var t = 0;"; for (i = 0; i < 10000; i++) { printf "fn d%d(): i64 { return %d; }\n", i, i; print "t = t + 1;" }
             print "syscall(60, t & 255);" }' > "$T/g6c.cyr"
compacts6 6c "$T/g6c.cyr" 16 450000
CYRIUS_IR=3 "$T/stage1" < "$R/src/main.cyr" > "$T/ir3cc" 2> "$T/ir3cc.err" || { echo "FAIL dce_eliminates axis6 6d: cycc's CYRIUS_IR=3 build failed"; exit 1; }
grep -q '^wp-compact: [0-9]* bytes reclaimed' "$T/ir3cc.err" || { echo "FAIL dce_eliminates axis6 6d: cycc's CYRIUS_IR=3 build does not compact: $(grep -v '^warning\|^note' "$T/ir3cc.err" | head -3)"; exit 1; }
if grep -q 'wp-compact declined' "$T/ir3cc.err"; then echo "FAIL dce_eliminates axis6 6d: $(grep 'declined' "$T/ir3cc.err")"; exit 1; fi

# ── axis 7 — 6.7.14: a LIVE generic instance nested inside a dead one survives ─────────────
# Generic instances are emitted inline, inside the fn that first needs them, so `svh$i8` (dead:
# in_svh_i8 inlines it) CONTAINS `sv$i8` (live: the inlined body calls it). The sweeps filled /
# removed the dead fn's whole range, the live body with it: x86 exit 132 (the ud2 sentinel; 139
# before 6.7.11), CYRIUS_WX=0 132, aarch64 a hang under qemu. A dead fn whose range holds a live
# fn's start is kept whole now (runtime.cyr _dce_holds_live). 7a: the filed g.cyr exits 253 on x86
# W^X, CYRIUS_WX=0, aarch64 and cx (cx does not sweep — the control). 7b: the corpus file that
# met it, tests/tcyr/lang/generic_instance_inline_binding.tcyr, 18/18 under CYRIUS_DCE=1 on x86
# and aarch64. Mutations (6.7.14): `_dce_holds_live` returning 0 -> RED 7a (x86 132); only the
# aarch64 sweep's guard dropped -> RED 7a (aarch64 124, the hang).
# issues/2026-10-13-dce-removes-live-generic-instance-nested-in-dead-one.md
cat > "$T/g.cyr" <<'EOF'
fn sv<T>(x: T) { var y: T = 253; return y; }
fn svh<T>(x: T) { return sv<T>(x); }
fn in_svh_i8() { return svh<i8>(1); }
var r = in_svh_i8();
syscall(60, r & 255);
EOF
GIB="$R/tests/tcyr/lang/generic_instance_inline_binding.tcyr"
tcyr18() {   # <leg> <outfile> <rc>
  [ "$3" = 0 ] && grep -q '^18 passed, 0 failed' "$2" || { echo "FAIL dce_eliminates axis7b ($1): generic_instance_inline_binding.tcyr under CYRIUS_DCE=1 exits $3: $(tail -1 "$2")"; exit 1; }
}
for WX in 1 0; do
  CYRIUS_DCE=1 CYRIUS_WX=$WX "$T/stage1" < "$T/g.cyr" > "$T/g$WX" 2> "$T/g$WX.err" || { echo "FAIL dce_eliminates axis7a: g.cyr did not compile (CYRIUS_WX=$WX)"; exit 1; }
  grep -q 'unreachable fns' "$T/g$WX.err" || { echo "FAIL dce_eliminates axis7a: g.cyr has no dead fn any more — the row proves nothing: $(cat "$T/g$WX.err")"; exit 1; }
  chmod +x "$T/g$WX"; got=0; "$T/g$WX" || got=$?
  [ "$got" = 253 ] || { echo "FAIL dce_eliminates axis7a (x86, CYRIUS_WX=$WX): g.cyr under CYRIUS_DCE=1 exits $got, want 253 — a live instance nested in a dead one was removed"; exit 1; }
done
CYRIUS_DCE=1 "$T/stage1" < "$GIB" > "$T/gib" 2>/dev/null || { echo "FAIL dce_eliminates axis7b: the corpus file did not compile under CYRIUS_DCE=1"; exit 1; }
chmod +x "$T/gib"; got=0; "$T/gib" > "$T/gib.out" 2>&1 || got=$?; tcyr18 x86 "$T/gib.out" "$got"
"$T/stage1" < "$R/src/main_aarch64.cyr" > "$T/cc_a64" 2>/dev/null && [ -s "$T/cc_a64" ] || { echo "FAIL dce_eliminates axis7: cannot build src/main_aarch64.cyr"; exit 1; }
chmod +x "$T/cc_a64"
if command -v qemu-aarch64 > /dev/null 2>&1; then
  CYRIUS_DCE=1 "$T/cc_a64" < "$T/g.cyr" > "$T/ga" 2>/dev/null || { echo "FAIL dce_eliminates axis7a: g.cyr did not compile for aarch64"; exit 1; }
  chmod +x "$T/ga"; got=0; timeout 20 qemu-aarch64 "$T/ga" || got=$?
  [ "$got" = 253 ] || { echo "FAIL dce_eliminates axis7a (aarch64): g.cyr under CYRIUS_DCE=1 exits $got, want 253 (124 = the hang)"; exit 1; }
  CYRIUS_DCE=1 "$T/cc_a64" < "$GIB" > "$T/giba" 2>/dev/null || { echo "FAIL dce_eliminates axis7b: the corpus file did not compile for aarch64"; exit 1; }
  chmod +x "$T/giba"; got=0; timeout 60 qemu-aarch64 "$T/giba" > "$T/giba.out" 2>&1 || got=$?; tcyr18 aarch64 "$T/giba.out" "$got"
else
  echo "  SKIP dce_eliminates axis7 aarch64 legs: qemu-aarch64 not installed"
fi
"$T/stage1" < "$R/src/main_cx.cyr" > "$T/cc_cx" 2>/dev/null && [ -s "$T/cc_cx" ] && \
  "$T/stage1" < "$R/programs/cxvm.cyr" > "$T/cxvm" 2>/dev/null && [ -s "$T/cxvm" ] || { echo "FAIL dce_eliminates axis7: cannot build src/main_cx.cyr / programs/cxvm.cyr"; exit 1; }
chmod +x "$T/cc_cx" "$T/cxvm"
CYRIUS_DCE=1 "$T/cc_cx" < "$T/g.cyr" > "$T/g.cyx" 2>/dev/null || { echo "FAIL dce_eliminates axis7a: g.cyr did not compile for cx"; exit 1; }
got=0; timeout 20 "$T/cxvm" < "$T/g.cyx" || got=$?
[ "$got" = 253 ] || { echo "FAIL dce_eliminates axis7a (cx): g.cyr under CYRIUS_DCE=1 exits $got, want 253"; exit 1; }

# ── axis 8 — 6.7.14: a redefined fn's LOSING body keeps nothing alive ───────────────────────
# `_fn_redirect` turns the earlier definition's entry into a jump to the last one, so the losing
# body lies in no fn's range, and the seed pass took every call in it as a root: `only_in_loser`,
# called only from the losing `f`, was not dead in a.cyr (0 'dead:' lines) while it was in b.cyr
# (1). The filed a.cyr / b.cyr verbatim, built as their manifest's `stdlib = ["syscalls"]` builds
# them (lib/syscalls.cyr ahead of the source): both report it dead and exit 1 (the winner ran), on
# x86 W^X, CYRIUS_WX=0 and aarch64. Mutation (6.7.14): `_dce_in_loser` returning 0 -> RED 8 (a.cyr
# reports 0). issues/2026-10-12-dce-keeps-the-callees-of-a-redefined-fns-losing-body.md
cat > "$T/a.cyr" <<'EOF'
fn only_in_loser() { return 42; }
fn f() { return only_in_loser(); }
fn f() { return 1; }
var r = f();
syscall(SYS_EXIT, r);
EOF
cat > "$T/b.cyr" <<'EOF'
fn only_in_loser() { return 42; }
fn g() { return 1; }
var r = g();
syscall(SYS_EXIT, r);
EOF
loser8() {   # <leg> <compiler> <run: x86|a64> [ENV=V...]
  l8="$1"; c8="$2"; r8="$3"; shift 3
  for x in a b; do
    { echo 'include "lib/syscalls.cyr"'; cat "$T/$x.cyr"; } > "$T/${x}8.cyr"
    env CYRIUS_DCE=1 CYRIUS_DCE_VERBOSE=1 "$@" "$c8" < "$T/${x}8.cyr" > "$T/${x}8" 2> "$T/${x}8.err" || { echo "FAIL dce_eliminates axis8 ($l8): $x.cyr did not compile: $(grep -m1 error "$T/${x}8.err")"; exit 1; }
    n8=$(grep -c 'dead: only_in_loser' "$T/${x}8.err" || true)
    [ "$n8" = 1 ] || { echo "FAIL dce_eliminates axis8 ($l8): $x.cyr reports 'dead: only_in_loser' $n8 times, want 1 — a losing body's call kept it alive"; exit 1; }
    chmod +x "$T/${x}8"; got=0
    if [ "$r8" = a64 ]; then timeout 20 qemu-aarch64 "$T/${x}8" || got=$?; else "$T/${x}8" || got=$?; fi
    [ "$got" = 1 ] || { echo "FAIL dce_eliminates axis8 ($l8): $x.cyr exits $got, want 1"; exit 1; }
  done
}
loser8 "x86 W^X" "$T/stage1" x86
loser8 "x86 CYRIUS_WX=0" "$T/stage1" x86 CYRIUS_WX=0
if command -v qemu-aarch64 > /dev/null 2>&1; then loser8 aarch64 "$T/cc_a64" a64
else echo "  SKIP dce_eliminates axis8 aarch64 leg: qemu-aarch64 not installed"; fi

echo "PASS dce_eliminates: $SAVED B removed (not padded), eliminated cycc reproduces the normal build byte-identically, float path unaffected, default path inert, the pad after compacted code is zero, no 4,096-run cap, a live instance nested in a dead one kept (x86, WX=0, aarch64, cx), a losing body roots nothing"
exit 0
