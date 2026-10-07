#!/bin/sh
# Gate: the data-segment vaddr EMITELF_USER writes is the one FIXUP patched against.
#
# THE DEFECT (v6.6.3). `_wx_data_vaddr` derives the RW segment's vaddr by rounding the END
# OF CODE up to a 2 MB boundary, and FIXUP and EMITELF_USER each computed it independently
# and were expected to agree. `CYRIUS_DCE=1` breaks that: FIXUP computes dbase, bakes every
# absolute gvar/string address into the code, and only THEN does the DCE pass COMPACT and
# shrink `cp`. EMITELF_USER re-derived from the smaller `cp` and emitted a PT_LOAD at a
# vaddr the code had never been patched for.
#
# Measured on sankhya 3.0.1's `tests/sankhya.bcyr` at 6.6.2:
#
#     no DCE : LOAD vaddr=0x800000 RW   2,660,464 bytes   rc=0, full benchmark table
#     DCE    : LOAD vaddr=0x600000 RW     686,192 bytes   rc=139, ZERO output
#
# ...while the code still executed `movabsq $0x8000b0, %rcx; movq %rax, (%rcx)` — a store
# into unmapped space during GLOBAL INITIALISATION, so it died before main. The same repo's
# MAIN binary was fine with DCE because its code size happened to round into the same 2 MB
# bucket either way, which is why the filing read as "specific to the benchmark translation
# unit" rather than as a codegen defect.
#
# ⛔ WHY THIS GATE IS STRUCTURAL, and the reason must survive an "upgrade" attempt.
# The behavioural test needs a binary whose code crosses a 2 MB bucket when DCE compacts it.
# No in-tree fixture reaches that:
#   * cycc's own source: 1,251,864 -> 1,215,000 bytes. Both land at 0x600000 — no crossing,
#     so a gate built on it passes against the BROKEN compiler.
#   * synthetic dead code sized past 2 MB: DCE lists the fns as dead but does NOT compact.
#     Measured at 400 fns it compacts (220,701 bytes eliminated); at 4,200 and at 22,000 it
#     NOPs and stops. ⚠ CORRECTED 6.6.18: this read "`DECODE_WALK_OK` fails on the generated
#     bodies". It does not. The repair registry holds 4,096 dead-code runs (one per dead fn,
#     `_wpnr_add`, src/common/util.cyr) and a saturated registry declines the whole pass —
#     measured: 4,096 one-line dead fns compact, 4,097 decline, and since 6.6.18 the note says
#     so ("compaction declined on x86_64 ELF: more than 4096 dead-code runs"). So the bound is
#     the run count, not the body: ≤4,096 dead fns of ≳520 B each would cross a 2 MB bucket,
#     and this gate could be made behavioural that way. Until then it stays structural.
# Pinning the mechanism and SAYING so beats a behavioural-looking check that cannot fail —
# the same call `deps_family_expansion_ordered.sh` documents for its own case.
#
# Mutation-proven: deleting either `_wx_dbase_frozen` guard reddens this gate, and restores
# the sankhya segfault.
#
# See docs/development/issues/sankhya-dce-bench-segfault.md
#
# 6.6.20 — THE FREEZE IS A W^X-ONLY FIX (rows 6-7). Two layouts have no gap to freeze into: a
# `kernel;` image (ELF32 multiboot and CYRIUS_ELF64_KERNEL=1) and CYRIUS_WX=0 (one RWX PT_LOAD)
# put .bss/.rodata DIRECTLY after the code, from the post-compaction cp. Under CYRIUS_DCE=1 both
# compacted, so the data moved down under every address FIXUP had already patched in. The
# fix declines compaction for both (runtime.cyr _dce_compact_why) and names it in the
# unreachable-fns note. What THIS gate's probes measure on the 6.6.19 compiler:
#   Row 6 RUNS the WX=0 binary. Its probe (60 dead fns, 7,596 B eliminated) exits rc 0 and
#   writes 8 NUL bytes instead of "data-ok" (rc 42): .bss moved to 0x400150 while the code
#   still uses the pre-compaction 0x401ef8 (G) and 0x401f10 (the string), which now fall in
#   the zero-filled tail of the segment. Other shapes fault instead: the 6.6.20 audit's own
#   60-dead-fn probe (9,930 B eliminated) died rc 139. Either way, each flag alone exits 42.
#   Row 7 cannot run a kernel, so it DECODES one: the .bss and .rodata vaddrs readelf reports
#   must each occur as an imm64 inside .text. Its probe moves .bss 0x1003e0 -> 0x1000f8 on
#   ELF32 and 0x100428 -> 0x100140 on ELF64, while the code still addresses 0x1003e0 /
#   0x100428 — past the image, so a kernel scribbles memory instead of faulting.
#   Both rows also pin the decline note, and row 6's anti-vacuous half proves the probe really
#   compacts under W^X.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
fail() { echo "FAIL: dce_data_vaddr_frozen: $1"; exit 1; }

for BE in x86 aarch64; do
    F="$ROOT/src/backend/$BE/fixup.cyr"
    [ -f "$F" ] || fail "$BE: src/backend/$BE/fixup.cyr missing"

    # 1. the frozen slot exists
    grep -q '^var _wx_dbase_frozen = 0;' "$F" \
        || fail "$BE: no '_wx_dbase_frozen' global — the freeze was removed"

    # 2. FIXUP records the dbase it patched against
    grep -q '_wx_dbase_frozen = dbase;' "$F" \
        || fail "$BE: FIXUP does not record dbase into _wx_dbase_frozen"

    # 3. EMITELF_USER prefers the recorded value over a re-derive
    grep -q 'if (_wx_dbase_frozen != 0) { dbase = _wx_dbase_frozen; }' "$F" \
        || fail "$BE: EMITELF_USER re-derives dbase instead of using the frozen one"

    # 4. ANTI-VACUOUS: the recorded assignment must come BEFORE the emitter's override,
    #    otherwise all three greps could be satisfied by dead or misordered text.
    REC=$(grep -n '_wx_dbase_frozen = dbase;' "$F" | head -1 | cut -d: -f1)
    USE=$(grep -n 'if (_wx_dbase_frozen != 0) { dbase = _wx_dbase_frozen; }' "$F" | head -1 | cut -d: -f1)
    [ "$REC" -lt "$USE" ] \
        || fail "$BE: dbase is consumed at line $USE before it is recorded at line $REC"
done

# 5. a DCE build still runs — cheap smoke, and it does catch a gross break even though it
#    cannot catch the bucket-crossing case above.
CC="$ROOT/build/cycc"
[ -x "$CC" ] || fail "build/cycc missing"
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: dce_data_vaddr_frozen: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$WORK"' EXIT
cd "$ROOT"
printf 'include "lib/syscalls.cyr"\nvar gz = 0;\nfn unused_a(): i64 { return 1; }\nfn unused_b(): i64 { return 2; }\nfn main(): i64 { store64(&gz, 7); return load64(&gz) - 7; }\n' > "$WORK/t.cyr"
CYRIUS_DCE=1 "$CC" < "$WORK/t.cyr" > "$WORK/t.bin" 2>/dev/null || fail "DCE build failed"
chmod +x "$WORK/t.bin"
"$WORK/t.bin" || fail "a DCE-built binary did not exit 0"

# and the RW vaddr must match the non-DCE build of the same source
"$CC" < "$WORK/t.cyr" > "$WORK/n.bin" 2>/dev/null || fail "non-DCE build failed"
VD=$(readelf -lW "$WORK/t.bin" 2>/dev/null | awk '/LOAD/ && /RW/ {print $3}')
VN=$(readelf -lW "$WORK/n.bin" 2>/dev/null | awk '/LOAD/ && /RW/ {print $3}')
[ -n "$VD" ] || fail "could not read the DCE build's RW segment vaddr"
[ "$VD" = "$VN" ] || fail "RW vaddr moved under DCE: $VN -> $VD"

# 6. CYRIUS_WX=0: one RWX segment, data right after the code — compaction must decline, and
#    the binary must RUN. 60 dead fns, two globals and a string, so the data has somewhere to go.
awk 'BEGIN { for (i = 0; i < 60; i++) printf "fn dead%d(x): i64 { var a = x * %d; var b = a + 7; var c = b * b; return c - a + %d; }\n", i, i + 3, i * 1000 + 7;
             print "var G = 40;"; print "var H = 2;";
             print "fn main(): i64 { syscall(1, 1, \"data-ok\\n\", 8); G = G + H; return G; }";
             print "var rc = main();"; print "syscall(60, rc);" }' > "$WORK/w.cyr"
CYRIUS_DCE=1 "$CC" < "$WORK/w.cyr" > "$WORK/w_wx.bin" 2> "$WORK/w_wx.err" || fail "row 6: W^X DCE build failed"
grep -q 'dead code eliminated' "$WORK/w_wx.err" \
    || fail "row 6: the probe no longer compacts under W^X, so its WX=0 half proves nothing: $(cat "$WORK/w_wx.err")"
CYRIUS_DCE=1 CYRIUS_WX=0 "$CC" < "$WORK/w.cyr" > "$WORK/w0.bin" 2> "$WORK/w0.err" || fail "row 6: CYRIUS_WX=0 DCE build failed"
chmod +x "$WORK/w0.bin"
WRC=0
"$WORK/w0.bin" > "$WORK/w0.out" || WRC=$?
WOUT=$(tr -d '\000' < "$WORK/w0.out")
[ "$WRC" = 42 ] && [ "$WOUT" = "data-ok" ] \
    || fail "row 6: a CYRIUS_DCE=1 CYRIUS_WX=0 binary exits $WRC with output '$WOUT' (want 42, 'data-ok') — compaction moved the data under the patched addresses"
grep -q 'compaction declined on x86_64 ELF (CYRIUS_WX=0): the single RWX segment' "$WORK/w0.err" \
    || fail "row 6: the CYRIUS_WX=0 decline is not named in the unreachable-fns note: $(cat "$WORK/w0.err")"
if grep -q 'dead code eliminated' "$WORK/w0.err"; then fail "row 6: CYRIUS_WX=0 still compacts: $(cat "$WORK/w0.err")"; fi

# 7. `kernel;` (ELF32 multiboot, and CYRIUS_ELF64_KERNEL=1): data right after the code, no way to
#    run it here — so decode it. Every section vaddr the image claims for its data must be an
#    imm64 the code actually uses.
sect() {  # sect <bin> <name> -> "addr off size" (hex, no 0x)
    readelf -SW "$1" 2>/dev/null | awk -v n="$2" '{ for (i = 1; i <= NF; i++) if ($i == n) { print $(i + 2), $(i + 3), $(i + 4); exit } }'
}
imm_in_text() {  # imm_in_text <bin> <hex vaddr> — the 8-byte little-endian imm64 occurs in .text
    set -- "$1" "$2" $(sect "$1" .text)
    [ -n "${5:-}" ] || return 1
    want=$(printf '%016x' $((0x$2)) | sed 's/../& /g' | awk '{ for (i = NF; i >= 1; i--) printf " %s", $i; printf " " }')
    od -An -tx1 -v -j $((0x$4)) -N $((0x$5)) "$1" | tr '\n' ' ' | tr -s ' ' | grep -qF "$want"
}
{ echo 'kernel;'
  awk 'BEGIN { for (i = 0; i < 6; i++) printf "fn dead%d(x): i64 { var a = x * %d; var b = a + 7; var c = b * b; return c - a + %d; }\n", i, i + 3, i * 1000 + 7 }'
  printf 'var G = 40;\nfn main(): i64 { var s = "kdata"; G = G + load8(s); return G; }\nmain();\n'
} > "$WORK/k.cyr"
for KE in KERNEL32=1 CYRIUS_ELF64_KERNEL=1; do
    for D in 0 1; do
        env "$KE" CYRIUS_DCE=$D "$CC" < "$WORK/k.cyr" > "$WORK/k.bin" 2> "$WORK/k.err" || fail "row 7 ($KE DCE=$D): kernel build failed: $(tail -1 "$WORK/k.err")"
        for SN in .bss .rodata; do
            SA=$(sect "$WORK/k.bin" "$SN" | cut -d' ' -f1)
            [ -n "$SA" ] || fail "row 7 ($KE DCE=$D): no $SN section in the kernel image"
            imm_in_text "$WORK/k.bin" "$SA" \
                || fail "row 7 ($KE DCE=$D): $SN is at 0x$SA but no code addresses it — the data moved after the addresses were patched in (CYRIUS_DCE=1 compacted a kernel image)"
        done
    done
    grep -q 'compaction declined on x86_64 ELF (kernel;): a kernel image' "$WORK/k.err" \
        || fail "row 7 ($KE): the kernel decline is not named in the unreachable-fns note: $(cat "$WORK/k.err")"
done

echo "PASS: dce_data_vaddr_frozen (both backends record+consume in order; DCE build runs, RW vaddr $VD stable; CYRIUS_WX=0 and kernel; decline compaction and keep data where the code addresses it)"
