#!/bin/sh
# tests/valform_simd_crosstarget.sh — v6.4.81
#
# CYRIUS_HAS_VAL_SIMD_PARAMS must be predefined on EVERY emit path, including the
# PE and Mach-O CROSS paths, not only the native forks.
#
# THE BUG THIS GUARDS (silent, no diagnostic, found 2026-07-27 by the closeout audit):
# All six NATIVE forks predefine the flag — main_win.cyr:459 since v6.4.31,
# main_cx.cyr:129 since .54, main_x86_macho.cyr:163, main_aarch64*.cyr — but
# src/main.cyr's PE and Mach-O CROSS arms predefined only the target macro. So
# lib/simd.cyr's whole value-form block vanished when you cross-built, and the SAME
# SOURCE produced two different programs depending on WHERE it was built:
# f32v4_add(a,b) compiled natively on cass/ecb/ach and died with "undefined
# function" under `cyrius build --target win` from Linux. Half-shipped for a minor.
#
# WHY THIS IS A HOST-SIDE GATE AND NOT A tcyr:
# The defect IS the cross path diverging from the native one. A tcyr runs natively on
# each host, so on cass it exercises main_win.cyr — the fork that was always correct —
# and stays green through the entire bug. The cross-emit has to be checked on the
# build host. This is the same reason the release gate's `vr01_` glob could not see it.

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"

if [ ! -x "$CC" ]; then
    printf "  SKIP: valform-simd-crosstarget — %s not built\n" "$CC"
    exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat > "$T/probe.cyr" <<'EOF'
#ifdef CYRIUS_HAS_VAL_SIMD_PARAMS
fn probe(): i64 { return 1; }
#endif
fn main(): i64 { return probe(); }
EOF

fail=0
# Each target's emit path must define the flag. A missing predefine makes `probe`
# undefined and cycc fails closed -- which is exactly the signal we assert on.
for spec in "native:" "pe:CYRIUS_TARGET_WIN=1" "macho:CYRIUS_MACHO=1" "agnos:CYRIUS_TARGET_AGNOS=1"; do
    name=${spec%%:*}
    envv=${spec#*:}
    if [ -n "$envv" ]; then
        env "$envv" "$CC" < "$T/probe.cyr" > "$T/out.$name" 2> "$T/err.$name" || true
    else
        "$CC" < "$T/probe.cyr" > "$T/out.$name" 2> "$T/err.$name" || true
    fi
    if [ -s "$T/out.$name" ] && ! grep -q "reachable undefined" "$T/err.$name"; then
        printf "  PASS: valform-simd-crosstarget — %s predefines CYRIUS_HAS_VAL_SIMD_PARAMS\n" "$name"
    else
        printf "  FAIL: valform-simd-crosstarget — %s does NOT predefine CYRIUS_HAS_VAL_SIMD_PARAMS\n" "$name"
        printf "        (value-form SIMD would silently vanish when emitting for this target)\n"
        head -2 "$T/err.$name" | sed 's/^/        /'
        fail=1
    fi
done

exit $fail
