#!/bin/sh
# tests/gates/frontend/silent_values_checked.sh — 6.7.6 (Break 1, lane D)
#
# SILENT WRONG VALUES (the user's decisions, 2026-10-08 — roadmap "Break 1 decisions"):
#   F  `var x: f32 = <an f64 value>` ROUNDS to f32 (a local, a global in either zone, a for-init),
#      as a 6.7.4 `f32[N]` list element does; it stored the f64 bits, which read as 0.0. The
#      runtime half is tests/tcyr/crossos/f32_scalar_init_rounds.tcyr (A rows).
#   I  CYRIUS_IR=3 keeps the x86 f32 conversions (`f32_from`, `f32_to`, and the initializer's): their
#      raw bytes were not IR-recorded, so the opt-in pass forwarded rax across them (a prerequisite
#      of F under IR=3; pre-existing since the builtins landed).
#   A  ANTI-VACUOUS: each crossos tcyr on x86_64 (default, CYRIUS_IR=3, CYRIUS_DCE=1) and with
#      compilers built from this tree on aarch64 (qemu), cx (cxvm) and PE (wine, a private prefix),
#      with its full assertion count.
#
# MUTATION LEDGER (scratch trees, each rebuilt with the one change, run as CYCC=<mutant>; 2026-10-08):
#   (filled in below as each row lands)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=silent_values_checked
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $T (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper. CHANGELOG [6.6.16] [6.6.17]
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
ulimit -c 0 2>/dev/null || true
cd "$ROOT"
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; timeout 60 env ${2:-} "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
exits() {   # <name> <want> <what> <source> [ENV=V]: builds (under ENV), runs, exits <want>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1" "${5:-}"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}

# ── I: CYRIUS_IR=3 and the x86 f32 conversions ──────────────────────────────────────────────────
I1='fn lo32(p): i64 { return load32(p) & 0xFFFFFFFF; }\nfn main(): i64 {\n    var y: f64 = 1.5;\n    var fy: f32 = f32_from(y);\n    var ok = 0;\n    if (lo32(&fy) == 0x3FC00000) { ok = ok + 1; }\n    var m: f32 = f32_from(1.5);\n    var m2: f32 = m * f32_from(2.0);\n    if (f32_to(m2) == 0x4008000000000000) { ok = ok + 2; }\n    var g: f32 = y;\n    if (lo32(&g) == 0x3FC00000) { ok = ok + 4; }\n    return ok;\n}\nsyscall(60, main());\n'
exits i1 7 "I1: f32_from / f32_to / an f32 initializer under CYRIUS_IR=3" "$I1" CYRIUS_IR=3
exits i2 7 "I2: ... the same program, default pipeline" "$I1"

# ── A: each crossos tcyr, every leg, with its full assertion count ─────────────────────────────
X86_LEGS="plain IR3 DCE"
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2>/dev/null && [ -s "$T/cc_a64" ]; then chmod +x "$T/cc_a64"
    else bad "A0: could not build src/main_aarch64.cyr"; fi
fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2>/dev/null && [ -s "$T/cc_cx" ] && \
   "$CC" < programs/cxvm.cyr > "$T/cxvm" 2>/dev/null && [ -s "$T/cxvm" ]; then chmod +x "$T/cc_cx" "$T/cxvm"
else bad "A0: could not build src/main_cx.cyr / programs/cxvm.cyr"; fi
tcyr_ok() {   # <label> <output file> <exit> <want>
    if [ "$3" -eq 0 ] && grep -q "^$4 passed, 0 failed" "$2"; then ok "$1: $4 passed"
    else bad "$1: exit $3, $(grep -E 'passed|FAIL' "$2" | tr -d '\r' | head -3 | tr '\n' '|')"; fi
}
tcyr_all() {   # <tag> <tcyr path> <assertion floor>
    tg=$1; TC="$ROOT/$2"
    want=$(grep -cE '^ *assert_eq\(' "$TC")
    [ "$want" -ge "$3" ] || bad "$tg: only $want assertions derived from $2 (floor $3)"
    for mode in $X86_LEGS; do
        case $mode in
            plain) env_=""; lbl="$tg x86" ;;
            IR3) env_="CYRIUS_IR=3"; lbl="$tg x86, CYRIUS_IR=3" ;;
            DCE) env_="CYRIUS_DCE=1"; lbl="$tg x86, CYRIUS_DCE=1" ;;
        esac
        rc=0; env $env_ "$CC" < "$TC" > "$T/$tg.$mode" 2> "$T/$tg.$mode.err" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/$tg.$mode.err" | head -1)"; continue; fi
        chmod +x "$T/$tg.$mode"; got=0; timeout 60 "$T/$tg.$mode" > "$T/$tg.$mode.out" 2>&1 || got=$?
        tcyr_ok "$lbl" "$T/$tg.$mode.out" "$got" "$want"
    done
    if [ -x "$T/cc_a64" ]; then
        if "$T/cc_a64" < "$TC" > "$T/$tg.a" 2> "$T/$tg.aerr"; then
            chmod +x "$T/$tg.a"; got=0; (cd "$T" && timeout 120 qemu-aarch64 "./$tg.a" > "$T/$tg.aout" 2>&1) || got=$?
            tcyr_ok "$tg aarch64 (qemu)" "$T/$tg.aout" "$got" "$want"
        else bad "$tg aarch64: the tcyr did not compile: $(grep '^error' "$T/$tg.aerr" | head -1)"; fi
    else echo "  SKIP $tg aarch64 — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
    if [ -x "$T/cc_cx" ]; then
        if "$T/cc_cx" < "$TC" > "$T/$tg.cyx" 2> "$T/$tg.cxerr" && [ -s "$T/$tg.cyx" ]; then
            got=0; timeout 120 "$T/cxvm" < "$T/$tg.cyx" > "$T/$tg.cxout" 2>&1 || got=$?
            tcyr_ok "$tg cx (cxvm)" "$T/$tg.cxout" "$got" "$want"
        else bad "$tg cx: the tcyr did not compile: $(grep '^error' "$T/$tg.cxerr" | head -1)"; fi
    fi
    if command -v wine > /dev/null 2>&1; then
        if CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$T/$tg.exe" 2> "$T/$tg.werr" && [ -s "$T/$tg.exe" ]; then
            got=0
            (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$tg.exe" > "$T/$tg.wout" 2>/dev/null) || got=$?
            tcyr_ok "$tg PE (wine)" "$T/$tg.wout" "$got" "$want"
        else bad "$tg PE: the tcyr did not compile: $(grep '^error' "$T/$tg.werr" | head -1)"; fi
    else echo "  SKIP $tg PE — wine not installed"; skips=$((skips + 1)); fi
}
tcyr_all AF tests/tcyr/crossos/f32_scalar_init_rounds.tcyr 30

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — f32 initializers round (F); IR=3 keeps the f32 conversions (I); every tcyr on x86_64 / IR / DCE / aarch64 / cx / PE (A)"
