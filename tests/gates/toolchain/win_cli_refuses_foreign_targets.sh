#!/bin/sh
# tests/gates/toolchain/win_cli_refuses_foreign_targets.sh — 6.7.11
#
# A CLI whose compiler cannot emit a target REFUSES that target by name (user, 2026-10-13): on
# Windows and macOS, `--agnos`, `--target=x86_64-bare-metal-elf` and `--target=aarch64-bare-metal-elf`
# are rc 1 with `error: <flag> is not available from the Windows CLI: cycc.exe emits PE only (build
# agnos / bare-metal images on Linux)` (macOS: `the macOS CLI: cycc emits Mach-O only`), before
# anything compiles or is written.
#
# THE FILED DEFECT (docs/development/issues/archived/2026-10-10-windows-cli-drops-target-selectors.md). The
# selectors reach the compiler as environment entries (CYRIUS_TARGET_AGNOS, CYRIUS_KERNEL +
# CYRIUS_ELF64_KERNEL). compile()'s Windows arm never passed them, and the PE-hosted compiler
# (src/main_win.cyr) reads none of them anyway, so cyrius.exe built a plain PE, printed `OK (2560
# bytes)` and exited 0 — plus `kernel: entry 0x1000a8 … (x86_64 ELF64 multiboot2)` for an ELF that
# was never written. The macOS CLIs pass them, but the Mach-O compilers read none either: measured
# 2026-10-14 on ecb (arm64) and ach (x86_64), all three wrote a Mach-O at rc 0 (ach's aarch64 one
# failed only because no cycc_aarch64 ships there). The fix: cbt/cli_args.cyr `_cli_foreign_target`,
# the first block of `_cli_apply_target`, asks `_cli_host_emits_only()` (`#ifdef CYRIUS_TARGET_WIN` /
# `CYRIUS_TARGET_MACOS`; 0 on Linux: x86_64 Linux, where src/main.cyr honours the selectors — the
# aarch64 Linux CLI's forks read CYRIUS_KERNEL alone and drop `--agnos` / the x86_64 bare-metal target,
# issues/2026-10-14-aarch64-linux-cli-drops-target-selectors.md).
#
# THE ROWS.
#   S  (always) the CLI built for each host carries exactly its own refusal: the PE build the
#      Windows text, the x86_64 and arm64 Mach-O builds the macOS text, the Linux build neither.
#      (A Mach-O cannot run here; ecb / ach ran it by hand — see the CHANGELOG.)
#   L  (always) the x86_64 Linux CLI keeps all three selectors: `--agnos` and the x86_64 bare-metal target
#      write an ELF (rc 0; the kernel line printed), the aarch64 bare-metal one an aarch64 ELF.
#   W  (wine) cyrius.exe + cycc.exe built from this tree: the three selectors each rc 1, the exact
#      named error on stderr, no output file, a pre-existing output left byte-for-byte; `run --agnos`
#      refused the same way; a plain build rc 0, an `MZ` image that exits 7; `--win` accepted (an
#      `MZ`); `--target=cx` and `--target=js` reach their own arms (their dry-run lines). wine is not
#      hardware: the release gate's cass leg (and the .bat probe in the CHANGELOG) is the real
#      Windows.
#
# MUTATION PROOF (scratch copies of the tree with cbt/ mutated, run through THIS gate; GREEN on the
# real tree):
#   M1  `_cli_apply_target` without its `_cli_foreign_target()` call (the 6.7.10        RED 5: W1-W5
#       behaviour: W1 / W2 an `MZ` at rc 0, W2 the kernel line, W5 ran the program, exit 7)
#   M2  `_cli_host_emits_only` without its CYRIUS_TARGET_WIN arm                       RED 6: S1, W1-W5
#   M3  `_cli_host_emits_only` without its CYRIUS_TARGET_MACOS arm                     RED 1: S2
#   M4  the Windows answer on every host (the refusal leaks onto Linux and macOS)     RED 5: S2, S3,
#                                                                                             L1-L3
#   M5  only `--agnos` refused (the two `--target` tests never match)                 RED 2: W2, W3
set -u
G=win_cli_refuses_foreign_targets
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G — no compiler at $CC"; exit 1; }
command -v timeout > /dev/null 2>&1 || { echo "FAIL: $G — needs timeout(1)"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
WP="$T/wine"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
fails=0
checks=0
skips=0
check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
WINWHY="the Windows CLI: cycc.exe emits PE only"
MACWHY="the macOS CLI: cycc emits Mach-O only"
TAIL="(build agnos / bare-metal images on Linux)"
# has FILE TEXT -> yes / no (a fixed-string search of the binary)
has() { if grep -aqF "$2" "$1" 2> /dev/null; then echo yes; else echo no; fi; }
magic() { if [ -f "$1" ]; then od -An -tx1 -N4 "$1" | tr -d ' \n'; else echo none; fi; }

# Every compiler and CLI below is built from THIS tree (never build/cyrius, the store or PATH), with
# no inherited compile-mode switch.
unset CYRIUS_BOUNDS CYRIUS_POISON CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE CYRIUS_TARGET_WIN CYRIUS_TARGET_AGNOS \
    CYRIUS_KERNEL CYRIUS_ELF64_KERNEL CYRIUS_MACHO CYRIUS_MACHO_ARM 2> /dev/null || true
mkdir -p "$T/lin" "$T/proj"
build() {   # build OUT ENV... < SRC — fails the gate by name if the result is empty
    _o=$1; shift
    if ! env "$@" "$CC_USE" > "$_o" 2> "$_o.err" || [ ! -s "$_o" ]; then
        echo "FAIL: $G — could not build $_o: $(grep -m1 -i error "$_o.err")"; exit 1
    fi
}
CC_USE="$CC"; build "$T/lin/cyrius" X=1 < cbt/cyrius.cyr; chmod +x "$T/lin/cyrius"
CC_USE="$CC"; build "$T/cc_win" X=1 < src/main_win.cyr; chmod +x "$T/cc_win"
CC_USE="$CC"; build "$T/cc_x" X=1 < src/main_aarch64.cyr; chmod +x "$T/cc_x"
CC_USE="$T/cc_win"; build "$T/cyrius.exe" X=1 < cbt/cyrius.cyr
CC_USE="$CC"; build "$T/cyrius_macho_x86" CYRIUS_MACHO=1 < cbt/cyrius.cyr
CC_USE="$T/cc_x"; build "$T/cyrius_macho_arm" CYRIUS_MACHO_ARM=1 < cbt/cyrius.cyr

echo "== S: each host's CLI carries its own refusal =="
check "S1 the PE CLI names the Windows refusal" "yes yes no" \
    "$(has "$T/cyrius.exe" "$WINWHY") $(has "$T/cyrius.exe" "$TAIL") $(has "$T/cyrius.exe" "$MACWHY")"
check "S2 the Mach-O CLIs (x86_64, arm64) name the macOS refusal" "yes yes no no" \
    "$(has "$T/cyrius_macho_x86" "$MACWHY") $(has "$T/cyrius_macho_arm" "$MACWHY") $(has "$T/cyrius_macho_x86" "$WINWHY") $(has "$T/cyrius_macho_arm" "$WINWHY")"
check "S3 the Linux CLI carries neither" "no no" "$(has "$T/lin/cyrius" "$WINWHY") $(has "$T/lin/cyrius" "$MACWHY")"

printf 'fn main(): i64 { return 7; }\nvar r = main();\nsyscall(60, r);\n' > "$T/proj/hello.cyr"

echo "== L: the Linux CLI keeps the selectors =="
# The wrapper finds the cycc (and cycc_aarch64) beside it (v6.5.42).
cp "$CC" "$T/lin/cycc"
cp "$T/cc_x" "$T/lin/cycc_aarch64"
mkdir -p "$T/lhome"
lrun() {   # lrun OUT ARGS... -> rc; stdout+stderr in $T/l.out
    _rc=0
    (cd "$T/proj" && HOME="$T/lhome" CYRIUS_HOME="$T/lhome/.cyrius" timeout 120 "$T/lin/cyrius" build "$@") \
        > "$T/l.out" 2>&1 || _rc=$?
    echo "$_rc"
}
rc=$(lrun --agnos hello.cyr l_agnos.out)
check "L1 --agnos: rc, an ELF" "0 7f454c46" "$rc $(magic "$T/proj/l_agnos.out")"
rc=$(lrun --target=x86_64-bare-metal-elf hello.cyr l_bm.out)
check "L2 --target=x86_64-bare-metal-elf: rc, an ELF, the kernel line" "0 7f454c46 1" \
    "$rc $(magic "$T/proj/l_bm.out") $(grep -c 'kernel: entry 0x1000a8' "$T/l.out")"
rc=$(lrun --target=aarch64-bare-metal-elf hello.cyr l_bma.out)
# e_machine (bytes 18-19): 0xb7 = EM_AARCH64
check "L3 --target=aarch64-bare-metal-elf: rc, an aarch64 ELF" "0 7f454c46 b700" \
    "$rc $(magic "$T/proj/l_bma.out") $(od -An -tx1 -j18 -N2 "$T/proj/l_bma.out" 2> /dev/null | tr -d ' \n')"

echo "== W: the Windows CLI, under wine =="
if ! command -v wine > /dev/null 2>&1 || ! command -v winepath > /dev/null 2>&1; then
    echo "  SKIP (named): the W rows — wine is not installed; the Windows CLI is covered only by the cass leg"
    skips=$((skips + 1))
else
    # A PRIVATE prefix, and wine's own HOME / XDG_CACHE_HOME under $T (a fresh prefix writes $HOME/.cache).
    export WINEPREFIX="$WP" HOME="$T/whome" XDG_CACHE_HOME="$T/whome/.cache" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    mkdir -p "$T/whome" "$T/w/bin" "$T/w/ch" "$T/w/proj"
    cp "$T/cyrius.exe" "$T/w/bin/cyrius.exe"
    CC_USE="$T/cc_win"; build "$T/w/bin/cycc.exe" X=1 < src/main_win.cyr
    cp "$T/proj/hello.cyr" "$T/w/proj/hello.cyr"
    wine cmd /c exit 0 > /dev/null 2>&1 || true   # create the prefix before winepath needs it
    CH=$(winepath -w "$T/w/ch" 2> /dev/null)
    [ -n "$CH" ] || { echo "FAIL: $G — winepath could not map the throwaway CYRIUS_HOME"; exit 1; }
    wrun() {   # wrun VERB ARGS... -> rc; stdout in $T/w.out, stderr in $T/w.err
        _rc=0
        (cd "$T/w/proj" && CYRIUS_HOME="$CH" timeout 300 wine "$T/w/bin/cyrius.exe" "$@") \
            > "$T/w.out" 2> "$T/w.err" || _rc=$?
        echo "$_rc"
    }
    # refused FLAG -> "rc lines" : rc, and how many stderr lines are exactly the decided text
    refused() {
        _want="error: $1 is not available from $WINWHY $TAIL"
        echo "$(grep -cxF "$_want" "$T/w.err" 2> /dev/null || :)"
    }
    rc=$(wrun build --agnos hello.cyr agnos.out)
    check "W1 build --agnos: rc 1, the named error, no output" "1 1 none" \
        "$rc $(refused --agnos) $(magic "$T/w/proj/agnos.out")"
    rc=$(wrun build --target=x86_64-bare-metal-elf hello.cyr bm.out)
    check "W2 build --target=x86_64-bare-metal-elf: rc 1, the named error, no output, no kernel line" "1 1 none 0" \
        "$rc $(refused --target=x86_64-bare-metal-elf) $(magic "$T/w/proj/bm.out") $(cat "$T/w.out" "$T/w.err" | grep -c 'kernel: entry')"
    rc=$(wrun build --target=aarch64-bare-metal-elf hello.cyr bma.out)
    check "W3 build --target=aarch64-bare-metal-elf: rc 1, the named error, no output" "1 1 none" \
        "$rc $(refused --target=aarch64-bare-metal-elf) $(magic "$T/w/proj/bma.out")"
    printf 'old\n' > "$T/w/proj/keep.out"
    rc=$(wrun build --agnos hello.cyr keep.out)
    kept=changed
    [ "$(cat "$T/w/proj/keep.out" 2> /dev/null)" = old ] && kept=untouched
    check "W4 build --agnos over an existing output: rc 1, the file untouched" "1 untouched" "$rc $kept"
    rc=$(wrun run --agnos hello.cyr)
    check "W5 run --agnos (another verb): rc 1, the named error, nothing run" "1 1 0" \
        "$rc $(refused --agnos) $(grep -c 'compile' "$T/w.out")"
    rc=$(wrun build hello.cyr plain.exe)
    check "W6 a plain build: rc 0, a PE" "0 4d5a" "$rc $(magic "$T/w/proj/plain.exe" | cut -c1-4)"
    prc=0
    (cd "$T/w/proj" && timeout 120 wine ./plain.exe) > /dev/null 2>&1 || prc=$?
    check "W7 the plain build runs and exits 7" 7 "$prc"
    rc=$(wrun build --win hello.cyr w.exe)
    check "W8 --win stays accepted (a no-op on the Windows CLI): rc 0, a PE" "0 4d5a" \
        "$rc $(magic "$T/w/proj/w.exe" | cut -c1-4)"
    rc=$(wrun build --dry-run --target=cx hello.cyr out.cyx)
    check "W9 --target=cx reaches its own arm (dry-run: emit-cx)" "0 1" "$rc $(grep -c '^dry-run: emit-cx hello.cyr' "$T/w.out")"
    rc=$(wrun build --dry-run --target=js hello.cyr out.js)
    check "W10 --target=js reaches its own arm (dry-run: emit-js)" "0 1" "$rc $(grep -c '^dry-run: emit-js hello.cyr' "$T/w.out")"
    _wine_down
fi

echo ""
if [ "$fails" -gt 0 ]; then
    for f in l.out w.out w.err; do [ -s "$T/$f" ] && { echo "  ($f, first lines)"; sed -n '1,6p' "$T/$f" | sed 's/^/    /'; }; done
    echo "FAIL: $G — $fails of $checks checks failed"
    exit 1
fi
if [ "$skips" -gt 0 ]; then
    echo "SKIP: $G — $skips leg(s) could not run here (named above); all $checks checks that ran passed (exit 77: a SKIP, not a PASS)"
    exit 77
fi
echo "PASS: $G — $checks checks"
exit 0
