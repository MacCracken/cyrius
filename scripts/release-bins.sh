#!/bin/sh
# Build every cyrius.cyml `[release] bins` entry for one tarball target into a release staging bin/.
# Usage: sh scripts/release-bins.sh <macos-arm64|macos-x86_64|windows> <stage-bin-dir> <compiler>
#   (run from the repo root, as release-scripts.sh is: the compiles resolve `include` against it)
#   <compiler> is the Linux-hosted compiler that emits the target: macos-arm64 the aarch64 cross
#   compiler (run here with CYRIUS_MACHO_ARM=1), macos-x86_64 build/cycc (run with CYRIUS_MACHO=1),
#   windows cycc_win (src/main_win.cyr; it emits PE itself, and each output is named <bin>.exe).
#
# The list is read from the manifest, never kept here. The macOS and Windows builders built a HAND
# list (cyrfmt cyrlint cyrdoc cyrius-init cyrsign cxvm cyaudit cyrius_api_surface), so a macOS or
# Windows binary install had no cyrius-lsp, ark, cyrld, ts_test_runner or cyrsign-efi, and bin/cyriusly
# was the shell script; the aarch64 Linux job reads the manifest since 6.7.14 (the user's 6.7.14 D59:
# ship every [release] bin, built for aarch64), and the macOS and Windows jobs since 6.7.16 (kept by
# 6.7.17's D84). Every entry is built for
# the target and arch-checked (the Mach-O magic and cputype, the PE signature and machine); a listed
# entry with no programs/<bin>.cyr, a compile that fails, an empty output or a wrong architecture
# FAILS, naming it. Every source is checked before anything compiles. CHANGELOG [6.7.16]
#
# The entries NOT built here, each for a reason (tests/gates/toolchain/cli_args_never_dropped.sh
# axis 15 holds every builder to the manifest's list less exactly these):
#   cybs        the x86_64 assembly the 29 KB seed assembles (bootstrap/cybs.cyr): no Mach-O or PE
#               form, as on aarch64 Linux.
#   cycc        the builder's own line: the target's own driver (src/main_aarch64_macho.cyr,
#               src/main_x86_macho.cyr, src/main_win.cyr), not a programs/ source.
#   cyrius      the builder's own line: cbt/cyrius.cyr, not a programs/ source.
#   cyrius-lsp  windows only: cycc_win refuses it ("refusing to emit binary with 2 reachable
#               undefined function(s)": sys_fstat and sys_readlink have no PE wrapper), and it
#               forks a compiler child through pipes, which PE stubs as -1.
set -e
TARGET="${1:?usage: release-bins.sh <macos-arm64|macos-x86_64|windows> <stage-bin-dir> <compiler>}"
DEST="${2:?usage: release-bins.sh <macos-arm64|macos-x86_64|windows> <stage-bin-dir> <compiler>}"
CC="${3:?usage: release-bins.sh <macos-arm64|macos-x86_64|windows> <stage-bin-dir> <compiler>}"
case "$TARGET" in
    macos-arm64|macos-x86_64) EXT="" ;;
    windows) EXT=".exe" ;;
    *) echo "ERROR: release-bins.sh: unknown target '$TARGET' (macos-arm64, macos-x86_64 or windows)" >&2; exit 1 ;;
esac
[ -x "$CC" ] || { echo "ERROR: release-bins.sh: compiler $CC is not an executable" >&2; exit 1; }
# The same override release-scripts.sh, release-lib.sh and install.sh's _parse_release_array honour.
CYML="${CYRIUS_CYML:-cyrius.cyml}"
[ -f "$CYML" ] || { echo "ERROR: release-bins.sh: $CYML not found (run from the repo root)" >&2; exit 1; }

BINS=$(awk -v k="bins" '
    /^\[release\]/ { in_r = 1; next }
    in_r && /^\[/ { exit }
    in_r && $1 == k {
        sub(/^[^=]+= \[/, ""); sub(/\].*$/, "")
        gsub(/[",]/, " "); gsub(/ +/, " ")
        sub(/^ +/, ""); sub(/ +$/, ""); print; exit
    }' "$CYML")
[ -n "$BINS" ] || { echo "ERROR: release-bins.sh: $CYML has no [release] bins list (or it parsed to nothing)" >&2; exit 1; }

# _skip <bin>: 0 when this script does not build <bin> for $TARGET (the header names each reason).
_skip() {
    case "$1" in cybs|cycc|cyrius) return 0 ;; esac
    [ "$TARGET" = windows ] && [ "$1" = cyrius-lsp ] && return 0
    return 1
}
for bin in $BINS; do
    _skip "$bin" && continue
    [ -f "programs/$bin.cyr" ] || { echo "ERROR: $CYML [release] bins lists $bin, and programs/$bin.cyr does not exist" >&2; exit 1; }
done

# _hex <file> <offset> <count>: those bytes as lowercase hex, no spaces.
_hex() { od -An -tx1 -j"$2" -N"$3" "$1" | tr -d ' \n'; }
# _arch_ok <file>: 0 when <file> is an executable image for $TARGET.
_arch_ok() {
    [ -s "$1" ] || return 1
    case "$TARGET" in
        macos-arm64)  [ "$(_hex "$1" 0 4)" = cffaedfe ] && [ "$(_hex "$1" 4 4)" = 0c000001 ] ;;
        macos-x86_64) [ "$(_hex "$1" 0 4)" = cffaedfe ] && [ "$(_hex "$1" 4 4)" = 07000001 ] ;;
        windows)
            [ "$(_hex "$1" 0 2)" = 4d5a ] || return 1
            # e_lfanew (little-endian u32 at 0x3c) -> "PE\0\0", then the machine (0x8664 = x86-64).
            _pe=$(od -An -tu4 -j60 -N4 "$1" | tr -d ' \n')
            [ -n "$_pe" ] && [ "$(_hex "$1" "$_pe" 6)" = 504500006486 ] ;;
    esac
}
mkdir -p "$DEST"
_ERR=$(mktemp) && [ -f "$_ERR" ] || { echo "ERROR: release-bins.sh: mktemp failed (TMPDIR=${TMPDIR:-/tmp})" >&2; exit 1; }
trap 'rm -f "$_ERR"' EXIT
for bin in $BINS; do
    _skip "$bin" && continue
    out="$DEST/$bin$EXT"
    rc=0
    case "$TARGET" in
        macos-arm64)  CYRIUS_MACHO_ARM=1 "$CC" < "programs/$bin.cyr" > "$out" 2> "$_ERR" || rc=$? ;;
        macos-x86_64) CYRIUS_MACHO=1 "$CC" < "programs/$bin.cyr" > "$out" 2> "$_ERR" || rc=$? ;;
        windows)      "$CC" < "programs/$bin.cyr" > "$out" 2> "$_ERR" || rc=$? ;;
    esac
    if [ "$rc" != 0 ]; then
        echo "ERROR: release-bins.sh: programs/$bin.cyr does not build for $TARGET (rc $rc):" >&2
        grep -E '^(error|warning: undefined)' "$_ERR" | head -5 >&2 || true
        exit 1
    fi
    _arch_ok "$out" || { echo "ERROR: release-bins.sh: $bin$EXT is not a $TARGET image ($(_hex "$out" 0 8))" >&2; exit 1; }
    chmod +x "$out"
done
