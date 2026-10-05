#!/bin/sh
# Gate: in a `kernel;` build an array initializer is IN THE IMAGE, not a store behind the program
# (6.6.16, C1).
#
# ⛔ WHY. The list used to be stored at run time by the deferred replay (EMIT_GVAR_INITS), and an
# x86 kernel build emits that replay AFTER the top-level program (src/main.cyr's `_init_km == 1`
# branch — the v5.7.19 multiboot invariant, which agnos depends on). A kernel whose top-level
# program never returns therefore never ran the stores: measured at the 6.6.16 slot open,
# `kernel; var B[1] = { 0x77, 0x66 }; asm { 0xF4 x4 }` emitted `c6 41 00 77 c6 41 01 66` AFTER the
# asm, and B read 0. src/common/util.cyr carried a comment saying per-byte arrays "don't suffer the
# kmode-entry init-order bug" — false. Every image target now bakes the list (_gai_bake), the way a
# scalar constant has been baked since v5.11.64, and emits no code for it.
#
# HOW IT IS MEASURED — a differential, so it cannot pass by reading nothing. Each row builds the
# program TWICE: the test, and a control that declares the same arrays with no initializer. Then:
#   * the two images are the SAME SIZE — a store sequence would make the test longer;
#   * every byte that differs lies AFTER the program's `f4 f4 f4 f4` marker (the code is identical,
#     so nothing was emitted for the lists), and exactly as many bytes differ as the lists hold
#     nonzero bytes;
#   * each array's bytes are found, contiguous, in the test image and not in the control's.
# Rows:
#   K0  x86 `kernel;`, the bare byte list that compiled before 6.6.16 (it was RED by size)
#   K   x86 `kernel;`, typed u32 / i64 lists with enum elements, and a module-scope declaration
#       after the first statement (the top-level asm)
#   E   CYRIUS_TARGET_EFI=1 `kernel;` with an `efi_main` and bare byte lists (a UTF-16 string, a
#       GUID) — gnoboot's build shape: 29 such arrays. There the late replay does run (before
#       efi_main), so the values were right; what changes is that no store is emitted and the
#       bytes are in the image (gnoboot 0.7.2 in scratch: 37,376 -> 35,328 bytes, all 29 arrays
#       found contiguous in the new image).
#
# MUTATION LEDGER (6.6.16):
#   1. real tree                                      -> GREEN (3 rows)
#   2. the slot-open compiler                          -> RED, 9 checks: K0 by size, E by its code and
#                                                         missing bytes (a PE pads to its section size), K refused
#   3. _EMIT_GVAR_STATIC_INITS without the _gai_bake call -> RED, 10 checks: no row finds its bytes
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
[ -x "$CC" ] || { echo "FAIL: kmode_array_initializer_baked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: kmode_array_initializer_baked: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
fail=0
rows=0
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# The image as " xx xx xx ..." (one space before every byte), so a pattern only matches on a
# byte boundary.
hexs() { od -An -v -tx1 "$1" | tr -s ' \n' '  ' | sed 's/^ *//; s/^/ /; s/ *$/ /'; }
# occurrences of the byte pattern $2 (" xx xx ... ") in file $1
count() { hexs "$1" | awk -v p="$2" '{ n = 0; s = $0; while ((i = index(s, p)) > 0) { n++; s = substr(s, i + 1) } print n }'; }
# 0-based offset of the first `f4 f4 f4 f4`, or -1
marker() { hexs "$1" | awk '{ i = index($0, " f4 f4 f4 f4 "); if (i == 0) print -1; else print (i - 1) / 3 }'; }

# row <id> <env> <nonzero bytes> <test source> <control source> <pattern>...
row() {
    rows=$((rows + 1))
    id=$1; envs=$2; want=$3; shift 3
    printf '%b' "$1" > "$T/$id.cyr"
    printf '%b' "$2" > "$T/$id.ctl.cyr"
    shift 2
    if ! env $envs "$CC" < "$T/$id.cyr" > "$T/$id.bin" 2> "$T/$id.err"; then
        bad "$id: the test does not compile: $(grep -m1 '^error' "$T/$id.err")"; return
    fi
    if ! env $envs "$CC" < "$T/$id.ctl.cyr" > "$T/$id.ctl" 2> "$T/$id.ctl.err"; then
        bad "$id: the control does not compile: $(grep -m1 '^error' "$T/$id.ctl.err")"; return
    fi
    st=$(wc -c < "$T/$id.bin"); sc=$(wc -c < "$T/$id.ctl")
    [ "$st" -eq "$sc" ] || bad "$id: the image is $st bytes against the control's $sc (code was emitted for the list)"
    m=$(marker "$T/$id.bin")
    [ "$m" -ge 0 ] || { bad "$id: no f4 f4 f4 f4 marker in the image"; return; }
    cmp -l "$T/$id.bin" "$T/$id.ctl" > "$T/$id.cmp" 2>/dev/null
    nd=$(awk 'END { print NR }' "$T/$id.cmp")
    early=$(awk -v m="$m" '$1 - 1 <= m + 3 { n++ } END { print n + 0 }' "$T/$id.cmp")
    [ "$early" = 0 ] || bad "$id: $early byte(s) differ at or before the program's marker (offset $m): the code changed"
    [ "$nd" = "$want" ] || bad "$id: $nd bytes differ from the control, want $want (the lists' nonzero bytes)"
    for p in "$@"; do
        ct=$(count "$T/$id.bin" "$p"); cc=$(count "$T/$id.ctl" "$p")
        [ "$ct" -ge 1 ] || bad "$id: '$p' is not in the image"
        [ "$cc" = 0 ] || bad "$id: '$p' is in the CONTROL image too (the row would be vacuous)"
    done
}

row K0 '' 2 \
    'kernel;\nvar KB[1] = { 0x77, 0x66 };\nasm { 0xF4; 0xF4; 0xF4; 0xF4; }\n' \
    'kernel;\nvar KB[1];\nasm { 0xF4; 0xF4; 0xF4; 0xF4; }\n' \
    ' 77 66 00 00 00 00 00 00 '

row K '' 22 \
    'kernel;\nenum KE { KA = 0x1234567; }\nvar KB[1] = { 0x77, 0x66 };\nvar KT: u32[2] = {0x5A17C0DE, 0x0BADF00D};\nvar KN: i64[2] = {KA, KE.KA + 1};\nasm { 0xF4; 0xF4; 0xF4; 0xF4; }\nvar KP: u16[2] = {0xBEEF, 0xCAFE};\n' \
    'kernel;\nenum KE { KA = 0x1234567; }\nvar KB[1];\nvar KT: u32[2];\nvar KN: i64[2];\nasm { 0xF4; 0xF4; 0xF4; 0xF4; }\nvar KP: u16[2];\n' \
    ' 77 66 00 00 00 00 00 00 ' ' de c0 17 5a 0d f0 ad 0b ' ' 67 45 23 01 00 00 00 00 68 45 23 01 00 00 00 00 ' ' ef be fe ca '

row E 'CYRIUS_TARGET_EFI=1' 18 \
    'kernel;\nvar EM[1] = { 0x67, 0x00, 0x6E, 0x00, 0x6F, 0x00 };\nvar EG[2] = { 0x8B, 0xE4, 0xDF, 0x61, 0x93, 0xCA, 0x11, 0xD2, 0xAA, 0x0D, 0x00, 0xE0, 0x98, 0x03, 0x2B, 0x8C };\nasm { 0xF4; 0xF4; 0xF4; 0xF4; }\nfn efi_main(handle, st): i64 { return load8(&EM) + load8(&EG); }\n' \
    'kernel;\nvar EM[1];\nvar EG[2];\nasm { 0xF4; 0xF4; 0xF4; 0xF4; }\nfn efi_main(handle, st): i64 { return load8(&EM) + load8(&EG); }\n' \
    ' 67 00 6e 00 6f 00 00 00 ' ' 8b e4 df 61 93 ca 11 d2 aa 0d 00 e0 98 03 2b 8c '
# E must really be the EFI image (a PE32+ with the EFI-application subsystem), or the row is x86 ELF again.
if [ -s "$T/E.bin" ]; then
    [ "$(od -An -tx1 -N2 "$T/E.bin" | tr -d ' ')" = 4d5a ] || bad "E: the CYRIUS_TARGET_EFI=1 build is not an MZ/PE image"
fi

[ "$rows" -ge 3 ] || bad "only $rows rows ran (floor 3)"
if [ "$fail" -ne 0 ]; then
    echo "FAIL: kmode_array_initializer_baked ($fail checks failed over $rows rows)"
    exit 1
fi
echo "PASS: kmode_array_initializer_baked ($rows rows)"
exit 0
