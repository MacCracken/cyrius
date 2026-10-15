#!/bin/sh
# 6.7.12 — cbt's `[embed]` / `${file:}` open refuses a file reached through a directory link on
# Windows and on macOS arm64 too, not only where the open walks the path from a root dirfd.
#
# ⛔ WHY: `_proj_path_bad` checks every prefix of the path for a link, then `_embed_open` opens it
# — a check-then-open race. Linux and x86 macOS close it by WALKING the path with
# openat(dirfd, component, O_DIRECTORY | O_NOFOLLOW), so a directory swapped for a link in between
# fails the open. Windows opened the whole path (no dirfd openat; O_NOFOLLOW guards the LAST
# component only), and macOS arm64 skipped the walk (its SYS_OPENAT 56 reached BSD open(5) with
# the dirfd shifted out), so on both a junction / directory link planted after the check was
# followed, and the build embedded out-of-project bytes. Now:
#   · Windows: kernel32!GetFinalPathNameByHandleW is routed (0xF04E), and `_embed_open_win` refuses
#     -ELOOP a handle whose final path is not inside the project root's (lib/fs_win.cyr
#     win_handle_under: a case-blind prefix that ends at a separator).
#   · macOS arm64: 56 reaches Darwin openat 463 with the dirfd KEPT (`_esx_arm_atfd`; Linux's
#     AT_FDCWD -100 becomes Darwin's -2), and `_embed_open` walks there like everywhere else.
#
# THE AXES
#   axis 1  `syscall(0xF04E, h, buf, cch, flags)` (argc 5) builds with CYRIUS_TARGET_WIN=1 and is
#           not reported as unrouted; one argument short, it IS reported (literal-and-arity).
#   axis 2  the routed-number note names `0xF04E (kernel32: GetFinalPathNameByHandleW)` and ENDS
#           with it: the note is one literal with a hand-counted byte length, and a length left at
#           its old value silently cuts the newest entries off the end. (This gate pins the END;
#           pe_lockfileex_reroute.sh now checks 0xF04C-0xF04D is present and followed.)
#   axis 3  the axis-1 build IMPORTS GetFinalPathNameByHandleW (objdump -p; skipped by name
#           without an objdump that reads PE).
#   axis 4  STATIC: `_embed_open`'s CYRIUS_TARGET_WIN arm calls `_embed_open_win`, which asks
#           `win_handle_under(fd, rh)` and returns `0 - 40` unless it is 1; `win_handle_under` /
#           `_fs_handle_under_path` ask 0xF04E at argc 5 for both handles and test the separator
#           (92) after the prefix; `_embed_open` has no `walk = 0` (the arm64-macOS skip) left.
#   axis 5  the arm64-macOS route, on the BINARY (the ecb leg of the release gate runs it): the
#           crossos test cross-built with CYRIUS_MACHO_ARM=1 carries the folded openat body
#           `cmn x0,#100; b.ne +8; movn x0,#1; movz x16,#463` and NO `open(5)` arg-shift body
#           (`mov x0,x1; mov x1,x2; mov x2,x3; movz x16,#5`).
#   axis 6  BEHAVIOUR: tests/tcyr/crossos/embed_open_under_root.tcyr natively (Linux: the walk is
#           the oracle), under qemu-aarch64 (skipped by name without it), and as PE under wine
#           (skipped by name without it — NOT hardware: the cass and ecb legs of the release gate
#           run the same .tcyr, the VERDICT for the two targets this fixes). Each run in a scratch
#           cwd (the test's fixtures go in its cwd; a gate never writes the tree), 0 failed over a
#           row floor.
#
# MUTATION LEDGER — every mutant BUILT AND RUN 2026-10-15 (6.7.12 windows lane, W2; x86_64 Linux
# + wine; CYCC=<mutant cycc> for the compiler rows, a scratch tree for the lib / cbt rows):
#   mutant                                                       result
#   the 0xF04E row removed from _PE_ROUTE_FILELOCK               axes 1, 3 and 6 FAIL (wine: 9 rows —
#                                                                the unrouted -38 makes every
#                                                                containment answer -1, so even the
#                                                                plain in-project path is refused)
#   the note's byte count left at 1639                           axis 2 FAIL (the note ends at 0xF04D)
#   `_embed_open`'s PE arm back to `file_open(path, fl, 0)`      axes 4 and 6 FAIL (wine: 3 rows —
#                                                                the link is followed and the
#                                                                outside file read; cass: the same
#                                                                3, and a real junction followed)
#   the separator test dropped (`return 1` after the prefix)     axes 4 and 6 FAIL (wine: 1 row,
#                                                                <root>/inx under <root>/in)
#   the arm64 Mach-O 56 row back to `_esx_arm_shift(S, 56, 5, 3)` axis 5 FAIL. On ecb the slot-open
#                                                                tree's build of the .tcyr fails 5
#                                                                rows (the link followed, the
#                                                                dirfd dropped); 30 / 30 after
#   `walk = 0` back in _embed_open (the arm64-macOS skip)        axis 4 FAIL
# Exit 77 = could not run (the SKIP protocol). CHANGELOG [6.7.12]
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: embed_link_race_pe: build/cycc missing"; exit 77; }
MF="$ROOT/cbt/manifest.cyr"
FW="$ROOT/lib/fs_win.cyr"
TC="$ROOT/tests/tcyr/crossos/embed_open_under_root.tcyr"
for f in "$MF" "$FW" "$TC"; do
    [ -f "$f" ] || { echo "FAIL: embed_link_race_pe: $f is missing"; exit 1; }
done

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: embed_link_race_pe: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix, and wine's own HOME / XDG_CACHE_HOME, under $D — never the user's
# ~/.wine or ~/.cache. The EXIT teardown stops THIS prefix's wineserver and removes its server
# dir, which `wineserver -k` leaves behind (the pe_last_error_reroute.sh shape). CHANGELOG [6.6.17]
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
    printf 'fn main(): i64 {\n    var b[64];\n    var j = syscall(%s);\n    return j & 0;\n}\nvar r = main();\nsyscall(60, r);\n' "$2" > "$D/$1.cyr"
    CYRIUS_TARGET_WIN=1 "$CC" < "$D/$1.cyr" > "$D/$1.exe" 2> "$D/$1.err"
}

# axis 1: routed at argc 5, reported one argument short.
rc=0; build fp "0xF04E, 0, &b, 32, 0" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$D/fp.exe" ]; then bad "axis 1: syscall(0xF04E, 4 args) did not build for PE (rc $rc)"
elif grep -q "syscall 61518 with" "$D/fp.err"; then bad "axis 1: syscall(0xF04E, 4 args) is reported as not routed"
else ok; fi
build fps "0xF04E, 0, &b, 32"
if grep -q "syscall 61518 with 3 argument" "$D/fps.err"; then ok
else bad "axis 1: syscall(0xF04E, 3 args) (one argument short) was not reported"; fi

# axis 2: the note names 0xF04E and ENDS with it.
if grep -q '^  note: CYRIUS_TARGET_WIN=1 routes' "$D/fps.err"; then
    note=$(grep '^  note: CYRIUS_TARGET_WIN=1 routes' "$D/fps.err" || true)
    case "$note" in
        *'+ 0xF04E (kernel32: GetFinalPathNameByHandleW).') ok ;;
        *'0xF04E (kernel32: GetFinalPathNameByHandleW)'*) bad "axis 2: the note names 0xF04E but does not END with it — its byte count is wrong" ;;
        *) bad "axis 2: the routed-number note does not name 0xF04E (kernel32: GetFinalPathNameByHandleW) — or it is cut short: ...$(printf '%s' "$note" | tail -c 60)" ;;
    esac
else
    bad "axis 2: the short-arity probe printed no routed-number note"
fi

# axis 3: the import.
if [ -s "$D/fp.exe" ] && objdump -p "$D/fp.exe" > "$D/imp.txt" 2>/dev/null && grep -q 'DLL Name' "$D/imp.txt"; then
    if grep -qE '[[:space:]]GetFinalPathNameByHandleW$' "$D/imp.txt"; then ok
    else bad "axis 3: the syscall(0xF04E) build does not import kernel32!GetFinalPathNameByHandleW"; fi
else
    echo "  SKIP: axis 3 (no objdump that reads PE)"
fi

# axis 4: static, over the tree's cbt/manifest.cyr and lib/fs_win.cyr.
code() { grep -vE '^[[:space:]]*#' "$1"; }
fnbody() { code "$1" | awk -v f="$2" 'index($0, "fn " f "(") == 1 { s = 1 } s == 1 { print } s == 1 && /^}/ { exit }'; }
f4=$fail
eo=$(fnbody "$MF" _embed_open)
warm=$(grep -A2 '^    #ifdef CYRIUS_TARGET_WIN' <<EOF
$(awk 'index($0, "fn _embed_open(") == 1 { s = 1 } s == 1 { print } s == 1 && /^}/ { exit }' "$MF")
EOF
)
[ -n "$eo" ] || bad "axis 4: cbt/manifest.cyr has no _embed_open"
case "$warm" in
    *'return _embed_open_win(path, fl);'*) ;;
    *) bad "axis 4: _embed_open's CYRIUS_TARGET_WIN arm does not return _embed_open_win(path, fl) (it reads: $(printf '%s' "$warm" | tr -s ' \n' ' '))" ;;
esac
printf '%s\n' "$eo" | grep -q 'walk = 0' && bad "axis 4: _embed_open still skips the walk somewhere (walk = 0 — the arm64-macOS whole-path open)"
eow=$(fnbody "$MF" _embed_open_win)
if [ -z "$eow" ]; then
    bad "axis 4: cbt/manifest.cyr has no _embed_open_win"
else
    printf '%s\n' "$eow" | grep -q 'var under = win_handle_under(fd, rh);' \
        || bad "axis 4: _embed_open_win does not ask win_handle_under(fd, rh)"
    printf '%s\n' "$eow" | grep -q 'if (under != 1)' \
        || bad "axis 4: _embed_open_win does not refuse every answer but 1 (a -1 'cannot tell' must refuse too)"
    printf '%s\n' "$eow" | grep -q 'return 0 - 40;' \
        || bad "axis 4: _embed_open_win does not refuse with -ELOOP (0 - 40)"
fi
whu=$(fnbody "$FW" win_handle_under)
fhp=$(fnbody "$FW" _fs_handle_under_path)
if [ -z "$whu" ] || [ -z "$fhp" ]; then
    bad "axis 4: lib/fs_win.cyr lacks win_handle_under or _fs_handle_under_path"
else
    printf '%s\n' "$whu" | grep -q 'syscall(0xF04E, root_h, &a, 32768, 0)' \
        || bad "axis 4: win_handle_under does not ask GetFinalPathNameByHandleW (0xF04E, argc 5) for the root"
    printf '%s\n' "$fhp" | grep -q 'syscall(0xF04E, h, &b, 32768, 0)' \
        || bad "axis 4: _fs_handle_under_path does not ask GetFinalPathNameByHandleW (0xF04E, argc 5) for the file"
    printf '%s\n' "$fhp" | grep -q 'if (load16(&b + na \* 2) == 92) { return 1; }' \
        || bad "axis 4: _fs_handle_under_path does not require a separator after the root's prefix (C:\\proj would hold C:\\project)"
    printf '%s\n' "$whu$fhp" | grep -q 'return 1; }' || bad "axis 4: win_handle_under never answers 1"
fi
[ "$fail" = "$f4" ] && ok

# axis 5: the arm64-macOS openat route, on the binary.
( cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> "$D/cc_a64.err" )   # includes resolve from the root
if [ ! -s "$D/cc_a64" ]; then
    bad "axis 5: the aarch64 cross compiler did not build from this tree: $(head -2 "$D/cc_a64.err" | tr '\n' ' ')"
else
    chmod +x "$D/cc_a64"
    ( cd "$ROOT" && CYRIUS_MACHO_ARM=1 "$D/cc_a64" < "$TC" > "$D/eo_ma" 2> "$D/eo_ma.err" )
    if [ ! -s "$D/eo_ma" ]; then
        bad "axis 5: the arm64-macOS build of embed_open_under_root.tcyr produced no binary: $(grep -m2 '^error' "$D/eo_ma.err" | tr '\n' ' ')"
    else
        od -An -v -tx4 -w4 "$D/eo_ma" | tr -d ' ' > "$D/eo_ma.w"
        natfd=$(awk 'w3 == "b101901f" && w2 == "54000041" && w1 == "92800020" && $0 == "d28039f0" { n++ } { w3 = w2; w2 = w1; w1 = $0 } END { print n + 0 }' "$D/eo_ma.w")
        nshift=$(awk 'w3 == "aa0103e0" && w2 == "aa0203e1" && w1 == "aa0303e2" && $0 == "d28000b0" { n++ } { w3 = w2; w2 = w1; w1 = $0 } END { print n + 0 }' "$D/eo_ma.w")
        if [ "$natfd" -lt 1 ]; then bad "axis 5: the arm64-macOS build carries no folded openat body (cmn x0,#100; b.ne; movn x0,#1; movz x16,#463) — 56 does not reach Darwin openat with its dirfd"
        elif [ "$nshift" != 0 ]; then bad "axis 5: the arm64-macOS build still carries $nshift open(5) arg-shift bodies — a dirfd is dropped"
        else ok; fi
    fi
fi

# axis 6: behaviour — native (the oracle), qemu-aarch64, PE under wine.
summary() {  # $1 = output file -> "passed failed"
    tr -d '\r' < "$1" | sed -n 's/^\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1 \2/p' | tail -1
}
grade() {  # $1 = label, $2 = output file, $3 = exit code, $4 = floor
    s=$(summary "$2"); np=${s% *}; nf=${s#* }
    if [ -z "$s" ]; then bad "axis 6 ($1): no summary (exit $3)"
    elif [ "$3" != 0 ] || [ "$nf" != 0 ]; then
        bad "axis 6 ($1): $np passed, $nf failed (exit $3)"
        tr -d '\r' < "$2" | grep -m6 'FAIL:' | sed 's/^/      /'
    elif [ "$np" -lt "$4" ]; then bad "axis 6 ($1): only $np rows ran (floor $4)"
    else ok; fi
}
( cd "$ROOT" && "$CC" < "$TC" > "$D/eo" 2> "$D/eo.err" )
if [ ! -s "$D/eo" ]; then
    bad "axis 6: the native build of embed_open_under_root.tcyr produced no binary: $(grep -m2 '^error' "$D/eo.err" | tr '\n' ' ')"
else
    chmod +x "$D/eo"; mkdir -p "$D/n"
    nrc=0; ( cd "$D/n" && ulimit -c 0 && "$D/eo" > "$D/n.out" 2>&1 ) || nrc=$?
    grade native "$D/n.out" "$nrc" 25
fi
if command -v qemu-aarch64 > /dev/null 2>&1 && [ -s "$D/cc_a64" ]; then
    ( cd "$ROOT" && "$D/cc_a64" < "$TC" > "$D/eo_a" 2> "$D/eo_a.err" )
    if [ ! -s "$D/eo_a" ]; then bad "axis 6: the aarch64 build of the .tcyr produced no binary"
    else
        chmod +x "$D/eo_a"; mkdir -p "$D/a"
        arc=0; ( cd "$D/a" && ulimit -c 0 && qemu-aarch64 "$D/eo_a" > "$D/a.out" 2>&1 ) || arc=$?
        grade qemu-aarch64 "$D/a.out" "$arc" 25
    fi
elif [ -s "$D/cc_a64" ]; then
    echo "  SKIP: axis 6 qemu-aarch64 (qemu-aarch64 absent — pi runs the .tcyr in the release gate)"
else
    echo "  SKIP: axis 6 qemu-aarch64 (no aarch64 cross compiler — axis 5 has failed on that)"
fi
if ! command -v wine > /dev/null 2>&1; then
    echo "  SKIP: axis 6 wine (wine absent — the cass cross-OS leg runs embed_open_under_root.tcyr on real Windows)"
else
    mkdir -p "$D/w"
    ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$D/w/eo.exe" 2> "$D/eo_w.err" )
    if [ ! -s "$D/w/eo.exe" ]; then
        bad "axis 6: the PE build of embed_open_under_root.tcyr produced no binary: $(grep -m2 '^error' "$D/eo_w.err" | tr '\n' ' ')"
    else
        wrc=0
        ( cd "$D/w" && ulimit -c 0; LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            wine eo.exe > "$D/w.out" 2>&1 ) || wrc=$?
        if tr -d '\r' < "$D/w.out" | grep -q 'SKIP: the directory-link rows'; then
            bad "axis 6 (PE): this wine refused to create the directory link, so the race rows did not run"
        else
            grade "PE" "$D/w.out" "$wrc" 30
        fi
    fi
    WINEPREFIX="$WP" wineserver -k > /dev/null 2>&1 || true
fi

echo "$pass passed, $fail failed"
[ "$pass" -ge 6 ] || { echo "FAIL: embed_link_race_pe: only $pass rows ran (floor 6)"; exit 1; }
if [ "$fail" -ne 0 ]; then echo "FAIL: embed_link_race_pe"; exit 1; fi
echo "PASS: embed_link_race_pe — 0xF04E routed at its arity, named, imported; the [embed] open refuses a file a directory link leads outside the project on Windows (final-path containment) and walks with a kept dirfd on arm64 macOS"
