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

echo "PASS dce_eliminates: $SAVED B removed (not padded), eliminated cycc reproduces the normal build byte-identically, float path unaffected, default path inert, the pad after compacted code is zero"
exit 0
