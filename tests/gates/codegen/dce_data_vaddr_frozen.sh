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
#     `DECODE_WALK_OK` fails on the generated bodies and the pass correctly bails (that
#     fail-safe is the v6.5.72 lesson). Measured at 400 fns it compacts (220,701 bytes
#     eliminated); at 4,200 and at 22,000 it NOPs and stops. So the fixture cannot be grown
#     into the regime under test.
# Pinning the mechanism and SAYING so beats a behavioural-looking check that cannot fail —
# the same call `deps_family_expansion_ordered.sh` documents for its own case.
#
# Mutation-proven: deleting either `_wx_dbase_frozen` guard reddens this gate, and restores
# the sankhya segfault.
#
# See docs/development/issues/sankhya-dce-bench-segfault.md
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
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
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

echo "PASS: dce_data_vaddr_frozen (both backends record+consume in order; DCE build runs, RW vaddr $VD stable)"
