#!/bin/sh
# An `include` directly after `#@pkgver` is missing from the file map.
#
#   sh 2026-11-01-first-prelude-include-unmapped.sh [path-to-cycc] [path-to-stdlib-lib-dir]
#
# Defaults to the current toolchain. Writes only into a new mktemp directory,
# which it leaves behind and prints.
CC=${1:-$(cyrius which 2>/dev/null)}
SNAP=${2:-$HOME/.cyrius/lib}
D=$(mktemp -d "${TMPDIR:-/tmp}/first-include.XXXXXX") || exit 1
echo "cycc: $CC ($("$CC" --version 2>&1 | head -1))"
echo "work: $D"
cd "$D" || exit 1
mkdir lib
cp "$SNAP/fnptr.cyr" lib/
printf 'fn broken( { return 0; }\n' > lib/bad.cyr
printf '# fine\n' > lib/ok.cyr

BODY='fn efi_main(h, s): i64 { return 0; }\n'
PV='#@pkgver 0.0.1\n'
F='include "lib/fnptr.cyr"\n'
BAD='include "lib/bad.cyr"\n'
OK='include "lib/ok.cyr"\n'

case_() {
    printf '%b' "$2" > "$1.cyr"
    CYRIUS_TARGET_EFI=1 "$CC" < "$1.cyr" > "$1.out" 2> "$1.err"
    rc=$?
    printf '  %-26s exit=%-3s reserved=%-2s %s\n' "$1" "$rc" \
        "$(grep -c 'reserved intrinsic' "$1.err")" \
        "$(grep -m1 -E '^error' "$1.err" | cut -c1-60)"
}

echo 'fnptr.cyr (expect exit=0 reserved=0 in every row):'
case_ fnptr_no_pkgver     "$F$BODY"
case_ fnptr_after_pkgver  "$PV$F$BODY"
case_ fnptr_after_blank   "$PV\n$F$BODY"
case_ fnptr_second        "$PV$OK$F$BODY"

echo 'a syntax error in lib/bad.cyr line 1 (expect every row to name lib/bad.cyr:1):'
case_ bad_no_pkgver       "$BAD"
case_ bad_after_pkgver    "$PV$BAD"
case_ bad_after_blank     "$PV\n$BAD"
case_ bad_second          "$PV$OK$BAD"
