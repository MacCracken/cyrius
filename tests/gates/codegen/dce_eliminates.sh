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
# 8b (review fix): under CYRIUS_IR=3 the seam's wp_compact moves the code BEFORE FIXUP's seed pass
# reads the recorded ranges, so they move with it (ir.cyr _wp_fnr_shift). Left pre-move, a range
# lay over whatever moved into it: a.cyr's `only_in_loser` was not dead (0), and live code was —
# fn_redefinition_last_wins.tcyr listed `rd_kp` / `rd_kv62` dead and its CYRIUS_IR=3 CYRIUS_DCE=1
# binary died on the ud2 sentinel (132, not 27/27), a top-level `helper()` after a loser was taken
# for a losing-body call (`dead: helper`, 132, not 38). Mutation: the `_wp_fnr_shift` call dropped
# -> RED 8b on all three.
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
loser8 "x86 CYRIUS_IR=3" "$T/stage1" x86 CYRIUS_IR=3
if command -v qemu-aarch64 > /dev/null 2>&1; then loser8 aarch64 "$T/cc_a64" a64
else echo "  SKIP dce_eliminates axis8 aarch64 leg: qemu-aarch64 not installed"; fi
CYRIUS_IR=3 CYRIUS_DCE=1 "$T/stage1" < "$R/tests/tcyr/crossos/fn_redefinition_last_wins.tcyr" > "$T/rd8" 2> "$T/rd8.err" || {
  echo "FAIL dce_eliminates axis8b: fn_redefinition_last_wins.tcyr did not compile under CYRIUS_IR=3 CYRIUS_DCE=1: $(grep -m1 error "$T/rd8.err")"; exit 1; }
grep -q 'wp-compact: ' "$T/rd8.err" || { echo "FAIL dce_eliminates axis8b: the IR=3 seam compacted nothing, so the row proves nothing"; exit 1; }
chmod +x "$T/rd8"; got=0; "$T/rd8" > "$T/rd8.out" 2>&1 || got=$?
[ "$got" = 0 ] || { echo "FAIL dce_eliminates axis8b: fn_redefinition_last_wins.tcyr under CYRIUS_IR=3 CYRIUS_DCE=1 exits $got, want 0 — a stale losing-body range dropped a live fn"; exit 1; }
top8() {   # <statements in pre> <the fn that must stay live> <want exit> [ENV=V...]
  n8=$1; f8=$2; w8=$3; shift 3
  { echo 'var q = 0;'; echo 'fn helper(): i64 { q = 5; return 5; }'; echo 'fn pre(x): i64 {'; echo '    var r = x;'
    i=0; while [ $i -lt "$n8" ]; do echo '    r = r + 3 * 4;'; i=$((i + 1)); done
    echo '    return r;'; echo '}'; echo 'fn f(): i64 { return 2; }'; echo 'fn f(): i64 { return 1; }'
    echo 'helper();'; echo 'var r = f() + pre(0) + q;'; echo 'syscall(60, r & 255);'; } > "$T/t8.cyr"
  env CYRIUS_IR=3 CYRIUS_DCE=1 CYRIUS_DCE_VERBOSE=1 "$@" "$T/stage1" < "$T/t8.cyr" > "$T/t8" 2> "$T/t8.err" || {
    echo "FAIL dce_eliminates axis8b ($n8 statements $*): did not compile: $(grep -m1 error "$T/t8.err")"; exit 1; }
  if grep -q "^  dead: $f8\$" "$T/t8.err"; then echo "FAIL dce_eliminates axis8b ($n8 statements $*): $f8 is listed dead, but top-level code after the loser calls it"; exit 1; fi
  chmod +x "$T/t8"; got=0; "$T/t8" || got=$?
  [ "$got" = "$w8" ] || { echo "FAIL dce_eliminates axis8b ($n8 statements $*): exits $got, want $w8 — a live fn was removed"; exit 1; }
}
top8 24 helper 38
top8 24 helper 38 CYRIUS_WX=0
top8 40 pre 230
top8 40 pre 230 CYRIUS_WX=0

# ── axis 9 — 6.7.14: a `#naked` redefinition past 49,152 recorded rel32 sources ──────────────
# EFNREDIRECT (x86/emit.cyr) registers the redirect's rel32 once: a `#naked` body opens with the
# defer-init jump whose rel32 is already recorded at those bytes, so it scans the registry first.
# The scan read the fixed S + 0x60000, and past 49,152 sources the registry lives in alloc'd
# storage (6.6.20) — the fixed region read beyond it is the run registry, so the naked body's own
# record was missed, the rel32 registered twice and repaired twice: 50,100 sources ahead of the
# filed `#naked` shape (fn_redefinition_binds_last.sh's naked_dce) exited 132, not 1. Mutation:
# the scan back on S + 0x60000 -> RED 9 (132).
awk 'BEGIN {
    print "fn inc(x): i64 { return x + 1; }"
    for (f = 0; f < 100; f++) {
        printf "fn g%d(r): i64 {\n", f
        for (k = 0; k < 501; k++) { print "    r = inc(r);" }
        print "    return r;"
        print "}"
    }
    print "#naked"
    print "fn g(): i64 { asm { 0xB8; 0x02; 0x00; 0x00; 0x00; 0xC3; } }"
    print "fn d1(): i64 { var a = 1; var b = 2; var c = a + b; return c * 7 + 3; }"
    print "fn d2(): i64 { var a = 4; var b = 5; var c = a * b; return c - 9; }"
    print "fn h(): i64 { var x = g(); return x; }"
    print "#naked"
    print "fn g(): i64 { asm { 0xB8; 0x01; 0x00; 0x00; 0x00; 0xC3; } }"
    print "syscall(60, h());"
}' > "$T/nk.cyr"
[ "$(grep -c 'inc(r)' "$T/nk.cyr")" -gt 49152 ] || { echo "FAIL dce_eliminates axis9: the probe no longer has more than 49,152 rel32 sources"; exit 1; }
CYRIUS_DCE=1 "$T/stage1" < "$T/nk.cyr" > "$T/nk" 2> "$T/nk.err" || { echo "FAIL dce_eliminates axis9: the probe did not compile: $(grep -m1 error "$T/nk.err")"; exit 1; }
grep -q 'bytes of dead code eliminated' "$T/nk.err" || { echo "FAIL dce_eliminates axis9: nothing was eliminated, so the redirect did not move: $(cat "$T/nk.err")"; exit 1; }
chmod +x "$T/nk"; got=0; "$T/nk" || got=$?
[ "$got" = 1 ] || { echo "FAIL dce_eliminates axis9: a #naked redefinition past 49,152 sources exits $got under CYRIUS_DCE=1, want 1 — its rel32 was repaired twice"; exit 1; }

# ── axis 10 — 6.7.14: a call counts only where an instruction starts ───────────────────────────
# The seed and propagate passes took every E8 / E9 BYTE whose rel32 decoded to a fn start as a
# call, so an immediate that happened to hold one kept a dead fn live — and data addresses move
# with every global added (two unused globals flipped `ir_emit1` in the cx fork: dead_code_floor.sh
# RED). A call now marks a fn live only from an instruction start of a span the length decoder
# walks exactly (fixup.cyr _dce_cand_build); a span with a raw asm byte or a switch's jump table
# keeps the byte scan, so nothing live is ever dropped.
# 10a: imm64 constants built to read `E8 rel32` onto two dead fns' starts — one in a live fn's body
#      (the propagate pass), one in top-level code (the seed pass): both fns are listed dead and
#      CYRIUS_DCE=1 removes them; the bytes are checked to hold the calls (the row is not vacuous).
# 10b: raw asm `EB 02 81 78` jumps over two bytes the decoder reads as `cmp dword [rax+d8], imm32`,
#      which swallows the real `call callee` after them and resyncs: in a fn and at the top level,
#      the callee stays live and the CYRIUS_DCE=1 binary runs (43).
# 10c: a switch's jump table read as code swallows the `call callee` that opens case 0 for some
#      case-body sizes: six of them, the callee live and the CYRIUS_DCE=1 binary right.
# Mutations (6.7.14), each RED: `_dce_mark` without its instruction-start test (10a: neither fn
# dead); `_dce_raw_note` a no-op (10b: callee listed dead in the fn and at the top level, and the
# DCE=1 binary exits 132); the top-level note dropped (10b top level, the same); `_dce_ijmp`
# answering 0 (10c: callee dead for case 0 + 2, + 3 and + 5, those DCE=1 binaries 132).
# issues/2026-10-14-dead-code-floor-trips-on-dce-byte-scan-false-live.md
_find8() {   # <file> <16 hex digits, the 8 bytes in file order> -> every offset holding them
  od -An -tx1 -v "$1" | tr -s ' ' '\n' | grep -v '^$' | awk -v w="$2" '{ a[NR - 1] = $1 }
    END { for (i = 0; i + 8 <= NR; i++) if (a[i] a[i+1] a[i+2] a[i+3] a[i+4] a[i+5] a[i+6] a[i+7] == w) print i }'
}
cat > "$T/a10.cyr" <<'EOF'
fn dead_seed(): i64 { return 5; }
fn dead_prop(): i64 { return 6; }
fn live_fn(x): i64 { var c = 0x1122334455667788; return (x & 3) + (c & 1); }
var r = live_fn(0x2233445566778899);
syscall(60, r);
EOF
CYRIUS_SYMS="$T/a10.syms" "$T/stage1" < "$T/a10.cyr" > "$T/a10" 2> "$T/a10.err" || { echo "FAIL dce_eliminates axis10a: the probe did not compile: $(cat "$T/a10.err")"; exit 1; }
PV=$(od -An -t u8 -j $(( $(od -An -t u8 -j 32 -N 8 "$T/a10" | tr -d ' ') + 16 )) -N 8 "$T/a10" | tr -d ' ')   # phdr 0 p_vaddr
PO=$(od -An -t u8 -j $(( $(od -An -t u8 -j 32 -N 8 "$T/a10" | tr -d ' ') + 8 )) -N 8 "$T/a10" | tr -d ' ')    # phdr 0 p_offset
M1=$(_find8 "$T/a10" 8877665544332211); M2=$(_find8 "$T/a10" 9988776655443322)
DS=$(awk '$2 == "dead_seed" { print $1 }' "$T/a10.syms"); DP=$(awk '$2 == "dead_prop" { print $1 }' "$T/a10.syms")
[ "$(echo "$M1" | wc -w)" = 1 ] && [ "$(echo "$M2" | wc -w)" = 1 ] && [ -n "$DS" ] && [ -n "$DP" ] || {
  echo "FAIL dce_eliminates axis10a: the probe's two imm64 markers or two dead fns were not found once each (markers '$M1' '$M2', fns '$DS' '$DP')"; exit 1; }
REL1=$(( (0x$DP - (PV - PO + M1 + 5)) & 0xFFFFFFFF ))   # the E8 at the fn-body imm's first byte -> dead_prop
REL2=$(( (0x$DS - (PV - PO + M2 + 5)) & 0xFFFFFFFF ))   # the E8 at the top-level imm's first byte -> dead_seed
V1=$(printf '0x112233%08XE8' "$REL1"); V2=$(printf '0x223344%08XE8' "$REL2")
sed -e "s/0x1122334455667788/$V1/" -e "s/0x2233445566778899/$V2/" "$T/a10.cyr" > "$T/a10b.cyr"
CYRIUS_DCE_VERBOSE=1 "$T/stage1" < "$T/a10b.cyr" > "$T/a10b" 2> "$T/a10b.err" || { echo "FAIL dce_eliminates axis10a: the built probe did not compile"; exit 1; }
_le4() { printf '%02x%02x%02x%02x' $(( $1 & 255 )) $(( ($1 >> 8) & 255 )) $(( ($1 >> 16) & 255 )) $(( ($1 >> 24) & 255 )); }
[ "$(_find8 "$T/a10b" "e8$(_le4 "$REL1")332211")" = "$M1" ] && [ "$(_find8 "$T/a10b" "e8$(_le4 "$REL2")443322")" = "$M2" ] || {
  echo "FAIL dce_eliminates axis10a: the built probe's immediates do not hold the E8 rel32 calls at $M1 / $M2 — the row would prove nothing"; exit 1; }
[ "$(grep -c '^  dead: dead_seed$' "$T/a10b.err")" = 1 ] && [ "$(grep -c '^  dead: dead_prop$' "$T/a10b.err")" = 1 ] || {
  echo "FAIL dce_eliminates axis10a: an E8 byte inside an imm64 kept a dead fn live (dead: $(grep '^  dead:' "$T/a10b.err" | awk '{print $2}' | tr '\n' ' ')want dead_seed and dead_prop)"; exit 1; }
chmod +x "$T/a10b"; got=0; "$T/a10b" || got=$?
[ "$got" = 0 ] || { echo "FAIL dce_eliminates axis10a: the probe exits $got, want 0"; exit 1; }
CYRIUS_DCE=1 "$T/stage1" < "$T/a10b.cyr" > "$T/a10d" 2> "$T/a10d.err" || { echo "FAIL dce_eliminates axis10a: the CYRIUS_DCE=1 build failed"; exit 1; }
grep -q '96 bytes of dead code eliminated' "$T/a10d.err" || { echo "FAIL dce_eliminates axis10a: CYRIUS_DCE=1 did not remove both fns: $(cat "$T/a10d.err")"; exit 1; }
chmod +x "$T/a10d"; got=0; "$T/a10d" || got=$?
[ "$got" = 0 ] || { echo "FAIL dce_eliminates axis10a: the CYRIUS_DCE=1 probe exits $got, want 0"; exit 1; }
live10() {   # <row> <src> <want exit>: no `dead: callee`, and the CYRIUS_DCE=1 binary exits <want>
  CYRIUS_DCE_VERBOSE=1 "$T/stage1" < "$2" > "$T/l10" 2> "$T/l10.err" || { echo "FAIL dce_eliminates axis$1: did not compile: $(grep -m1 error "$T/l10.err")"; exit 1; }
  if grep -q '^  dead: callee$' "$T/l10.err"; then echo "FAIL dce_eliminates axis$1: callee is listed dead, but the code calls it"; exit 1; fi
  CYRIUS_DCE=1 "$T/stage1" < "$2" > "$T/l10d" 2> /dev/null || { echo "FAIL dce_eliminates axis$1: the CYRIUS_DCE=1 build failed"; exit 1; }
  chmod +x "$T/l10d"; got=0; "$T/l10d" || got=$?
  [ "$got" = "$3" ] || { echo "FAIL dce_eliminates axis$1: the CYRIUS_DCE=1 binary exits $got, want $3 — a live fn was removed"; exit 1; }
}
cat > "$T/b10f.cyr" <<'EOF'
fn callee(): i64 { return 42; }
fn host(): i64 { asm { 0xEB; 0x02; 0x81; 0x78; } var v = callee(); return v + 1; }
var r = host();
syscall(60, r);
EOF
cat > "$T/b10t.cyr" <<'EOF'
fn callee(): i64 { return 42; }
var r = 0;
asm { 0xEB; 0x02; 0x81; 0x78; }
r = callee() + 1;
syscall(60, r);
EOF
live10 "10b (fn)" "$T/b10f.cyr" 43
live10 "10b (top level)" "$T/b10t.cyr" 43
a=0
while [ $a -le 5 ]; do
  { echo 'fn callee(): i64 { return 42; }'; echo 'fn host(x): i64 {'; echo '    var q = 0;'; echo '    switch (x) {'
    printf '        case 0: q = callee() + 1;'; i=0; while [ $i -lt $a ]; do printf ' q = q + 7;'; i=$((i + 1)); done; echo
    echo '        case 1: q = 2;'; echo '        case 2: q = 3;'; echo '        case 3: q = 4;'; echo '    }'; echo '    return q;'; echo '}'
    echo 'var r = host(0);'; echo 'syscall(60, r & 255);'; } > "$T/c10.cyr"
  live10 "10c (case 0 + $a)" "$T/c10.cyr" $((43 + 7 * a))
  a=$((a + 1))
done

echo "PASS dce_eliminates: $SAVED B removed (not padded), eliminated cycc reproduces the normal build byte-identically, float path unaffected, default path inert, the pad after compacted code is zero, no 4,096-run cap, a live instance nested in a dead one kept (x86, WX=0, aarch64, cx), a losing body roots nothing (its range moved by the CYRIUS_IR=3 seam too), a #naked redirect past 49,152 sources repaired once, an E8 inside an immediate is no call (a raw asm block and a jump table keep the byte scan)"
exit 0
