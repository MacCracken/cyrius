#!/bin/sh
# dce_kept_dead_calls.sh — 6.7.11. Under CYRIUS_DCE=1, a call that SURVIVES compaction but aims at
# a function compaction REMOVED becomes `ud2; ud2; nop` — never an address in whatever moved
# into the hole. And FIXUP's own `ud2` sentinel (an undefined callee under --allow-undef) is left
# alone by the compaction's repair pass.
#
# THE DEFECT (filed by agnos: issues/2026-10-10-agnos-kernel-dce-compaction-moves-data.md, its
# second half). A dead fn whose body the length decoder cannot size (an `out dx, al` — agnos had
# five) is KEPT, while the fns it calls are removed. Compaction shifted the kept body's call like
# any other, by the bytes deleted below each end, so it landed on whatever now sits where the
# callee was: measured on the slot-open compiler, a forward `call` onto an unrelated live fn, a
# backward tail `jmp` onto the kept body's own entry. Harmless only while the kept body stays
# dead. The repair (ir.cyr _wp_dead_xfer) covers both registries the pass repairs: the fixup
# table (ftype 2: a forward call, a forward tail call) and the disp32 sources (a backward call,
# a backward tail call). In passing: the same stage read FIXUP's ud2 sentinel back as a rel32 and
# "adjusted" it into `0f 5f 0f` (maxps) — the undefined call then faulted SIGSEGV, not SIGILL.
#
# ROWS
#   K  the four shapes. Each must compact, keep the dead body (its marker `90 90 90 ee` is still
#      in .text), and put 0f 0b 0f 0b 90 exactly where the plain build has the call / jmp — which
#      the plain build's CYRIUS_SYMS proves is aimed at the removed callee (anti-vacuous). The
#      live program still exits 0.
#   U  --allow-undef + CYRIUS_DCE=1, a dead fn below the undefined call so the call site moves:
#      the sentinel's bytes are intact and the call dies SIGILL (132), as without CYRIUS_DCE.
# Mutations (6.7.11, each in a scratch copy of src/): `_wp_dead_xfer` returning 0 -> K RED on
# all four shapes (the bytes are a call/jmp again); the ftype-2 `poff2 >= 0` skip dropped -> U
# RED (rc 139, maxps where the sentinel was).
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || { echo "FAIL: dce_kept_dead_calls: cannot cd to $R"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: dce_kept_dead_calls: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: dce_kept_dead_calls: no build/cycc"; exit 1; }
FAILS=0
fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

hex_text() {  # hex_text <bin> -> .text as one lowercase hex string; prints "OFF ADDR" to $T/ta
    set -- "$1" $(readelf -SW "$1" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == ".text") { print $(i + 2), $(i + 3), $(i + 4); exit } }')
    [ -n "${4:-}" ] || return 1
    echo "$((0x$3)) $((0x$2))" > "$T/ta"
    od -An -tx1 -v -j $((0x$3)) -N $((0x$4)) "$1" | tr -d ' \n'
}
pos_of() {  # pos_of <hex> <needle> -> byte offset of the first byte-aligned match, or nothing
    awk -v h="$1" -v n="$2" 'BEGIN { s = 1; while ((i = index(substr(h, s), n)) > 0) { p = s + i - 1; if ((p % 2) == 1) { print (p - 1) / 2; exit } s = p + 1 } }'
}
count_of() {  # count_of <hex> <needle> -> matches at even (byte) positions
    awk -v h="$1" -v n="$2" 'BEGIN { c = 0; s = 1; while ((i = index(substr(h, s), n)) > 0) { p = s + i - 1; if ((p % 2) == 1) c++; s = p + 1 } print c }'
}

MARK=909090ee
UD=0f0b0f0b90
# shape: name, opcode the plain build must hold, callee, source
shape() {
    _n=$1; _op=$2; _callee=$3
    cat > "$T/$_n.cyr"
    "$CC" < "$T/$_n.cyr" > "$T/$_n.0" 2>/dev/null || { fail "K $_n: the plain build failed"; return; }
    CYRIUS_SYMS="$T/$_n.syms" "$CC" < "$T/$_n.cyr" > /dev/null 2>&1
    CYRIUS_DCE=1 "$CC" < "$T/$_n.cyr" > "$T/$_n.1" 2> "$T/$_n.err" || { fail "K $_n: the CYRIUS_DCE=1 build failed: $(cat "$T/$_n.err")"; return; }
    grep -q 'bytes of dead code eliminated' "$T/$_n.err" || { fail "K $_n: nothing was eliminated: $(cat "$T/$_n.err")"; return; }
    H0=$(hex_text "$T/$_n.0"); read -r O0 A0 < "$T/ta"
    H1=$(hex_text "$T/$_n.1")
    [ "$(count_of "$H0" "$MARK")" = 1 ] && [ "$(count_of "$H1" "$MARK")" = 1 ] \
        || { fail "K $_n: the kept body's marker $MARK is not in .text exactly once (the body was removed, or the probe is ambiguous)"; return; }
    M0=$(pos_of "$H0" "$MARK"); M1=$(pos_of "$H1" "$MARK")
    # the call / jmp in the plain build: the first $_op byte after the marker
    K=$(pos_of "$(echo "$H0" | cut -c$(( (M0 + 4) * 2 + 1 ))-)" "$_op")
    [ -n "$K" ] || { fail "K $_n: no $_op after the marker in the plain build"; return; }
    S0=$((M0 + 4 + K))
    REL=$(echo "$H0" | cut -c$(( (S0 + 1) * 2 + 1 ))-$(( (S0 + 5) * 2 )) | sed 's/\(..\)\(..\)\(..\)\(..\)/\4\3\2\1/')
    REL=$((0x$REL)); [ "$REL" -ge 2147483648 ] && REL=$((REL - 4294967296))
    TGT=$(printf '%016x' $((A0 + S0 + 5 + REL)))
    grep -q "^$TGT $_callee\$" "$T/$_n.syms" \
        || { fail "K $_n: the plain build's $_op at +$S0 aims at 0x$TGT, not at $_callee ($(grep " $_callee\$" "$T/$_n.syms")) — the probe is wrong"; return; }
    S1=$((M1 + 4 + K))
    GOT=$(echo "$H1" | cut -c$(( S1 * 2 + 1 ))-$(( (S1 + 5) * 2 )))
    [ "$GOT" = "$UD" ] || fail "K $_n: the kept body's call into the removed $_callee is '$GOT' after compaction, want $UD (ud2; ud2; nop) — it was retargeted onto whatever moved there"
    chmod +x "$T/$_n.1"; RC=0; ( ulimit -c 0; timeout 60 "$T/$_n.1"; exit $? ) > /dev/null 2>&1 || RC=$?
    [ "$RC" = 0 ] || fail "K $_n: the compacted program exits $RC, want 0"
}

shape fwd_call e8 later_callee <<'EOF'
fn kept_dead(): i64 { asm { 0x90; 0x90; 0x90; 0xEE; } var v = later_callee(5); return v + 1; }
fn later_callee(x): i64 { var q = x * 3; return q + 1; }
fn live_fn(x): i64 { return x + 100; }
fn main(): i64 { return live_fn(1) - 101; }
var rc = main();
syscall(60, rc);
EOF
shape fwd_tail e9 later_callee <<'EOF'
fn kept_dead(): i64 { asm { 0x90; 0x90; 0x90; 0xEE; } return later_callee(5); }
fn later_callee(x): i64 { var q = x * 3; return q + 1; }
fn live_fn(x): i64 { return x + 100; }
fn main(): i64 { return live_fn(1) - 101; }
var rc = main();
syscall(60, rc);
EOF
shape bwd_call e8 removed_callee <<'EOF'
fn removed_callee(x): i64 { var q = x * 3; return q + 1; }
fn kept_dead(): i64 { asm { 0x90; 0x90; 0x90; 0xEE; } var v = removed_callee(5); return v + 1; }
fn live_fn(x): i64 { return x + 100; }
fn main(): i64 { return live_fn(1) - 101; }
var rc = main();
syscall(60, rc);
EOF
shape bwd_tail e9 removed_callee <<'EOF'
fn removed_callee(x): i64 { var q = x * 3; return q + 1; }
fn kept_dead(): i64 { asm { 0x90; 0x90; 0x90; 0xEE; } return removed_callee(5); }
fn live_fn(x): i64 { return x + 100; }
fn main(): i64 { return live_fn(1) - 101; }
var rc = main();
syscall(60, rc);
EOF

# U — FIXUP's sentinel survives the repair pass. The branch is taken, so the undefined call runs.
cat > "$T/u.cyr" <<'EOF'
fn dead_a(x): i64 { var q = x * 3; return q + 1; }
fn main(): i64 { if (load8("a") == 97) { nosuch(1); } return 0; }
var rc = main();
syscall(60, rc);
EOF
for D in 0 1; do
    CYRIUS_DCE=$D "$CC" --allow-undef < "$T/u.cyr" > "$T/u$D" 2> "$T/u$D.err" || fail "U: the --allow-undef build (CYRIUS_DCE=$D) failed: $(cat "$T/u$D.err")"
done
grep -q 'bytes of dead code eliminated' "$T/u1.err" || fail "U: the CYRIUS_DCE=1 build eliminated nothing, so the call site never moved: $(cat "$T/u1.err")"
UH=$(hex_text "$T/u1" || true)
[ "$(count_of "$UH" "505f$UD")" -ge 1 ] || fail "U: the undefined call's ud2 sentinel is not intact after compaction (push rax; pop rdi; $UD absent)"
chmod +x "$T/u0" "$T/u1"
R0=0; ( ulimit -c 0; timeout 60 "$T/u0"; exit $? ) > /dev/null 2>&1 || R0=$?
R1=0; ( ulimit -c 0; timeout 60 "$T/u1"; exit $? ) > /dev/null 2>&1 || R1=$?
[ "$R0" = 132 ] || fail "U: the plain --allow-undef build exits $R0 at the undefined call, want 132 (SIGILL) — the probe is wrong"
[ "$R1" = 132 ] || fail "U: under CYRIUS_DCE=1 the undefined call exits $R1, want 132 (SIGILL at FIXUP's sentinel)"

if [ "$FAILS" -gt 0 ]; then echo "FAIL: dce_kept_dead_calls ($FAILS)"; exit 1; fi
echo "PASS: dce_kept_dead_calls (a kept dead body's forward / backward call and tail call into removed code become ud2, never a live address; --allow-undef's sentinel survives compaction)"
exit 0
