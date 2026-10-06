#!/bin/sh
# include_fallback_cyrius_home.sh — 6.6.16 (C10). cycc's `lib/...` include fallback reads the
# store slot of the home the CLI uses: CYRIUS_HOME/versions/<VERSION>/lib/ when CYRIUS_HOME is
# set and non-empty, else HOME/.cyrius/versions/<VERSION>/lib/ — and it reads the WHOLE
# environment to find them.
#
# ⛔ WHY. `_init_cyrius_lib` (src/frontend/lex.cyr) built the fallback from `HOME=` only, out of
# ONE 4096-B read of /proc/self/environ, while the comments beside it said CYRIUS_HOME. cbt
# resolves its home as CYRIUS_HOME, else $HOME/.cyrius, so under a CYRIUS_HOME that is not
# ~/.cyrius the CLI and the compiler read two different stdlibs: `cyrius distlib`'s verify
# compiled a leaf missing from ./lib against HOME's slot ahead of its own mirror, and
# distlib_sidecar_verified.sh had to pin HOME to a throwaway to stay hermetic. Measured on the
# slot open: HOME=A CYRIUS_HOME=B resolved A in both orders; CYRIUS_HOME=B alone did not
# resolve; a 5000-B variable ahead of HOME made the fallback vanish.
#
# THE ORACLE NEEDS NO RUN. The two homes' slots define DIFFERENT fns: HOME's zz_c10.cyr defines
# zz_from_home, CYRIUS_HOME's defines zz_from_chome. `mc.cyr` calls only zz_from_chome and
# `mh.cyr` only zz_from_home, so a wrong selection fails the compile with the reachable-undefined
# refusal, and no selection fails it with `cannot open include file`. That lets one matrix cover
# every Linux-targeted compiler built from this tree: x86, the aarch64 cross, cx, the
# Linux-hosted PE cross, and the native aarch64 fork under qemu-aarch64 (the openat branch). The
# x86 rows also RUN the binary (exit 22 = CYRIUS_HOME's, 11 = HOME's). The macOS forks and the
# PE-native cycc.exe compile the fallback out (`#ifdef CYRIUS_TARGET_LINUX`), as before.
#
# Rows, per compiler: precedence in both environ orders; CYRIUS_HOME alone and with a missing
# HOME; unset (HOME's slot, unchanged) + its anti-vacuous twin; empty CYRIUS_HOME = unset, both
# orders; CYRIUS_HOME's slot lacking the file (and a nonexistent CYRIUS_HOME) is
# `cannot open include file`, NEVER HOME's copy; a 5000-B and a 9000-B variable ahead of both;
# a split of `CYRIUS_HOME=` across the 4096-B and 8192-B read boundaries at five offsets; a
# CYRIUS_HOME of exactly 1984 B accepted and of 1985 B refused with NO fallback (not HOME's, not
# a truncated prefix — the padding is `/.` steps, so any prefix of it names B too); an over-long
# HOME is no fallback and does not disable CYRIUS_HOME; a relative CYRIUS_HOME resolves from the
# CWD; the cyrius.cyml pin-drift warning is printed exactly once on EITHER branch and not at all
# when no slot is selected.
#
# `--compiler <cycc>` runs the matrix against ONE prebuilt, host-native compiler and builds
# nothing (the pi leg: a native aarch64 cycc cross-built from the tree). CHANGELOG [6.6.16]
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
G=include_fallback_cyrius_home
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
[ -r /proc/self/environ ] || { echo "SKIP: $G: no /proc/self/environ on this host — the fallback is Linux-only"; exit 77; }
VER=$(sed -n 's/^var _VERSION_TOOLCHAIN *= *"\(.*\)";.*/\1/p' "$R/src/version_str.cyr")
[ -n "$VER" ] || { echo "FAIL: $G: could not read _VERSION_TOOLCHAIN from src/version_str.cyr"; exit 1; }
QEMU=$(command -v qemu-aarch64 2>/dev/null || true)

# ── the compilers: label, binary, runner, whether its output runs here ──────────────────────────
mkdir -p "$T/cc"
: > "$T/compilers"
if [ "${1:-}" = "--compiler" ]; then
    [ -n "${2:-}" ] && [ -x "$2" ] || { echo "FAIL: $G: --compiler needs an executable compiler"; exit 1; }
    echo "given $2 - 1" >> "$T/compilers"
else
    CC=${CYCC:-"$R/build/cycc"}
    [ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
    cd "$R" || exit 1
    "$CC" < src/main.cyr > "$T/cc/x86" 2> "$T/eb" || { echo "FAIL: $G: could not build src/main.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
    "$CC" < src/main_aarch64.cyr > "$T/cc/aarch64" 2> "$T/eb" || { echo "FAIL: $G: could not build src/main_aarch64.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
    "$CC" < src/main_cx.cyr > "$T/cc/cx" 2> "$T/eb" || { echo "FAIL: $G: could not build src/main_cx.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
    "$CC" < src/main_win.cyr > "$T/cc/pe_cross" 2> "$T/eb" || { echo "FAIL: $G: could not build src/main_win.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
    chmod +x "$T/cc/x86" "$T/cc/aarch64" "$T/cc/cx" "$T/cc/pe_cross"
    {
        echo "x86 $T/cc/x86 - 1"
        echo "aarch64 $T/cc/aarch64 - 0"
        echo "cx $T/cc/cx - 0"
        echo "pe_cross $T/cc/pe_cross - 0"
    } >> "$T/compilers"
    if [ -n "$QEMU" ]; then
        "$T/cc/aarch64" < src/main_aarch64_native.cyr > "$T/cc/aarch64_native" 2> "$T/eb" \
            || { echo "FAIL: $G: could not build src/main_aarch64_native.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
        chmod +x "$T/cc/aarch64_native"
        echo "aarch64_native $T/cc/aarch64_native $QEMU 0" >> "$T/compilers"
    else
        echo "  SKIP (named): the aarch64-native fork (the openat branch) — qemu-aarch64 is not installed"
    fi
fi

# ── the homes ───────────────────────────────────────────────────────────────────────────────────
A="$T/A"; B="$T/B"; C="$T/C"
mkdir -p "$A/.cyrius/versions/$VER/lib" "$B/versions/$VER/lib" "$C/versions/$VER/lib" "$T/cwd" "$T/pin"
echo 'fn zz_from_home(): i64 { return 11; }' > "$A/.cyrius/versions/$VER/lib/zz_c10.cyr"
echo 'fn zz_from_chome(): i64 { return 22; }' > "$B/versions/$VER/lib/zz_c10.cyr"
# C's slot exists and holds every OTHER leaf name a careless fix might probe; not zz_c10.cyr.
echo 'fn zz_other(): i64 { return 0; }' > "$C/versions/$VER/lib/zz_other.cyr"
for d in "$T/cwd" "$T/pin"; do
    printf 'include "lib/zz_c10.cyr"\nsyscall(60, zz_from_chome());\n' > "$d/mc.cyr"
    printf 'include "lib/zz_c10.cyr"\nsyscall(60, zz_from_home());\n' > "$d/mh.cyr"
done
printf '[package]\nname = "zzpin"\nversion = "0.1.0"\ncyrius = "0.0.1"\n' > "$T/pin/cyrius.cyml"
# `pad N` = N bytes of x. `longpath BASE N` = BASE padded with `/.` steps to exactly N bytes, so
# the whole path AND every prefix of the padding still name BASE.
pad() { head -c "$1" /dev/zero | tr '\0' x; }
longpath() {
    _p=$1
    while [ "${#_p}" -lt "$(($2 - 1))" ]; do _p="$_p/."; done
    [ "${#_p}" -lt "$2" ] && _p="$_p/"
    printf '%s' "$_p"
}
P5000=$(pad 5000); P9000=$(pad 9000)
B1984=$(longpath "$B" 1984); B1985=$(longpath "$B" 1985); A2100=$(longpath "$A" 2100)
[ "${#B1984}" -eq 1984 ] && [ "${#B1985}" -eq 1985 ] || { echo "FAIL: $G: could not build the 1984/1985-B paths"; exit 1; }

# The order rows are only rows if `env -i` keeps the order it is given.
ORD=$(env -i ZZ_A=1 ZZ_B=2 /bin/cat /proc/self/environ | tr '\0' ' ')
[ "$ORD" = "ZZ_A=1 ZZ_B=2 " ] || { echo "FAIL: $G: env -i does not keep the environ order ([$ORD]) — the order and split rows would be vacuous"; exit 1; }

fail=0
pass=0
_ok()  { pass=$((pass + 1)); }
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# row <expect> <main> <dir> <name> VAR=VAL... — compile <dir>/<main>.cyr with exactly that
# environment. expect: ok (compiles), nofile (`cannot open include file`), undef (the reachable-
# undefined refusal, naming the fn the other slot lacks).
row() {
    _e=$1; _m=$2; _d=$3; _n=$4; shift 4
    if [ "$RUN" = - ]; then
        ( cd "$_d" && env -i "$@" "$BIN" < "$_m.cyr" > "$T/o" 2> "$T/e" ); _rc=$?
    else
        ( cd "$_d" && env -i "$@" "$RUN" "$BIN" < "$_m.cyr" > "$T/o" 2> "$T/e" ); _rc=$?
    fi
    case "$_e" in
        ok)
            if [ "$_rc" -ne 0 ] || [ ! -s "$T/o" ]; then
                _bad "[$LBL] $_n: $_m did not compile (rc $_rc): $(grep -v '^note' "$T/e" | head -2 | tr '\n' ' ')"
                return
            fi
            if [ "$NATIVE" = 1 ]; then
                chmod +x "$T/o"; "$T/o" < /dev/null; _x=$?
                _want=22; [ "$_m" = mh ] && _want=11
                [ "$_x" -eq "$_want" ] || { _bad "[$LBL] $_n: the $_m binary exited $_x, not $_want"; return; }
            fi ;;
        nofile)
            if [ "$_rc" -eq 0 ] || ! grep -q 'cannot open include file: lib/zz_c10.cyr' "$T/e"; then
                _bad "[$LBL] $_n: expected 'cannot open include file' (rc $_rc): $(grep -v '^note' "$T/e" | head -2 | tr '\n' ' ')"
                return
            fi ;;
        undef)
            _fn=zz_from_chome; [ "$_m" = mh ] && _fn=zz_from_home
            # x86/aarch64/PE: "undefined function 'f'"; cx lists "  - f" under its own refusal.
            if [ "$_rc" -eq 0 ] || ! grep -qE "undefined function '$_fn'|^ *- $_fn\$" "$T/e"; then
                _bad "[$LBL] $_n: expected the undefined-$_fn refusal (rc $_rc): $(grep -v '^note' "$T/e" | head -2 | tr '\n' ' ')"
                return
            fi ;;
    esac
    _ok
}

# drift <want-count> <main> <name> VAR=VAL... — compile in a dir whose cyrius.cyml pins 0.0.1 and
# count the pin-drift warnings: one when a home selected a slot (whether or not it exists), none
# when no home did — neither variable set, or an over-long CYRIUS_HOME.
drift() {
    _w=$1; _m=$2; _n=$3; shift 3
    if [ "$RUN" = - ]; then
        ( cd "$T/pin" && env -i "$@" "$BIN" < "$_m.cyr" > "$T/o" 2> "$T/e" )
    else
        ( cd "$T/pin" && env -i "$@" "$RUN" "$BIN" < "$_m.cyr" > "$T/o" 2> "$T/e" )
    fi
    _c=$(grep -c 'cyrius.cyml pins 0.0.1' "$T/e")
    [ "$_c" -eq "$_w" ] && _ok || _bad "[$LBL] $_n: $_c pin-drift warnings, expected $_w"
}

# strict <name> VAR=VAL... — CYRIUS_STRICT_PIN=1 must REFUSE the pinned-elsewhere build (6.6.17).
strict() {
    _n=$1; shift
    _rc=0
    if [ "$RUN" = - ]; then
        ( cd "$T/pin" && env -i "$@" "$BIN" < mc.cyr > "$T/o" 2> "$T/e" ) || _rc=$?
    else
        ( cd "$T/pin" && env -i "$@" "$RUN" "$BIN" < mc.cyr > "$T/o" 2> "$T/e" ) || _rc=$?
    fi
    if [ "$_rc" -ne 0 ] && grep -q 'toolchain drift (CYRIUS_STRICT_PIN)' "$T/e"; then _ok
    else _bad "[$LBL] $_n: CYRIUS_STRICT_PIN=1 did not refuse (rc $_rc)"; fi
}

NCOMP=0
while read -r LBL BIN RUN NATIVE; do
    NCOMP=$((NCOMP + 1))
    # precedence, both environ orders
    row ok mc "$T/cwd" home_then_chome HOME="$A" CYRIUS_HOME="$B"
    row ok mc "$T/cwd" chome_then_home CYRIUS_HOME="$B" HOME="$A"
    row undef mh "$T/cwd" chome_wins_over_home HOME="$A" CYRIUS_HOME="$B"
    # CYRIUS_HOME alone; with HOME naming nothing
    row ok mc "$T/cwd" chome_only CYRIUS_HOME="$B"
    row ok mc "$T/cwd" chome_home_missing HOME="$T/nonexistent" CYRIUS_HOME="$B"
    # unset: HOME's slot, unchanged; the anti-vacuous twin proves A lacks zz_from_chome
    row ok mh "$T/cwd" unset_home_slot HOME="$A"
    row undef mc "$T/cwd" unset_anti_vacuous HOME="$A"
    # empty = unset, both orders
    row ok mh "$T/cwd" empty_chome HOME="$A" CYRIUS_HOME=
    row ok mh "$T/cwd" empty_chome_first CYRIUS_HOME= HOME="$A"
    # CYRIUS_HOME is authoritative: its slot lacking the file is an error, never HOME's copy
    row nofile mh "$T/cwd" slot_missing_no_fallthrough HOME="$A" CYRIUS_HOME="$C"
    row nofile mh "$T/cwd" chome_nonexistent_no_fallthrough HOME="$A" CYRIUS_HOME="$T/nonexistent"
    # past 4 KB and 8 KB of environment
    row ok mc "$T/cwd" pad5000_both PAD="$P5000" HOME="$A" CYRIUS_HOME="$B"
    row ok mh "$T/cwd" pad5000_home PAD="$P5000" HOME="$A"
    row ok mc "$T/cwd" pad9000_both PAD="$P9000" CYRIUS_HOME="$B" HOME="$A"
    row ok mh "$T/cwd" pad9000_home PAD="$P9000" HOME="$A"
    # `CYRIUS_HOME=` split across a read boundary: PAD=<n> + NUL puts it at byte n+5 — n=4070 value
    # straddles, 4079 the value starts the next chunk, 4085 the name straddles, 4091 the name
    # starts it; 8181 straddles the second boundary.
    for n in 4070 4079 4085 4091 8181; do
        row ok mc "$T/cwd" "split_$n" PAD="$(pad "$n")" CYRIUS_HOME="$B" HOME="$A"
        row ok mh "$T/cwd" "split_home_$n" PAD="$(pad "$n")" HOME="$A"
    done
    # the 1984-B bound: exactly 1984 is a home; 1985 is NO fallback — not HOME's, not a prefix
    row ok mc "$T/cwd" chome_1984 CYRIUS_HOME="$B1984" HOME="$A"
    row nofile mc "$T/cwd" chome_1985_no_fallback CYRIUS_HOME="$B1985" HOME="$A"
    row nofile mh "$T/cwd" chome_1985_not_home HOME="$A" CYRIUS_HOME="$B1985"
    # an over-long HOME: no fallback (CVE-34), and it does not disable CYRIUS_HOME
    row nofile mh "$T/cwd" home_2100_no_fallback HOME="$A2100"
    row ok mc "$T/cwd" home_2100_chome_ok HOME="$A2100" CYRIUS_HOME="$B"
    # a relative CYRIUS_HOME resolves against the compiler's CWD, as the CLI's does
    row ok mc "$T/cwd" chome_relative CYRIUS_HOME=../B HOME="$A"
    # the pin-drift check runs once after EITHER branch selects a slot, never without one
    drift 1 mc drift_chome_branch CYRIUS_HOME="$B"
    drift 1 mh drift_home_branch HOME="$A"
    drift 0 mh drift_no_home
    drift 0 mh drift_overlong_chome CYRIUS_HOME="$B1985" HOME="$A"
    # 6.6.17 — the opt-out knobs are read from the WHOLE environ too (`_env_var_is_1` was ONE
    # 4096-B read, so a knob past 4 KB was ignored): past 4 KB, past 8 KB, across the 4096-B
    # boundary (PAD= + 4080 B + NUL puts the knob at byte 4085); a value other than `1` is unset.
    drift 0 mc drift_nowarn CYRIUS_HOME="$B" CYRIUS_NO_WARN_PIN_DRIFT=1
    drift 0 mc drift_nowarn_pad5000 CYRIUS_HOME="$B" PAD="$P5000" CYRIUS_NO_WARN_PIN_DRIFT=1
    drift 0 mc drift_nowarn_pad9000 PAD="$P9000" CYRIUS_HOME="$B" CYRIUS_NO_WARN_PIN_DRIFT=1
    drift 0 mc drift_nowarn_split PAD="$(pad 4080)" CYRIUS_NO_WARN_PIN_DRIFT=1 CYRIUS_HOME="$B"
    drift 1 mc drift_nowarn_not_one CYRIUS_HOME="$B" PAD="$P5000" CYRIUS_NO_WARN_PIN_DRIFT=11
    strict drift_strict_pad5000 CYRIUS_HOME="$B" PAD="$P5000" CYRIUS_STRICT_PIN=1
done < "$T/compilers"

[ "$NCOMP" -ge 1 ] || _bad "no compiler ran (floor 1)"
[ "${1:-}" = "--compiler" ] || [ "$NCOMP" -ge 4 ] || _bad "only $NCOMP compilers ran (floor 4)"
[ "$pass" -ge $((NCOMP * 35)) ] || _bad "only $pass rows passed for $NCOMP compilers (floor 35 each)"

if [ "$fail" -ne 0 ]; then
    echo "FAIL $G: $fail failed, $pass passed"
    exit 1
fi
echo "PASS $G: $pass rows over $NCOMP compilers [$(cut -d' ' -f1 "$T/compilers" | tr '\n' ' ')] — CYRIUS_HOME's slot before HOME's in both orders, empty = unset, no fall-through, the whole environ read (past 4 KB / 8 KB and across read boundaries), the 1984-B bound never truncated, pin drift once on either branch, its opt-out knobs read past 4 KB too"
exit 0
