#!/bin/sh
# x86_trig_calls_polyfill.sh — f64_sin / f64_cos on every x86 output (Linux ELF, PE, x86
# Mach-O) call lib/math.cyr's polyfill, never the x87 fsin / fcos.
#
# ⛔ THE DEFECT (6.6.9 bite 4; audit: x87 fsin/fcos on large arguments). EF64_SIN / EF64_COS
# emitted bare `D9 FE` / `D9 FF`. x87 reduces with a 66-bit π, so sin(π) was 1.6e11 ulp off,
# error grew from 2^10 up, and for |x| >= 2^63 the instruction leaves the argument UNCHANGED
# (sin(1e19) = 1e19). Precision control does not reach fsin, so PE and x86 Mach-O were the
# same. Now all three call `_f64_sin_polyfill` / `_f64_cos_polyfill` (CHANGELOG [6.6.9]).
#
# Axes, per x86 output format:
#   1. without `include "lib/math.cyr"` the compile FAILS (exit 1, not a crash) and names the
#      include — a missing polyfill must never become a call to fn index -1;
#   2. with it, the disassembly (llvm-objdump, which reads all three formats) has no fsin /
#      fcos — a byte scan is not enough, layout shifts put D9 FE / D9 FF into displacements;
#      SKIPPED, by name, without llvm-objdump;
#   3. sin(π), sin(1e19) and cos(DBL_MAX) are the correctly rounded bits — run here for the ELF
#      and under wine for the PE (SKIPPED, by name, without wine; wine is not hardware — real
#      cass and ach are the crossos trig_polyfill.tcyr rows).
# Mutation: the 6.6.8 compiler (the D9 FE / D9 FF bodies) → 8 FAIL rows: axis 1 on all three
# formats (it compiles without the include), axis 2 on all three, axis 3 on ELF and PE.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL x86_trig_calls_polyfill: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $T, never the user's ~/.wine: its one wineserver is shared by
# every concurrent check.sh on the box. The EXIT kill is scoped to THIS prefix and also removes
# its server socket dir (/tmp/.wine-<uid>/server-<dev>-<ino>). CHANGELOG [6.6.16]
# 6.6.17: wine's own HOME and XDG_CACHE_HOME are under $T too — a fresh prefix writes
# $HOME/.cache (mesa shader caches) — and `wineserver -k` leaves the server dir behind, so
# _wine_down removes it. CHANGELOG [6.6.17]
WP="$T/wine"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL x86_trig_calls_polyfill: no compiler at $CC"; exit 1; }
cd "$R" || exit 1
fail=0

printf 'fn main(): i64 { var x = 1.0; var y = f64_sin(x); var z = f64_cos(x); return 0; }\nvar e = main();\nsyscall(60, e);\n' > "$T/nomath.cyr"
cat > "$T/math.cyr" <<'EOF'
include "lib/math.cyr"
fn main(): i64 {
    if (f64_sin(0x400921FB54442D18) != 0x3CA1A62633145C07) { return 1; }
    if (f64_sin(0x43E158E460913D00) != 0xBFEDAA805F702A5C) { return 2; }
    if (f64_cos(0x7FEFFFFFFFFFFFFF) != 0xBFEFFFE62ECFAB75) { return 3; }
    return 42;
}
var e = main();
syscall(60, e);
EOF

OBJDUMP=$(command -v llvm-objdump 2>/dev/null || true)
[ -n "$OBJDUMP" ] || { echo "  SKIP axis 2: llvm-objdump not installed — no disassembly check"; GATE_SKIPS=$((${GATE_SKIPS:-0} + 1)); }

for fmt in elf pe macho; do
    case "$fmt" in
        elf)   envv="" ;;
        pe)    envv="CYRIUS_TARGET_WIN=1" ;;
        macho) envv="CYRIUS_MACHO=1" ;;
    esac
    env $envv "$CC" < "$T/nomath.cyr" > "$T/nm.$fmt" 2> "$T/nm.$fmt.err"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        echo "  FAIL [$fmt] axis 1: f64_sin without lib/math.cyr exited $rc, expected 1"; fail=1
    elif ! grep -q 'f64_sin requires include "lib/math.cyr"' "$T/nm.$fmt.err" \
      || ! grep -q 'f64_cos requires include "lib/math.cyr"' "$T/nm.$fmt.err"; then
        echo "  FAIL [$fmt] axis 1: the error does not name lib/math.cyr for both builtins"; fail=1
    else
        echo "  ok [$fmt] axis 1: a missing include is a named compile error (exit 1)"
    fi
    env $envv "$CC" < "$T/math.cyr" > "$T/m.$fmt" 2> "$T/m.$fmt.err" || {
        echo "  FAIL [$fmt] axis 2: the probe with lib/math.cyr did not compile"; fail=1; continue; }
    if [ -n "$OBJDUMP" ]; then
        "$OBJDUMP" -d "$T/m.$fmt" > "$T/m.$fmt.dis" 2>&1
        ins=$(grep -c . "$T/m.$fmt.dis")
        x87=$(grep -cE '[[:space:]](fsin|fcos|fsincos)([[:space:]]|$)' "$T/m.$fmt.dis")
        if [ "$ins" -lt 1000 ]; then
            echo "  FAIL [$fmt] axis 2: only $ins disassembly lines — llvm-objdump did not read the binary"; fail=1
        elif [ "$x87" -ne 0 ]; then
            echo "  FAIL [$fmt] axis 2: $x87 x87 fsin/fcos instruction(s) in the binary"; fail=1
        else
            echo "  ok [$fmt] axis 2: no x87 fsin/fcos in $ins disassembly lines"
        fi
    fi
done

chmod +x "$T/m.elf"
"$T/m.elf"; got=$?
if [ "$got" -ne 42 ]; then
    echo "  FAIL [elf] axis 3: sin(pi) / sin(1e19) / cos(DBL_MAX) row $got is not correctly rounded"; fail=1
else
    echo "  ok [elf] axis 3: sin(pi), sin(1e19), cos(DBL_MAX) are the correctly rounded bits"
fi
if command -v wine > /dev/null 2>&1; then
    export WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    cp "$T/m.pe" "$T/m.exe"
    wine "$T/m.exe" > /dev/null 2>&1; got=$?
    if [ "$got" -ne 42 ]; then
        echo "  FAIL [pe] axis 3: under wine, row $got is not correctly rounded"; fail=1
    else
        echo "  ok [pe] axis 3: under wine, the same correctly rounded bits"
    fi
else
    echo "  SKIP [pe] axis 3: wine not installed"
    GATE_SKIPS=$((${GATE_SKIPS:-0} + 1))
fi

if [ "$fail" -ne 0 ]; then
    echo "FAIL: x86_trig_calls_polyfill"
    exit 1
fi
# 6.6.11 (K1): an axis that could not run makes the gate a SKIP (77), never a PASS.
if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: x86_trig_calls_polyfill — $GATE_SKIPS axis/leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: x86 f64_sin / f64_cos (ELF, PE, x86 Mach-O) call lib/math.cyr's fdlibm polyfill, not x87 fsin/fcos, and a missing include is a named compile error (6.6.9)"
exit 0
