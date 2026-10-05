#!/bin/sh
# 6.6.12 — kernel32!GetLastError is routed on PE (0xF04B), and lib/fs_win.cyr reads it to tell
# the END of a directory listing from a FAILURE part-way.
#
# ⛔ WHY: FindNextFileW returns 0 both at the end of a directory and when enumeration fails, and
# only GetLastError tells them apart (ERROR_NO_MORE_FILES = 18 is the end). There was no reroute
# for it — only ws2_32's WSAGetLastError (0xF024) — so `_dir_list_into_vec` treated every 0 as
# the end: a listing that failed half-way came back as a complete, shorter directory, which every
# walker (dir_walk, find_files, `cyrius test`) then trusted. The value must be read BEFORE
# FindClose, which can overwrite it. The same release gave `dir_list_into` its Windows arm (it
# answered -1 for every directory on PE), which reads it the same way.
#
# THE AXES
#   axis 1  `syscall(0xF04B)` (argc 1) builds with CYRIUS_TARGET_WIN=1 and is not reported as
#           unrouted; with one argument it IS reported — the route is literal-and-arity.
#   axis 2  the routed-number note names `0xF04B (kernel32: GetLastError)` and is printed WHOLE:
#           the note is one literal written with a hand-counted byte length, and a length left at
#           its old value silently cuts the newest entries off the end.
#   axis 3  the axis-1 build IMPORTS GetLastError (objdump -p; that axis alone is skipped
#           without an objdump that reads PE).
#   axis 4  STATIC, lib/fs_win.cyr: every FindNextFileW loop (`syscall(61463, ...)`) ends in
#           `syscall(61515)` (GetLastError) whose next code line is FindClose (`syscall(61464,`)
#           and whose next is the `!= 18` check; and no lib/ module hands 0xF016 / 0xF019 a
#           stdlib-widened `&w...` buffer — they take the narrow UTF-8 path since 6.6.12.
#   axis 5  BEHAVIOUR under wine (skipped without wine — NOT hardware; the cass cross-OS leg of
#           the release gate runs the same .tcyr): tests/tcyr/crossos/fs_dirlist.tcyr's PE build
#           reports 0 failed — dir_list_checked of a listable directory is 0, dir_list_into lists
#           it, and GetLastError after a missing name / a missing parent is 2 / 3.
#
# MUTATION LEDGER — every mutant BUILT AND RUN 2026-09-30 (lane P, bite B08; x86_64 Linux +
# wine 11.17; CYCC=<mutant cycc> for the compiler rows):
#   mutant                                                       result
#   the 0xF04B row removed from _PE_ROUTE_SOCK                   axes 1, 3 and 5 FAIL (5 wine rows)
#   the note's byte count left at 1550                           axis 2 FAIL (the note ends at 0xF04A)
#   GetLastError read AFTER FindClose (_dir_list_into_vec)       axis 4 FAIL
#   the `err != 18` check removed (_dir_list_into_win)           axis 4 FAIL
#   _dir_list_into_vec's check reads `err != 17`                 axes 4 and 5 FAIL (1 wine row)
# ⚠ No row can force FindNextFileW to FAIL part-way (not under wine, not on cass): axis 4 is what
# pins the error branch, axis 5 that the value it tests is the real one (a listing that ENDS is 18).
# Exit 77 = could not run (the SKIP protocol). CHANGELOG [6.6.12]
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: pe_last_error_reroute: build/cycc missing"; exit 77; }
FSW="$ROOT/lib/fs_win.cyr"
TC="$ROOT/tests/tcyr/crossos/fs_dirlist.tcyr"
[ -f "$FSW" ] || { echo "FAIL: pe_last_error_reroute: $FSW is missing"; exit 1; }
[ -f "$TC" ] || { echo "FAIL: pe_last_error_reroute: $TC is missing"; exit 1; }

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: pe_last_error_reroute: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix, and wine's own HOME / XDG_CACHE_HOME, under $D — never the user's
# ~/.wine or ~/.cache (a fresh prefix writes $HOME/.cache: mesa shader caches). The EXIT
# teardown stops THIS prefix's wineserver and removes its server dir
# (/tmp/.wine-<uid>/server-<dev>-<ino>), which `wineserver -k` leaves behind. CHANGELOG [6.6.17]
WP="$D/wp"
WHM="$D/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT INT TERM

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail + 1)); }

build() {  # $1 = file stem, $2 = the syscall's argument list
    printf 'fn main(): i64 {\n    var j = syscall(%s);\n    return j & 0;\n}\nvar r = main();\nsyscall(60, r);\n' "$2" > "$D/$1.cyr"
    CYRIUS_TARGET_WIN=1 "$CC" < "$D/$1.cyr" > "$D/$1.exe" 2> "$D/$1.err"
}

# axis 1: routed at argc 1, reported at argc 2.
build g "0xF04B"
rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$D/g.exe" ]; then bad "axis 1: syscall(0xF04B) did not build for PE (rc $rc)"
elif grep -q "syscall 61515 with" "$D/g.err"; then bad "axis 1: syscall(0xF04B) is reported as not routed"
else ok; fi
build s "0xF04B, 0"
if grep -q "syscall 61515 with 1 argument" "$D/s.err"; then ok
else bad "axis 1: syscall(0xF04B, 0) (one argument too many) was not reported"; fi

# axis 2: the note names 0xF04B and reaches its own end.
if grep -q '^  note: CYRIUS_TARGET_WIN=1 routes' "$D/s.err"; then
    note=$(grep '^  note: CYRIUS_TARGET_WIN=1 routes' "$D/s.err")
    case "$note" in
        *'+ 0xF04B (kernel32: GetLastError).') ok ;;
        *'0xF04B (kernel32: GetLastError)'*) bad "axis 2: the note names 0xF04B but does not END with it — its byte count is wrong" ;;
        *) bad "axis 2: the routed-number note does not name 0xF04B (kernel32: GetLastError) — or it is cut short: ...$(printf '%s' "$note" | tail -c 60)" ;;
    esac
else
    bad "axis 2: the unrouted probe printed no routed-number note"
fi

# axis 3: the import.
if [ -s "$D/g.exe" ] && objdump -p "$D/g.exe" > "$D/imp.txt" 2>/dev/null && grep -q 'DLL Name' "$D/imp.txt"; then
    if grep -qE '[[:space:]]GetLastError$' "$D/imp.txt"; then ok
    else bad "axis 3: the syscall(0xF04B) build does not import kernel32!GetLastError"; fi
else
    echo "  SKIP: axis 3 (no objdump that reads PE)"
fi

# axis 4: static, over the tree's lib/.
code() { grep -vE '^[[:space:]]*#' "$1"; }
nnext=$(code "$FSW" | grep -c 'syscall(61463,')
nread=$(code "$FSW" | awk '
    /syscall\(61515\)/ { s = 1; next }
    s == 1 && NF { if ($0 ~ /syscall\(61464,/) s = 2; else s = 0; next }
    s == 2 && NF { if ($0 ~ /!= 18/) n++; s = 0; next }
    END { print n + 0 }')
if [ "$nnext" -lt 2 ]; then
    bad "axis 4 (anti-vacuous): only $nnext FindNextFileW loop(s) in lib/fs_win.cyr (floor 2: _dir_list_into_vec, _dir_list_into_win)"
elif [ "$nread" != "$nnext" ]; then
    bad "axis 4: $nnext FindNextFileW loop(s) but $nread read GetLastError, then FindClose, then test for ERROR_NO_MORE_FILES (18) — a failed listing ends like a complete one"
else ok; fi
wide=$(for f in "$ROOT"/lib/*.cyr; do code "$f" | grep -nE 'syscall\((61465|61462), *&w' | sed "s|^|${f#$ROOT/}:|"; done)
if [ -n "$wide" ]; then
    bad "axis 4: 0xF016/0xF019 handed a stdlib-widened buffer (they take the narrow UTF-8 path since 6.6.12): $(printf '%s' "$wide" | head -3 | tr '\n' ' ')"
else ok; fi

# axis 5: behaviour under wine.
if ! command -v wine > /dev/null 2>&1; then
    echo "  SKIP: axis 5 (wine absent — the cass cross-OS leg runs fs_dirlist.tcyr on real Windows)"
else
    ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$D/t.exe" 2> "$D/t.err" )
    if [ ! -s "$D/t.exe" ]; then
        bad "axis 5: the PE build of fs_dirlist.tcyr produced no binary: $(grep -m2 '^error' "$D/t.err" | tr '\n' ' ')"
    else
        mkdir -p "$D/w" && cp "$D/t.exe" "$D/w/t.exe"
        ( cd "$D/w" && ulimit -c 0; LANG=C.UTF-8 WINEPREFIX="$D/wp" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            wine t.exe > "$D/t.out" 2>&1 ); wrc=$?
        sum=$(sed -n 's/^\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1 \2/p' "$D/t.out" | tail -1)
        np=${sum% *}; nf=${sum#* }
        if [ -z "$sum" ]; then
            bad "axis 5: the PE run under wine printed no summary (exit $wrc)"
        elif [ "$wrc" != 0 ] || [ "$nf" != 0 ]; then
            bad "axis 5: fs_dirlist.tcyr under wine: $np passed, $nf failed (exit $wrc)"
            grep -m6 'FAIL:' "$D/t.out" | sed 's/^/      /'
        elif [ "$np" -lt 30 ]; then
            bad "axis 5: fs_dirlist.tcyr under wine ran only $np rows (floor 30)"
        else ok; fi
        WINEPREFIX="$D/wp" wineserver -k > /dev/null 2>&1 || true
    fi
fi

echo "$pass passed, $fail failed"
[ "$pass" -ge 5 ] || { echo "FAIL: pe_last_error_reroute: only $pass rows ran (floor 5)"; exit 1; }
if [ "$fail" -ne 0 ]; then echo "FAIL: pe_last_error_reroute"; exit 1; fi
echo "PASS: pe_last_error_reroute — 0xF04B routed at its arity, named, imported; every FindNextFileW loop reads GetLastError before FindClose"
