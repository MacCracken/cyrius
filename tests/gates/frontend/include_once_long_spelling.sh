#!/bin/sh
# tests/gates/frontend/include_once_long_spelling.sh — 6.7.15 (the infratools lane, I2)
#
# INCLUDE-ONCE KEYS ON THE WHOLE SPELLING, at any length. The include-once table (S + 0x1C0000) held 256 entries of
# 128 B: PP_MARK_INCLUDED kept the first 127 bytes of a spelling and PP_ALREADY_INCLUDED compared the whole one, so a
# spelling of 128+ bytes never matched its own entry and a second `include` of it was not skipped — its top-level
# statements ran twice, its fns were defined twice (the later binds), no message. Since v4.8.4-alpha2. The table now
# holds a pointer per entry to the whole spelling, alloc'd (issues/2026-10-16-include-once-path-of-128-chars-included-twice.md).
#
#   F1  the filing's repro verbatim: a 128-character file name included twice around z.cyr -> 41 (was 42)
#   F2  the filing's 127-character control -> 41 (unchanged)
#   F3  a 308-character spelling through directories -> 41
#   F4  a 766-character spelling (the longest the filename capture takes, PP_FNAME_TOO_LONG past it) -> 41
#   D   two DISTINCT spellings sharing their first 250 characters, each included twice -> both once (40 + 1 + 1):
#       comparing only a stored prefix would merge them
#   N1  256 distinct includes compile, and a re-include at 256 (of a 128+ character spelling) is still skipped (42)
#   N2  the 257th distinct include is still refused, with the same message, rc 1
# Every row on five legs: x86 (the compiler under test), aarch64 (cycc_aarch64, run under qemu-aarch64), cx (cycc_cx,
# run under cxvm), PE (CYRIUS_TARGET_WIN=1, run under wine) and PE through cycc_win (src/main_win.cyr), the cross
# compilers built from this tree by the compiler under test. The Mach-O compilers (and every host's own) meet the
# shape on hardware in tests/tcyr/crossos/include_once_long_spelling.tcyr.
#
# MUTATION LEDGER (2026-10-18; each a one-edit copy of src/frontend/lex_pp.cyr, its compiler built 2-stage by the
# fixed one, this gate run with CYCC= it, so the cross legs are built from the mutated src too):
#   the 6.7.14 PP_MARK_INCLUDED / PP_ALREADY_INCLUDED (128 B entries)  -> RED F1 F3 F4 D N1 on every leg, 25 rows (F 42,
#                                                                         D 44, N1 refused: its re-include counted
#                                                                         as a 257th); F2 N2 green
#   PP_ALREADY_INCLUDED comparing at most 127 bytes                   -> RED D on every leg, 5 rows (41: the second
#                                                                         spelling merged into the first)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=include_once_long_spelling
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
case "$CC" in /*) ;; *) CC="$(pwd)/$CC" ;; esac
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
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
cd "$ROOT" || { echo "FAIL: $G: cannot cd to $ROOT"; exit 1; }
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
HAVE_WINE=0
if command -v wine > /dev/null 2>&1; then HAVE_WINE=1
else echo "  SKIP the PE legs' runs — wine not installed"; fi
HAVE_QEMU=0
if command -v qemu-aarch64 > /dev/null 2>&1; then HAVE_QEMU=1
else echo "  SKIP the aarch64 leg's runs — qemu-aarch64 not installed"; fi

# The cross compilers, built once from this tree by the compiler under test.
"$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/cc_a64.err" && [ -s "$T/cc_a64" ] && chmod +x "$T/cc_a64" || rm -f "$T/cc_a64"
"$CC" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/cc_cx.err" && [ -s "$T/cc_cx" ] \
    && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ] && chmod +x "$T/cc_cx" "$T/cxvm" \
    || rm -f "$T/cc_cx" "$T/cxvm"
"$CC" < src/main_win.cyr > "$T/cc_win" 2> "$T/cc_win.err" && [ -s "$T/cc_win" ] && chmod +x "$T/cc_win" || rm -f "$T/cc_win"

# The programs live in $W and are compiled there, so their includes resolve against it.
W="$T/w"
mkdir -p "$W"
LEGS="x86 a64 cx pe pew"
# leg_cc <leg> <src> <out> <err> (names in $W): compile with that leg's compiler; sets rc (127: no compiler)
leg_cc() {
    rc=0
    case "$1" in
        x86) (cd "$W" && timeout 60 "$CC" < "$2" > "$3" 2> "$4") || rc=$? ;;
        pe)  (cd "$W" && CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$2" > "$3" 2> "$4") || rc=$? ;;
        a64) if [ -x "$T/cc_a64" ]; then (cd "$W" && timeout 60 "$T/cc_a64" < "$2" > "$3" 2> "$4") || rc=$?; else rc=127; fi ;;
        cx)  if [ -x "$T/cc_cx" ]; then (cd "$W" && timeout 60 "$T/cc_cx" < "$2" > "$3" 2> "$4") || rc=$?; else rc=127; fi ;;
        pew) if [ -x "$T/cc_win" ]; then (cd "$W" && timeout 60 "$T/cc_win" < "$2" > "$3" 2> "$4") || rc=$?; else rc=127; fi ;;
    esac
}
# leg_run <leg> <bin> (a path): run a built program; sets got (77: no runner)
leg_run() {
    got=0
    case "$1" in
        x86) chmod +x "$2"; timeout 10 "$2" > /dev/null 2>&1 || got=$? ;;
        a64) if [ "$HAVE_QEMU" -eq 1 ]; then chmod +x "$2"; timeout 10 qemu-aarch64 "$2" > /dev/null 2>&1 || got=$?; else got=77; fi ;;
        cx)  timeout 10 "$T/cxvm" < "$2" > /dev/null 2>&1 || got=$? ;;
        pe|pew)
            if [ "$HAVE_WINE" -eq 1 ]; then
                cp "$2" "$T/run.exe"
                (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                    WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 60 wine ./run.exe > /dev/null 2>&1) || got=$?
            else got=77; fi ;;
    esac
}
# runs <row> <what> <file in $W> <want exit>: on every leg it compiles (rc 0) and the program exits <want>
runs() {
    for L in $LEGS; do
        leg_cc "$L" "$3" "$3.$L.bin" "$3.$L.err"
        if [ "$rc" -eq 127 ]; then bad "$1 [$L]: $2: the leg's compiler did not build"; continue; fi
        if [ "$rc" -ne 0 ] || [ ! -s "$W/$3.$L.bin" ]; then bad "$1 [$L]: $2: refused (rc $rc): $(head -1 "$W/$3.$L.err")"; continue; fi
        leg_run "$L" "$W/$3.$L.bin"
        if [ "$got" -eq 77 ]; then echo "  SKIP $1 [$L]: $2: built, no runner"
        elif [ "$got" -eq "$4" ]; then ok "$1 [$L]: $2 -> $got"
        else bad "$1 [$L]: $2: exit $got, want $4"; fi
        rm -f "$W/$3.$L.bin"
    done
}
# rp <char> <n>: the character n times
rp() { awk -v c="$1" -v n="$2" 'BEGIN { for (i = 0; i < n; i++) printf "%s", c }'; }
# twice <file in $W> <spelling>: var r = 40; the spelling, z.cyr, the spelling again; exit r
twice() { printf 'var r = 40;\ninclude "%s"\ninclude "z.cyr"\ninclude "%s"\nsyscall(60, r);\n' "$2" "$2" > "$W/$1"; }
printf '# z\n' > "$W/z.cyr"

# F1 / F2 — the filing's repro, verbatim names (124 / 123 q's + .cyr)
q128=$(rp q 124).cyr; q127=$(rp q 123).cyr
printf 'r = r + 1;\n' > "$W/$q128"; printf 'r = r + 1;\n' > "$W/$q127"
twice f1.cyr "$q128"; twice f2.cyr "$q127"
runs F1 'the filed 128-character name, included twice' f1.cyr 41
runs F2 'the filed 127-character name, included twice' f2.cyr 41
# F3 — 308 characters through directories (the cybs filing's path)
d=$(rp d 100); p308="$d/$d/$d/l.cyr"; mkdir -p "$W/$d/$d/$d"; printf 'r = r + 1;\n' > "$W/$p308"
twice f3.cyr "$p308"
runs F3 'a 308-character spelling through directories, included twice' f3.cyr 41
# F4 — 766 characters: seven 100-character directories and a 59-character name
p766="$d/$d/$d/$d/$d/$d/$d/$(rp m 55).cyr"; mkdir -p "$W/$d/$d/$d/$d/$d/$d/$d"; printf 'r = r + 1;\n' > "$W/$p766"
[ ${#p766} -eq 766 ] || bad "F4: the probe spelling is ${#p766} characters, want 766"
twice f4.cyr "$p766"
runs F4 'a 766-character spelling (the capture'"'"'s longest), included twice' f4.cyr 41
# D — two distinct spellings, the same first 250 characters
pa="$d/$d/$(rp k 48)a.cyr"; pb="$d/$d/$(rp k 48)b.cyr"
printf 'r = r + 1;\n' > "$W/$pa"; printf 'r = r + 1;\n' > "$W/$pb"
printf 'var r = 40;\ninclude "%s"\ninclude "%s"\ninclude "%s"\ninclude "%s"\nsyscall(60, r);\n' "$pa" "$pb" "$pa" "$pb" > "$W/dd.cyr"
runs D 'two distinct spellings sharing 250 characters, each included twice' dd.cyr 42
# N1 / N2 — the count: 255 files, then the 256th (the 128-character name), its re-include, then a 257th
i=1; while [ $i -le 255 ]; do printf '# f%s\n' $i > "$W/f$i.cyr"; i=$((i + 1)); done
{ printf 'var r = 40;\n'; i=1; while [ $i -le 255 ]; do printf 'include "f%s.cyr"\n' $i; i=$((i + 1)); done
  printf 'include "%s"\ninclude "%s"\ninclude "f1.cyr"\nsyscall(60, r + 1);\n' "$q128" "$q128"; } > "$W/n256.cyr"
runs N1 '256 distinct includes, then re-includes of the 256th (128 characters) and the 1st' n256.cyr 42
{ printf 'var r = 40;\n'; i=1; while [ $i -le 255 ]; do printf 'include "f%s.cyr"\n' $i; i=$((i + 1)); done
  printf 'include "%s"\ninclude "z.cyr"\nsyscall(60, r);\n' "$q128"; } > "$W/n257.cyr"
FULL='error: include-once table full (256 files) — split compilation unit'
for L in $LEGS; do
    leg_cc "$L" n257.cyr n257.$L.bin n257.$L.err
    if [ "$rc" -eq 127 ]; then bad "N2 [$L]: the leg's compiler did not build"
    elif [ "$rc" -ne 1 ]; then bad "N2 [$L]: the 257th distinct include: rc $rc, want 1"
    elif grep -qxF "$FULL" "$W/n257.$L.err"; then ok "N2 [$L]: the 257th distinct include refused: $FULL"
    else bad "N2 [$L]: the 257th distinct include: printed [$(head -1 "$W/n257.$L.err")], want [$FULL]"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
echo "PASS: $G — include-once keys on the whole spelling (128, 308 and 766 characters included once on x86, aarch64, cx, PE and cycc_win; two spellings sharing 250 characters stay distinct; 256 distinct includes compile, the 257th is refused with the same message)"
