#!/bin/sh
# tests/gates/platform/poison_env_rung.sh — 6.7.11
#
# CYRIUS_POISON reads like CYRIUS_BOUNDS and CYRIUS_COVERAGE on EVERY compiler fork: `1` on; `0`,
# empty or unset off; any other value refused by name — `error: CYRIUS_POISON must be 0 or 1 (or
# unset): <v>`, rc 1, nothing written (user decision, 2026-10-13).
#
# THE FILED DEFECT (docs/development/issues/archived/2026-10-10-poison-env-zero-or-empty-turns-mode-on.md).
# Each of the seven forks read the variable itself — `var _poison_env_early =
# _read_env("CYRIUS_POISON"); if (_poison_env_early != 0) { PP_PREDEFINE(S, "CYRIUS_POISON"); }`
# — and `_read_env` returns a pointer for ANY set variable, so `CYRIUS_POISON=0`, an empty value
# and `no` all built the poisoned binary (redzones, poison fill, quarantine-on-free) without a
# word: the repro exited 7 for each, 0 only when unset. The fix decides it ONCE, in the shared
# PREPROCESS beside `_bnd_setup` / `_cov_setup` (src/frontend/parse_cov.cyr `_poison_setup`,
# through lex_pp.cyr's `_pp_env_rung`), and the seven fork reads are gone.
#
# THE ROWS.
#   S   static: no src/main*.cyr fork reads CYRIUS_POISON in code (floor 7 forks); src/ reads it
#       exactly once, through `_pp_env_rung`, in parse_cov.cyr, which is the one PP_PREDEFINE of
#       it; PREPROCESS calls `_poison_setup` before PP_PASS (the first `#ifdef`).
#   R   the filed repro VERBATIM (exit 7 = the predefine is on), compiled by every fork that can
#       execute here and RUN on its target, for 1 / 0 / empty / no / unset — 7 / 0 / 0 / refused
#       (rc 1, 0 bytes, the named error) / 0:
#         x86 (build/cycc, or $CYCC)               output run natively
#         a64_cross (main_aarch64.cyr, x86 host)   output under qemu-aarch64
#         cx (main_cx.cyr)                         output under cxvm
#         win_host (main_win.cyr, x86 host)        output under wine
#         aarch64_qemu, native_qemu                the aarch64 / native-aarch64 COMPILERS under
#                                                  qemu-aarch64 (their own env read), output too
#         cycc.exe_wine, cx.exe_wine               the PE compilers under wine (kernel32's
#                                                  GetEnvironmentVariableA), outputs under wine / cxvm
#       The two Mach-O forks cannot execute here; they share PREPROCESS (row S) and were probed by
#       hand on ecb / ach at 6.7.11 (CHANGELOG). qemu and wine are emulation: pi and cass run the
#       crossos leg at the release gate.
#   F   `cyrius fuzz --poison` is unchanged: the CLI injects `CYRIUS_POISON=1` FIRST in the
#       compiler's environment, so a harness that exits 0 only under the predefine passes with
#       --poison whether the shell has the variable unset, `0` or `no`; without --poison it fails
#       (unset and `0`: the predefine is off) and an inherited `no` is a COMPILE FAIL naming it.
#
# MUTATION PROOF (scratch copies of the tree, x86 cycc rebuilt from the mutated src/ twice and
# passed as $CYCC, every other fork built from it by this gate; GREEN 52/52 on the real tree):
#   M1  `_poison_setup` back to the old test (`_read_env(..) != 0`)    RED 26: S2 x2, R 0 / no on all
#                                                                      8 forks and empty on the 6
#                                                                      non-wine ones, F5, F6
#   M2  the `_poison_setup(S)` call dropped from PREPROCESS             RED 21: S3, R 1 / no on all 8
#                                                                      forks, F1-F3, F6
#   M3  main_cx.cyr's 6.7.10 read restored beside the shared one       RED 6: S1, S2 x2, cx 0 / empty,
#                                                                      cx.exe_wine 0
#   M4  the 6.7.10 x86 cycc as $CYCC (the other forks still built      RED 5: x86 0 / empty / no, F5, F6
#       from this tree's src/)
# (Under wine an EMPTY variable reads as unset — GetEnvironmentVariableA — so the two wine compilers'
# empty rows are off with the old test too: they hold the rule, they cannot tell the two apart.)
set -u
G=poison_env_rung
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
REPRO=docs/development/issues/repros/2026-10-10-poison-env-zero-or-empty-turns-mode-on.cyr
[ -x "$CC" ] || { echo "FAIL: $G — no compiler at $CC"; exit 1; }
[ -f "$REPRO" ] || { echo "FAIL: $G — the filed repro $REPRO is missing"; exit 1; }
command -v timeout > /dev/null 2>&1 || { echo "FAIL: $G — needs timeout(1)"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix (and wine's own HOME / XDG_CACHE_HOME) under $T; the EXIT teardown stops
# THIS prefix's wineserver and removes its server dir, which `wineserver -k` leaves behind.
WP="$T/wine"; mkdir -p "$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
ulimit -c 0
fails=0
checks=0
skips=0
check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

echo "== S: one reader, in the shared PREPROCESS =="
nf=0; nread=0
for f in src/main*.cyr; do
    nf=$((nf + 1))
    n=$(sed 's/#.*//' "$f" | grep -c 'CYRIUS_POISON' || :)
    nread=$((nread + n))
done
[ "$nf" -ge 7 ] && nf=ok
check "S1 the compiler forks (floor 7)" ok "$nf"
check "S1 no fork reads CYRIUS_POISON in code" 0 "$nread"
check "S2 no _read_env(\"CYRIUS_POISON\") anywhere in src/" 0 "$(grep -rh '_read_env("CYRIUS_POISON")' src | sed 's/#.*//' | grep -c '_read_env' || :)"
check "S2 one rung read, in parse_cov.cyr" "src/frontend/parse_cov.cyr" "$(grep -rl '_pp_env_rung(S, "CYRIUS_POISON") == 1' src | paste -sd' ' -)"
check "S2 one predefine of it, in parse_cov.cyr" "src/frontend/parse_cov.cyr:1" "$(grep -rc 'PP_PREDEFINE(S, "CYRIUS_POISON")' src | grep -v ':0$' | paste -sd' ' -)"
order=$(awk '/^fn PREPROCESS\(S\)/ {on = 1} on && /_poison_setup\(S\);/ && !p {p = NR} on && /PP_PASS\(S\);/ && !q {q = NR} on && /^}/ {exit} END {if (p && q && p < q) print "before"; else print "p=" p " q=" q}' src/frontend/lex_pp.cyr)
check "S3 PREPROCESS calls _poison_setup before PP_PASS" before "$order"

echo "== R: the filed repro on every fork that can execute here =="
mk() {   # $1 out, $2 source, $3 compiler (a command), $4.. env
    o=$1; s=$2; c=$3; shift 3
    if ! env -u CYRIUS_POISON "$@" $c < "$s" > "$T/$o" 2> "$T/$o.err" || [ "$(wc -c < "$T/$o" | tr -d ' ')" -lt 1024 ]; then
        echo "FAIL: $G — building $o from $s failed: $(grep -m1 -i error "$T/$o.err")"; exit 1
    fi
    chmod +x "$T/$o"
}
mk a64x src/main_aarch64.cyr "$CC"
mk cx   src/main_cx.cyr      "$CC"
mk cxvm programs/cxvm.cyr    "$CC"
mk xwin src/main_win.cyr     "$CC"
HAVE_QEMU=0; command -v qemu-aarch64 > /dev/null 2>&1 && HAVE_QEMU=1
HAVE_WINE=0; command -v wine > /dev/null 2>&1 && HAVE_WINE=1
W="env HOME=$T/whome XDG_CACHE_HOME=$T/whome/.cache wine"
# "<label>|<compiler command>|<how its output runs: native, qemu, cxvm or wine>"
FORKS="x86|$CC|native
cx|$T/cx|cxvm"
if [ "$HAVE_QEMU" = 1 ]; then
    mk a64  src/main_aarch64.cyr        "$T/a64x"
    mk a64n src/main_aarch64_native.cyr "$T/a64x"
    FORKS="$FORKS
a64_cross|$T/a64x|qemu
aarch64_qemu|qemu-aarch64 $T/a64|qemu
native_qemu|qemu-aarch64 $T/a64n|qemu"
else
    echo "  SKIP (named): the a64_cross, aarch64_qemu and native_qemu rows — qemu-aarch64 is not installed"
    skips=$((skips + 1))
fi
if [ "$HAVE_WINE" = 1 ]; then
    export WINEPREFIX="$WP" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    mk cycc.exe src/main_win.cyr "$T/xwin"
    mk cx.exe   src/main_cx.cyr  "$CC" CYRIUS_TARGET_WIN=1
    FORKS="$FORKS
win_host|$T/xwin|wine
cycc.exe_wine|$W $T/cycc.exe|wine
cx.exe_wine|$W $T/cx.exe|cxvm"
else
    echo "  SKIP (named): the win_host, cycc.exe_wine and cx.exe_wine rows — wine is not installed"
    skips=$((skips + 1))
fi

# run_out <kind> -> the exit code of $T/o run on its target
run_out() {
    r=0
    case $1 in
        native) timeout 60 "$T/o" < /dev/null > /dev/null 2>&1 || r=$? ;;
        qemu)   timeout 60 qemu-aarch64 "$T/o" < /dev/null > /dev/null 2>&1 || r=$? ;;
        cxvm)   timeout 60 "$T/cxvm" < "$T/o" > /dev/null 2>&1 || r=$? ;;
        wine)   cp "$T/o" "$T/o.exe" && { timeout 120 $W "$T/o.exe" < /dev/null > /dev/null 2>&1 || r=$?; } ;;
    esac
    echo "$r"
}
printf '%s\n' "$FORKS" > "$T/forks"
while IFS='|' read -r l c k; do
    for v in 1 0 empty no unset; do
        rc=0
        case $v in
            unset) env -u CYRIUS_POISON timeout 300 $c < "$REPRO" > "$T/o" 2> "$T/o.err" || rc=$? ;;
            empty) env CYRIUS_POISON= timeout 300 $c < "$REPRO" > "$T/o" 2> "$T/o.err" || rc=$? ;;
            *)     env CYRIUS_POISON="$v" timeout 300 $c < "$REPRO" > "$T/o" 2> "$T/o.err" || rc=$? ;;
        esac
        sz=$(wc -c < "$T/o" | tr -d ' ')
        case $v in
            1)  want="compile 0, run 7" ;;
            no) want="compile 1, 0 bytes, refused by name" ;;
            *)  want="compile 0, run 0" ;;
        esac
        if [ "$v" = no ]; then
            named=no; grep -qx 'error: CYRIUS_POISON must be 0 or 1 (or unset): no' "$T/o.err" && named="refused by name"
            [ "$rc" -ge 124 ] && named="timeout or signal (rc $rc)"
            got="compile $rc, $sz bytes, $named"
        elif [ "$rc" != 0 ] || [ "$sz" = 0 ]; then
            got="compile $rc, $sz bytes: $(grep -m1 -i error "$T/o.err" | tr -d '\r')"
        else
            chmod +x "$T/o"; got="compile 0, run $(run_out "$k")"
        fi
        check "R $l CYRIUS_POISON=[$v]" "$want" "$got"
    done
done < "$T/forks"

echo "== F: cyrius fuzz --poison (the CLI injects =1 first) =="
mkdir -p "$T/bin" "$T/fz"
if ! "$CC" < cbt/cyrius.cyr > "$T/bin/cyrius" 2> "$T/cli.err" || [ "$(wc -c < "$T/bin/cyrius" | tr -d ' ')" -lt 100000 ]; then
    echo "FAIL: $G — cbt/cyrius.cyr does not build: $(grep -m1 -i error "$T/cli.err")"; exit 1
fi
chmod +x "$T/bin/cyrius"
cp "$CC" "$T/bin/cycc"   # the wrapper prefers the cycc beside it (cbt/core.cyr find_tools)
printf '#ifdef CYRIUS_POISON\nsyscall(60, 0);\n#endif\nsyscall(60, 3);\n' > "$T/fz/p.fcyr"
fz() {   # $1 the inherited value (unset / 0 / no), $2.. fuzz arguments -> rc and $T/fz.out
    v=$1; shift
    frc=0
    if [ "$v" = unset ]; then
        (cd "$T/fz" && env -u CYRIUS_POISON CYRIUS_RESOLVED=1 CYRIUS_HOME="$T/nohome" timeout 120 "$T/bin/cyrius" fuzz "$@") > "$T/fz.out" 2>&1 || frc=$?
    else
        (cd "$T/fz" && env CYRIUS_POISON="$v" CYRIUS_RESOLVED=1 CYRIUS_HOME="$T/nohome" timeout 120 "$T/bin/cyrius" fuzz "$@") > "$T/fz.out" 2>&1 || frc=$?
    fi
    echo "$frc"
}
check "F1 --poison, the variable unset: the harness passes" 0 "$(fz unset --poison p.fcyr)"
check "F2 --poison over an inherited 0: passes (=1 is read first)" 0 "$(fz 0 --poison p.fcyr)"
check "F3 --poison over an inherited no: passes" 0 "$(fz no --poison p.fcyr)"
check "F4 no --poison, unset: the harness fails (anti-vacuous)" 1 "$(fz unset p.fcyr)"
check "F5 no --poison, an inherited 0: off, the harness fails" 1 "$(fz 0 p.fcyr)"
r6=$(fz no p.fcyr)
grep -q 'COMPILE FAIL' "$T/fz.out" && grep -q 'CYRIUS_POISON must be 0 or 1 (or unset): no' "$T/fz.out" && r6="$r6 refused"
check "F6 no --poison, an inherited no: a compile refused by name" "1 refused" "$r6"

echo ""
if [ "$fails" -gt 0 ]; then
    echo "FAIL: $G — $fails of $checks checks failed"
    exit 1
fi
if [ "$skips" -gt 0 ]; then
    echo "SKIP: $G — $skips leg(s) could not run here (named above); all $checks checks that ran passed (exit 77: a SKIP, not a PASS)"
    exit 77
fi
echo "PASS: $G — $checks checks"
exit 0
