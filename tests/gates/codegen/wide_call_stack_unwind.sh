#!/bin/sh
# tests/gates/codegen/wide_call_stack_unwind.sh — 6.6.20
#
# ⛔ THE DEFECT (aarch64 ELF + arm64 Mach-O — one emitter — every release through 6.6.19).
# ECALLCLEAN took a call's stack arguments back with ONE `add sp, sp, #imm12` of (n - 6) * 16
# bytes and nothing guarded the immediate (the prologue's EPATCHFRAME and EADDRA_IMM already split
# theirs). From 262 arguments the carry landed in the LSL #12 bit:
#   n = 262   `add sp, sp, #0, lsl #12`  — sp never restored: a looped call walks off the stack
#   n = 263   `add sp, sp, #16, lsl #12` — +64 KiB where +4112 is right: sp climbs over the caller's
#             frame, a looped call overwrites its own counter and NEVER ENDS (measured: still
#             spinning after 10 minutes under qemu, past a plain SIGTERM)
#   n = 518   the carry reaches bit 23 — an `addg` on an MTE core such as qemu's default cpu (sp
#             silently leaks), SIGILL on pi and Apple Silicon (measured on pi: exit 132)
#   n >= 519  SIGILL everywhere, at the first call
# One call of 300 arguments "worked" while nothing touched the displaced sp. The same class sat in
# three more places. Past 2048 arguments the marshalling `ldr/str xN, [sp, #imm]` (scaled imm12,
# 32760 max) carried into opc bit 22: each `ldr` read a slot 32 KiB too low, and the shuffle's `str`
# assembled as an `ldr` — the store vanished. Past 2053 parameters the callee's
# `ldr x9, [x29, #imm]` did the same (at 2054 it read the saved fp). And from 8192 parameters the
# callee homed and read each parameter through a lone 16-bit `movz` of its displacement: param 8192
# was homed over the saved fp, 8193 over p1's slot (SIGSEGV) — the truncation that also made any
# local after a 64 KiB buffer alias a byte inside it (the frame probe; a loop over the buffer reset
# its own counter and never ended). No diagnostic anywhere. The roadmap bullet said "~300 arguments
# -> SIGILL" and roadmap-future called this imm12 class CLOSED; both were wrong. Every call shape
# funnels through ECALLPOPS/ECALLCLEAN (direct, callptr, method, operator, the over-the-ceiling tail
# call); `fncallN` stops at 8 and cannot reach it.
#
# AXES (the widths are the measured thresholds: 7 first stack arg, 261 last that fit, 262 first
# leak, 263, 518 first bit-23 word, 519 first SIGILL everywhere, 600, 2048 last [sp,#imm], 2049
# first [sp,x16], 2053 last callee [x29,#imm], 2054 first callee [x29,x16], 2100, 8200 — params
# 8192.. homed and read past 64 KiB, and register-argument offsets past 64 KiB, both `movk` arms):
#   1  static, every host: the aarch64 binary of each width carries the cleanup the SHELL derives
#      from (n - 6) * 16 — `add sp,sp,#hi,lsl #12` then `add sp,sp,#lo` past 4095 — as consecutive
#      words; each register argument's load at the offset derived here — `ldr xR, [sp, #off]` to
#      32760, `movz x16, #lo [; movk x16, #hi, lsl #16]; ldr xR, [sp, x16]` past it — plus
#      `str x9, [sp, x16]` past 2048 arguments, `ldr x9, [x29, x16]` past 2053 parameters, and the
#      LAST parameter's home and read at the displacement derived from n: `movz x10 [; movk x10];
#      sub x10, x29, x10; str x9, [x10]` and `movz x9 [; movk x9]; sub x9, x29, x9; ldr x0, [x9]`.
#      The frame probe carries `movk x9, #1, lsl #16` before both `sub x9, x29, x9` (a local) and
#      `sub x8, x29, x9` (the struct-result X8 retptr).
#   2  runtime, qemu-aarch64 (or qemu-aarch64-static) with `-cpu cortex-a72` when it has it — a
#      non-MTE core like pi's, so the 518 word is SIGILL here as on the hardware (when qemu is absent
#      every other leg still runs and the gate then exits 77, a SKIP and never a PASS; real hardware
#      is tests/tcyr/crossos/wide_call_stack_unwind.tcyr on pi + ecb): each probe calls its width-n fn
#      directly and through callptr, checks six parameter positions against an awk-derived literal
#      and that sp — the address of a local in a fresh callee frame — is the same before and after,
#      and only THEN loops 300 calls of each (so the broken compiler fails, it does not hang). The
#      frame probe reads back a local, a store through &local and a received struct, each past
#      64 KiB, after filling the 70000-byte buffer below them. The runs are under `timeout -s KILL`:
#      qemu outlives a plain SIGTERM when the guest sp is garbage.
#   3  the same probes natively on the host x86 compiler — the oracle that the probe itself is right.
#
# MUTATION LEDGER (each mutant applied to src/backend/aarch64/emit.cyr in a copy of the tree, the
# gate run there — it cross-builds cycc_aarch64 from that src). M1-M4 were measured against the 12
# widths 7..2100 (rows red, axis 1 / axis 2); M5-M8 against this 13-width + frame-probe gate:
#   M1 ECALLCLEAN back to the single `add sp, sp, #imm12`   -> RED 10 / 10 (262..2100: exit 3 to 518,
#                                                              SIGILL from 519 — measured on qemu's
#                                                              default MTE cpu; under cortex-a72,
#                                                              518 is SIGILL too)
#   M2 ELDR_SP/ESTR_SP back to the single [sp, #imm] form    -> RED 4 / 4 (2049, 2053, 2054, 2100: exit 4)
#   M3 ESTORESTACKPARM back to the single [x29, #imm] form   -> RED 2 / 2 (2054, 2100: exit 4)
#   M4 the split's `add sp, sp, #lo` dropped (LSL #12 only)  -> RED 7 / 7 (263, 519, 600, 2048, 2049,
#                                                              2053, 2100: exit 3 — sp off by `lo`)
#   M5 _EFP_ADDR_X9 back to the lone 16-bit `movz x9`       -> RED (8200: last-param read; frame probe)
#   M6 EFLADDR_X8's fallback back to the lone `movz x9`     -> RED (frame probe: the retptr row)
#   M7 ESTORESTACKPARM's x10 arm back to the lone `movz x10` -> RED (8200: last-param home + SIGSEGV)
#   M8 _EMOV_XN never emits its `movk`                       -> RED (8200 and the frame probe)
# The crossos twin is red under M1 (old compiler: sp -4096 at 262, SIGILL at 600), M2 + M3 (the 2100
# rows' values), M4 (sp -16 at 263), M5 (5 rows: 8200 values + the three frame rows), M6 (the
# retptr row), M7 and M8 (SIGSEGV in the 8200 rows).
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CC="${CYCC:-$ROOT/build/cycc}"
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL wide_call_stack_unwind: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT INT TERM
ulimit -c 0 2>/dev/null || true
WIDTHS="7 261 262 263 518 519 600 2048 2049 2053 2054 2100 8200"
NW=13
fail=0
bad() { echo "  FAIL: $1"; fail=1; }

[ "$(printf '%s\n' $WIDTHS | grep -c .)" = "$NW" ] || { echo "FAIL wide_call_stack_unwind: the width list lost rows"; exit 1; }

rc=0; (cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$T/cca" 2> "$T/cca.err") || rc=$?
[ "$rc" = 0 ] && [ -s "$T/cca" ] || { echo "FAIL wide_call_stack_unwind: cross-building cycc_aarch64 from src failed (rc $rc): $(head -3 "$T/cca.err")"; exit 1; }
chmod +x "$T/cca"

# The literal the callee must compute from six parameter positions — awk's arithmetic, not cyrius's.
want() { awk -v n="$1" 'BEGIN { m = int(n / 2); printf "%d", 1 + 2 * 3 + 6 * 7 + 7 * 1009 + m * 10007 + n * 100003 }'; }

gen() {   # gen N OUT
    _n=$1; _m=$(( _n / 2 )); _w=$(want "$_n")
    _p=$(seq -f 'p%.0f' -s ', ' 1 "$_n"); _a=$(seq -s ', ' 1 "$_n")
    {
        echo "fn f($_p) { return p1 + p2 * 3 + p6 * 7 + p7 * 1009 + p$_m * 10007 + p$_n * 100003; }"
        echo 'fn spp() { var x = 1; return &x; }'
        echo 'fn main() {'
        echo "    var a = spp(); var v = f($_a); var b = spp();"
        echo '    if (b != a) { return 3; }'
        echo "    if (v != $_w) { return 4; }"
        echo "    var c = spp(); var u = callptr(&f, $_a); var d = spp();"
        echo '    if (d != c) { return 5; }'
        echo "    if (u != $_w) { return 6; }"
        echo '    var s = 0; var i = 0;'
        echo "    while (i < 300) { s = s + f($_a) + callptr(&f, $_a); i = i + 1; }"
        echo "    if (s != $_w * 600) { return 7; }"
        echo '    return 42;'
        echo '}'
        echo 'var r = main();'
        echo 'syscall(60, r);'
    } > "$2"
}

_words() { od -An -v -tx4 "$1" | tr -s ' ' '\n' | grep -v '^$' || true; }
hx() { printf '%08x' "$1"; }
# movx R V — the words for xR = V: `movz xR, #(V & 0xFFFF)`, plus `movk xR, #(V >> 16), lsl #16`
# when V needs it (V < 2^32)
movx() {
    _mw=$(hx $(( 0xD2800000 | (($2 & 0xFFFF) << 5) | $1 )))
    _mh=$(( ($2 >> 16) & 0xFFFF ))
    [ "$_mh" -ne 0 ] && _mw="$_mw $(hx $(( 0xF2A00000 | (_mh << 5) | $1 )))"
    printf '%s' "$_mw"
}
# has_seq N "w1 w2 ..." — the words occur consecutively in the width-N binary
has_seq() { tr '\n' ' ' < "$T/w$1" | grep -q " $2 "; }

QEMU=0; QBIN=""
for _q in qemu-aarch64 qemu-aarch64-static; do
    if command -v "$_q" >/dev/null 2>&1; then QBIN=$_q; QEMU=1; break; fi
done
QCPU=""
if [ "$QEMU" = 1 ] && "$QBIN" -cpu help 2>/dev/null | grep -q 'cortex-a72'; then QCPU="-cpu cortex-a72"; fi
NRUN=0; NHOST=0; NSTATIC=0
for n in $WIDTHS; do
    gen "$n" "$T/p$n.cyr"
    rc=0; (cd "$ROOT" && "$T/cca" < "$T/p$n.cyr" > "$T/a$n" 2> "$T/a$n.err") || rc=$?
    [ "$rc" = 0 ] && [ -s "$T/a$n" ] || { bad "n=$n: the aarch64 probe did not compile (rc $rc): $(grep -v '^note' "$T/a$n.err" | head -2)"; continue; }
    chmod +x "$T/a$n"

    # axis 1 — the cleanup as consecutive words, derived here from (n - 6) * 16
    _words "$T/a$n" > "$T/w$n"
    e=$(( (n - 6) * 16 ))
    if [ "$e" -lt 4096 ]; then
        seq1=$(hx $(( 0x910003FF | (e << 10) )))
    else
        seq1=$(hx $(( 0x914003FF | ((e >> 12) << 10) )))
        lo=$(( e & 0xFFF ))
        [ "$lo" -ne 0 ] && seq1="$seq1 $(hx $(( 0x910003FF | (lo << 10) )))"
    fi
    if ! tr '\n' ' ' < "$T/w$n" | grep -q " $seq1 "; then
        bad "n=$n: no \`add sp\` cleanup '$seq1' for $e bytes of stack arguments"
    else
        NSTATIC=$((NSTATIC + 1))
    fi
    if [ "$n" -gt 6 ]; then
        # register arg a(r+1) sits at [sp + (n - r - 1) * 16]: the scaled-imm12 form to 32760,
        # `ldr xR, [sp, x16]` past it
        for r in 0 1 2 3 4 5; do
            off=$(( (n - r - 1) * 16 ))
            if [ "$off" -le 32760 ]; then
                w=$(hx $(( 0xF94003E0 | ((off / 8) << 10) | r ))); f="ldr x$r, [sp, #$off]"
            else
                w="$(movx 16 "$off") $(hx $(( 0xF8706BE0 | r )))"; f="x16 = $off; ldr x$r, [sp, x16]"
            fi
            has_seq "$n" "$w" || bad "n=$n: no \`$f\` ($w) loading argument $((r + 1))"
        done
        # the last parameter, p$n, at x29 - 8n: homed by ESTORESTACKPARM's x10 arm and read back by
        # the callee's body through _EFP_ADDR_X9 (both a lone movz, plus a movk past 64 KiB) — the
        # arms every width whose 8n is past the 256-byte `stur`/`ldur` reach takes
        d=$(( 8 * n ))
        if [ "$d" -gt 256 ]; then
            has_seq "$n" "$(movx 10 "$d") cb0a03aa f9000149" || bad "n=$n: no \`x10 = $d; sub x10, x29, x10; str x9, [x10]\` homing parameter $n"
            has_seq "$n" "$(movx 9 "$d") cb0903a9 f9400120" || bad "n=$n: no \`x9 = $d; sub x9, x29, x9; ldr x0, [x9]\` reading parameter $n"
        fi
    fi
    if [ "$n" -gt 2048 ]; then
        grep -qx 'f8306be9' "$T/w$n" || bad "n=$n: no \`str x9, [sp, x16]\` — the extras shuffle past 32760 bytes"
    fi
    if [ "$n" -gt 2053 ]; then
        grep -qx 'f8706ba9' "$T/w$n" || bad "n=$n: no \`ldr x9, [x29, x16]\` — the callee's stack-parameter load past 32760 bytes"
    fi

    # axis 2 — run it
    if [ "$QEMU" = 1 ]; then
        rc=0; (cd "$T" && timeout -s KILL 30 "$QBIN" $QCPU "./a$n" > /dev/null 2>&1) || rc=$?
        case "$rc" in
            42) NRUN=$((NRUN + 1)) ;;
            3|5) bad "n=$n: aarch64 exit $rc — sp moved across a $n-argument call (3 direct, 5 callptr)" ;;
            4|6) bad "n=$n: aarch64 exit $rc — a $n-argument call read the wrong parameters (4 direct, 6 callptr)" ;;
            7) bad "n=$n: aarch64 exit 7 — 600 looped $n-argument calls summed wrong" ;;
            *) bad "n=$n: aarch64 exit $rc (132 SIGILL, 139 SIGSEGV, 137 killed at 30 s — a hang)" ;;
        esac
    fi

    # axis 3 — the host oracle
    rc=0; (cd "$ROOT" && "$CC" < "$T/p$n.cyr" > "$T/x$n" 2> "$T/x$n.err") || rc=$?
    [ "$rc" = 0 ] && [ -s "$T/x$n" ] || { bad "n=$n: the host probe did not compile (rc $rc)"; continue; }
    chmod +x "$T/x$n"
    rc=0; timeout -s KILL 30 "$T/x$n" > /dev/null 2>&1 || rc=$?
    if [ "$rc" = 42 ]; then NHOST=$((NHOST + 1)); else bad "n=$n: the host x86 probe exited $rc (want 42) — the probe, not the aarch64 backend, is wrong"; fi
done

# THE FRAME PROBE — the same 16-bit displacement reached by frame size: each local after `buf` sits
# past 64 KiB below x29. `fill` keeps its counter in its own small frame, so the broken compiler
# reads the fill byte (exit 11 / 12 / 13) instead of hanging on a counter the fill overwrites.
cat > "$T/frame.cyr" <<'FRAME'
struct T3 { a; b; c; }
fn fill(p, n, v) { var i = 0; while (i < n) { store8(p + i, v); i = i + 1; } return 0; }
fn mk3(): T3 { var p = T3 { 1, 2, 3 }; return p; }
fn frame_local() { var buf[70000]; var y = 5; fill(&buf, 70000, 90); return y; }
fn frame_addr() { var buf[70000]; var y = 0; var py = &y; store64(py, 77); fill(&buf, 70000, 90); return y; }
fn frame_retptr() { var buf[70000]; var q: T3 = mk3(); fill(&buf, 70000, 90); return q.a * 100 + q.b * 10 + q.c; }
fn main() {
    if (frame_local() != 5) { return 11; }
    if (frame_addr() != 77) { return 12; }
    if (frame_retptr() != 123) { return 13; }
    return 42;
}
var r = main();
syscall(60, r);
FRAME
NFRAME=0
rc=0; (cd "$ROOT" && "$T/cca" < "$T/frame.cyr" > "$T/afr" 2> "$T/afr.err") || rc=$?
if [ "$rc" = 0 ] && [ -s "$T/afr" ]; then
    chmod +x "$T/afr"
    _words "$T/afr" | tr '\n' ' ' > "$T/wfr"
    # `movk x9, #1, lsl #16` (f2a00029) right before the local's `sub x9, x29, x9` (cb0903a9) and
    # before the retptr's `sub x8, x29, x9` (cb0903a8)
    if grep -q ' f2a00029 cb0903a9 ' "$T/wfr" && grep -q ' f2a00029 cb0903a8 ' "$T/wfr"; then
        NFRAME=$((NFRAME + 1))
    else
        bad "frame probe: no \`movk x9, #1, lsl #16\` before \`sub x9, x29, x9\` and \`sub x8, x29, x9\` — a local past 64 KiB is addressed through a truncated displacement"
    fi
    if [ "$QEMU" = 1 ]; then
        rc=0; (cd "$T" && timeout -s KILL 30 "$QBIN" $QCPU ./afr > /dev/null 2>&1) || rc=$?
        case "$rc" in
            42) NFRAME=$((NFRAME + 1)) ;;
            11|12|13) bad "frame probe: aarch64 exit $rc — a local past 64 KiB lost its value (11 load/store, 12 &local, 13 X8 retptr)" ;;
            *) bad "frame probe: aarch64 exit $rc (139 SIGSEGV, 137 killed at 30 s — a hang)" ;;
        esac
    fi
else
    bad "frame probe: the aarch64 probe did not compile (rc $rc): $(grep -v '^note' "$T/afr.err" | head -2)"
fi
rc=0; (cd "$ROOT" && "$CC" < "$T/frame.cyr" > "$T/xfr" 2> /dev/null) || rc=$?
chmod +x "$T/xfr" 2>/dev/null
rc=0; timeout -s KILL 30 "$T/xfr" > /dev/null 2>&1 || rc=$?
[ "$rc" = 42 ] || bad "frame probe: the host x86 probe exited $rc (want 42) — the probe, not the aarch64 backend, is wrong"
NFRAME_WANT=1; [ "$QEMU" = 1 ] && NFRAME_WANT=2

echo "  axis 1: $NSTATIC of $NW aarch64 probes carry the derived \`add sp\` cleanup (+ the x16 forms past 2048 / 2053)"
if [ "$QEMU" = 1 ]; then
    echo "  axis 2: $NRUN of $NW aarch64 probes exit 42 under $QBIN ${QCPU:-(default cpu)} (sp balanced, six positions right, 600 looped calls)"
    [ "$NRUN" = "$NW" ] || fail=1
else
    echo "  axis 2: NOT RUN (no qemu-aarch64 / qemu-aarch64-static) — pi + ecb run tests/tcyr/crossos/wide_call_stack_unwind.tcyr"
fi
echo "  axis 3: $NHOST of $NW host probes exit 42"
echo "  frame:  $NFRAME of $NFRAME_WANT legs (static movk, qemu run) for locals past 64 KiB"
[ "$NSTATIC" = "$NW" ] && [ "$NHOST" = "$NW" ] && [ "$NFRAME" = "$NFRAME_WANT" ] || fail=1
if [ "$fail" != 0 ]; then echo "FAIL wide_call_stack_unwind"; exit 1; fi
if [ "$QEMU" != 1 ]; then
    echo "SKIP: wide_call_stack_unwind — qemu-aarch64 absent: the runtime legs (axis 2 + frame run) did not run (exit 77: a SKIP, not a PASS)"
    exit 77
fi
echo "PASS wide_call_stack_unwind: calls of 7..8200 arguments unwind sp exactly and read every parameter, and locals past 64 KiB keep their values, on aarch64"
exit 0
