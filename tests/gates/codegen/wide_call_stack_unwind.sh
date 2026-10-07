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
# One call of 300 arguments "worked" while nothing touched the displaced sp. The same class sat two
# more places, one bit further out. Past 2048 arguments the marshalling `ldr/str xN, [sp, #imm]`
# (scaled imm12, 32760 max) carried into opc bit 22: each `ldr` read a slot 32 KiB too low, and the
# shuffle's `str` assembled as an `ldr` — the store vanished. Past 2053 parameters the callee's
# `ldr x9, [x29, #imm]` did the same (at 2054 it read the saved fp). No diagnostic.
# The roadmap bullet said "~300 arguments -> SIGILL" and roadmap-future called this imm12 class
# CLOSED; both were wrong. Every call shape funnels through ECALLPOPS/ECALLCLEAN (direct, callptr,
# method, operator, the over-the-ceiling tail call); `fncallN` stops at 8 and cannot reach it.
#
# AXES (the widths are the measured thresholds: 7 first stack arg, 261 last that fit, 262 first
# leak, 263, 518 first bit-23 word, 519 first SIGILL everywhere, 600, 2048 last [sp,#imm], 2049
# first [sp,x16], 2053 last callee [x29,#imm], 2054 first callee [x29,x16], 2100):
#   1  static, every host: the aarch64 binary of each width carries the cleanup the SHELL derives
#      from (n - 6) * 16 — `add sp,sp,#hi,lsl #12` then `add sp,sp,#lo` past 4095 — as consecutive
#      words; each register argument's load at the offset derived here — `ldr xR, [sp, #off]` to
#      32760, `ldr xR, [sp, x16]` past it — plus `str x9, [sp, x16]` past 2048 arguments and
#      `ldr x9, [x29, x16]` past 2053 parameters.
#   2  runtime, qemu-aarch64 with `-cpu cortex-a72` when it has it — a non-MTE core like pi's, so
#      the 518 word is SIGILL here as on the hardware (named SKIP when qemu is absent; real hardware
#      is tests/tcyr/crossos/wide_call_stack_unwind.tcyr on pi + ecb): each probe calls its width-n fn
#      directly and through callptr, checks six parameter positions against an awk-derived literal
#      and that sp — the address of a local in a fresh callee frame — is the same before and after,
#      and only THEN loops 300 calls of each (so the broken compiler fails, it does not hang). The
#      run is under `timeout -s KILL`: qemu outlives a plain SIGTERM when the guest sp is garbage.
#   3  the same probes natively on the host x86 compiler — the oracle that the probe itself is right.
#
# MUTATION LEDGER (each mutant applied to src/backend/aarch64/emit.cyr in a copy of the tree, the
# gate run there — it cross-builds cycc_aarch64 from that src; rows red of 12, axis 1 / axis 2):
#   M1 ECALLCLEAN back to the single `add sp, sp, #imm12`   -> RED 10 / 10 (262..2100: exit 3 to 518,
#                                                              SIGILL from 519 — qemu's default MTE cpu)
#   M2 ELDR_SP/ESTR_SP back to the single [sp, #imm] form    -> RED 4 / 4 (2049, 2053, 2054, 2100: exit 4)
#   M3 ESTORESTACKPARM back to the single [x29, #imm] form   -> RED 2 / 2 (2054, 2100: exit 4)
#   M4 the split's `add sp, sp, #lo` dropped (LSL #12 only)  -> RED 7 / 7 (263, 519, 600, 2048, 2049,
#                                                              2053, 2100: exit 3 — sp off by `lo`)
# The crossos twin is red under M1 (old compiler: sp -4096 at 262, SIGILL at 600), M2 + M3 (the 2100
# rows' values) and M4 (sp -16 at 263).
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CC="${CYCC:-$ROOT/build/cycc}"
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL wide_call_stack_unwind: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT INT TERM
ulimit -c 0 2>/dev/null || true
WIDTHS="7 261 262 263 518 519 600 2048 2049 2053 2054 2100"
NW=12
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

QEMU=0; command -v qemu-aarch64 >/dev/null 2>&1 && QEMU=1
QCPU=""
if [ "$QEMU" = 1 ] && qemu-aarch64 -cpu help 2>/dev/null | grep -q 'cortex-a72'; then QCPU="-cpu cortex-a72"; fi
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
                w=$(hx $(( 0xF8706BE0 | r ))); f="ldr x$r, [sp, x16]"
            fi
            grep -qx "$w" "$T/w$n" || bad "n=$n: no \`$f\` ($w) loading argument $((r + 1))"
        done
    fi
    if [ "$n" -gt 2048 ]; then
        grep -qx 'f8306be9' "$T/w$n" || bad "n=$n: no \`str x9, [sp, x16]\` — the extras shuffle past 32760 bytes"
    fi
    if [ "$n" -gt 2053 ]; then
        grep -qx 'f8706ba9' "$T/w$n" || bad "n=$n: no \`ldr x9, [x29, x16]\` — the callee's stack-parameter load past 32760 bytes"
    fi

    # axis 2 — run it
    if [ "$QEMU" = 1 ]; then
        rc=0; (cd "$T" && timeout -s KILL 30 qemu-aarch64 $QCPU "./a$n" > /dev/null 2>&1) || rc=$?
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

echo "  axis 1: $NSTATIC of $NW aarch64 probes carry the derived \`add sp\` cleanup (+ the x16 forms past 2048 / 2053)"
if [ "$QEMU" = 1 ]; then
    echo "  axis 2: $NRUN of $NW aarch64 probes exit 42 under qemu-aarch64 ${QCPU:-(default cpu)} (sp balanced, six positions right, 600 looped calls)"
    [ "$NRUN" = "$NW" ] || fail=1
else
    echo "  axis 2: SKIP (qemu-aarch64 absent) — the runtime leg did not run; pi + ecb run tests/tcyr/crossos/wide_call_stack_unwind.tcyr"
fi
echo "  axis 3: $NHOST of $NW host probes exit 42"
[ "$NSTATIC" = "$NW" ] && [ "$NHOST" = "$NW" ] || fail=1
if [ "$fail" != 0 ]; then echo "FAIL wide_call_stack_unwind"; exit 1; fi
echo "PASS wide_call_stack_unwind: calls of 7..2100 arguments unwind sp exactly and read every parameter on aarch64"
exit 0
