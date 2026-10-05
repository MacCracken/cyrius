#!/bin/sh
# Gate: in an x86 `kernel;` build, a global initializer that names an enum constant holds its value
# from the first instruction, and what still runs late is named (6.6.16, C6).
#
# ⛔ WHY. Pass 1's constant folder refuses every name (it sees only the names declared so far, so it
# would miss a forward enum and fold 3 where a later `var A = 9;` makes the program read 9), so a
# global whose initializer names an enum — `var X = A;`, `E.A`, `A + 1`, `var X: u8 = A;` — and
# every struct literal was a runtime store in the deferred replay. An x86 kernel build emits that
# replay AFTER its top-level program (src/main.cyr's `_init_km == 1` branch, the v5.7.19 multiboot
# order agnos depends on), so a kernel that never returns read 0. Measured at the 6.6.16 slot open:
# `kernel; enum E { A = 0x1234567; } var X = A; asm { 0xF4 x4 }` put `b8 67 45 23 01 48 b9 .. 48 89
# 01` AFTER the asm and left X's slot zero in the image. The fold now sits at the replay, where
# names resolve exactly as the replayed store does, and the value is BAKED (parse_decl.cyr
# _gvk_pre / _spc_try); the store stays, so the code does not change.
#
# HOW IT IS MEASURED.
#   R  RUN rows. A CYRIUS_ELF64_KERNEL=1 build (agnos's own build mode) is an ELF64 that also runs
#      as a Linux process: its top-level program runs, then the late replay, then the exit. So the
#      program reads exactly what the IMAGE holds — the strongest form of the claim. Every form
#      (scalars, narrow annotations, struct fields, nested structs, an f64 field, an array list's
#      enum elements, the redeclaration orders, a forward enum, the shadow) is checked by value; the exit code names the first wrong
#      one. A literal control (baked since v5.11.64) proves the program does read the image.
#   I  IMAGE rows for the builds that do not run here — the default `kernel;` (an ELF32 multiboot
#      image) and CYRIUS_TARGET_EFI=1 (gnoboot's shape). A differential: the test declares the
#      globals in the declaration zone, the control declares the SAME globals after the first
#      statement (program-order stores: the same immediates in the code, nothing baked). Each
#      value's 8-byte slot pattern must occur exactly once more in the test image than in the
#      control's — the baked copy. A value that must NOT be baked occurs equally often.
#   W  WARNING rows: an initializer an x86 kernel build still leaves to its late replay is named,
#      once per declaration, and only where it is true — not in a host build, not in an aarch64
#      kernel build (it replays BEFORE its program; its compiler is built from this tree), not in an
#      EFI build with an `efi_main` (the replay runs before efi_main is called), not in a build that
#      has already failed, never twice for one error.
#
# MUTATION LEDGER (6.6.16):
#   1. real tree                                   -> GREEN (11 rows)
#   2. the srcb-2 compiler (C1, no C6)              -> RED, 24 checks: R stops at row 2 (the first enum
#                                                     form), every I scalar / struct pattern is missing,
#                                                     no W row finds its warning (KL passes: C1's bake)
#      the slot-open compiler                       -> RED, 22 checks (R does not compile: an enum in a list)
#   3. _gvk_pre's record removed                    -> RED, 7 checks: R row 2, the I scalar patterns
#   4. _spc_try's blob write removed                -> RED, 7 checks: R row 13, the I struct patterns
#   5. _gvk_arm's efi_main exemption removed        -> RED, 1 check: W5 (EFI + efi_main warns)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
[ -x "$CC" ] || { echo "FAIL: kmode_enum_initializer_baked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: kmode_enum_initializer_baked: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
fail=0
rows=0
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
WMSG='in a kernel build the initializer of'

# The image as " xx xx xx ..." (one space before every byte), so a pattern only matches on a
# byte boundary; occurrences of the byte pattern $2 (" xx xx ... ") in file $1.
hexs() { od -An -v -tx1 "$1" | tr -s ' \n' '  ' | sed 's/^ *//; s/^/ /; s/ *$/ /'; }
count() { hexs "$1" | awk -v p="$2" '{ n = 0; s = $0; while ((i = index(s, p)) > 0) { n++; s = substr(s, i + 1) } print n }'; }
nwarn() { grep -c "$WMSG" "$1" || true; }

# ---------------------------------------------------------------------------------------------
# R — run rows (CYRIUS_ELF64_KERNEL=1, x86). `ck` exits with its row number at the first wrong
# value, so a regression names the form. W (a call) is the one initializer left to the replay.
cat > "$T/r.cyr" <<'EOF'
kernel;
enum RE { RA = 0x37; RB = 0x1234; RC = -5; }
struct RP { a; b: i32; c: u8; }
struct RN { x: u16; p: RP; y; }
struct RF { f: f64; n; }
var LIT = 0x29;
var X1 = RA;
var X2 = RE.RB;
var X3 = RA + 1;
var X4 = (RA) | RE.RB;
var X5: u8 = RA;
var X6: i8 = RC;
var X7: u16 = RE.RB;
var X8: u32 = RE.RA | 0x5A170000;
var X9: i32 = RC * 3;
var XA: *i64 = RB;
var XF = FA;
var S1 = RP { RA, RE.RB * 2, 0x99 };
var S2 = RN { 0xBEEF, RC, 0x11223344, 7, 0x123456789 };
var S3 = RF { -1.5, RA };
var L1[1] = { RA, 0x66 };
var L2: u32[2] = { RE.RB, RA | 0x100 };
var R1 = 5;
var R1 = RA;
var R2 = RA;
var R2 = 6;
var R3 = RA;
var R3 = RE.RB;
enum FE { FA = 0x4D; }
enum SE { SA = 3; }
var SH = SA;
var SA = 9;
fn rf(x): i64 { return x; }
var W = rf(RA);
fn ck(got, want, k): i64 { if (got != want) { syscall(60, k); } return 0; }
ck(LIT, 0x29, 1);
ck(X1, 0x37, 2); ck(X2, 0x1234, 3); ck(X3, 0x38, 4); ck(X4, 0x1237, 5); ck(X5, 0x37, 6);
ck(X6, -5, 7); ck(X7, 0x1234, 8); ck(X8, 0x5A170037, 9); ck(X9, -15, 10); ck(XA, 0x1234, 11);
ck(XF, 0x4D, 12);
ck(S1.a, 0x37, 13); ck(S1.b, 0x2468, 14); ck(S1.c, 0x99, 15);
ck(S2.x, 0xBEEF, 16); ck(S2.p.a, -5, 17); ck(S2.p.b, 0x11223344, 18); ck(S2.p.c, 7, 19);
ck(S2.y, 0x123456789, 20); ck(load64(&S3), 0xBFF8000000000000, 21); ck(S3.n, 0x37, 22);
ck(R1, 0x37, 23); ck(R2, 6, 24); ck(R3, 0x1234, 25);
ck(SA, 9, 26); ck(SH, 0, 27);
ck(W, 0, 28);
ck(load8(&L1), 0x37, 29); ck(load8(&L1 + 1), 0x66, 30); ck(L2[0], 0x1234, 31); ck(L2[1], 0x137, 32);
syscall(60, 100);
EOF
rows=$((rows + 1))
if CYRIUS_ELF64_KERNEL=1 "$CC" < "$T/r.cyr" > "$T/r.bin" 2> "$T/r.err" && [ -s "$T/r.bin" ]; then
    chmod +x "$T/r.bin"
    rc=0
    "$T/r.bin" > /dev/null 2>&1 || rc=$?
    [ "$rc" = 100 ] || bad "R: the kernel program read a wrong value at check $rc (1 = the literal control; 2-22 a form; 23-25 a redeclaration order; 26-28 the shadow / the residual; 29-32 an array list's enum elements)"
    # The shadow: SH names the GLOBAL SA (the later declaration hides the enum constant), as the
    # replayed store reads it — so it is not folded (3 would be the pass-1 mistake), stays late and
    # reads 0 in the program (row 27). With the residual call W, the two left late, each named once.
    n=$(nwarn "$T/r.err")
    [ "$n" = 2 ] || bad "R: $n late-initializer warnings, want 2 (SH, W)"
    grep "$WMSG 'W'" "$T/r.err" > /dev/null || bad "R: no warning names W (a call is left to the late replay)"
    grep "$WMSG 'SH'" "$T/r.err" > /dev/null || bad "R: no warning names SH (it names a global, the shadow, not the enum)"
    grep "$WMSG 'X1'\|$WMSG 'S1'\|$WMSG 'R2'" "$T/r.err" > /dev/null && bad "R: a baked initializer is warned"
else
    bad "R: the ELF64 kernel build failed: $(grep -m1 '^error' "$T/r.err")"
fi

# ---------------------------------------------------------------------------------------------
# I — image rows. row <id> <env> <test source> <control source> then pairs: <+N> <pattern>.
row() {
    rows=$((rows + 1))
    id=$1; envs=$2
    printf '%b' "$3" > "$T/$id.cyr"
    printf '%b' "$4" > "$T/$id.ctl.cyr"
    shift 4
    if ! env $envs "$CC" < "$T/$id.cyr" > "$T/$id.bin" 2> "$T/$id.err"; then
        bad "$id: the test does not compile: $(grep -m1 '^error' "$T/$id.err")"; return
    fi
    if ! env $envs "$CC" < "$T/$id.ctl.cyr" > "$T/$id.ctl" 2> "$T/$id.ctl.err"; then
        bad "$id: the control does not compile: $(grep -m1 '^error' "$T/$id.ctl.err")"; return
    fi
    while [ $# -ge 2 ]; do
        ct=$(count "$T/$id.bin" "$2"); cc=$(count "$T/$id.ctl" "$2")
        [ "$ct" = $((cc + $1)) ] || bad "$id: '$2' occurs $ct times in the image, $cc in the control's; want +$1"
        shift 2
    done
}
# A post-statement declaration of the same name is a program-order store: the same immediates in
# the code, nothing baked — the control. Every value is an 8-byte slot pattern no code holds.
DECL='var KX1 = KA;\nvar KX2 = KE.KB;\nvar KX3 = KA + 0x100;\nvar KX4: u32 = KE.KC | 4;\nvar KS = KP { KE.KD, KF };\nvar KN = KQ { 0x77, KG, KH };\nvar KR1 = 5;\nvar KR1 = KI;\nvar KW = kf(KJ);\nvar KT = KP { kf(1), KL };\n'
PRE='enum KE { KA = 0x5A17C0DE0BADF00D; KB = 0x2F3E4D5C6B7A8990; KC = 0x13579BD0; KD = 0x0102030405060708; KF = 0x1112131415161718; KG = 0x2122232425262728; KH = 0x3132333435363738; KI = 0x4142434445464748; KJ = 0x5152535455565758; KL = 0x6162636465666768; }\nstruct KP { a; b; }\nstruct KQ { x; p: KP; }\nfn kf(x): i64 { return x; }\n'
ASM='asm { 0xF4; 0xF4; 0xF4; 0xF4; }\n'
# KW (a call) and KT (a literal with a call leaf) are NOT baked: their constants occur equally often.
row K '' "kernel;\n$PRE$DECL$ASM" "kernel;\n$PRE$ASM$DECL" \
    1 ' 0d f0 ad 0b de c0 17 5a ' 1 ' 90 89 7a 6b 5c 4d 3e 2f ' 1 ' 0d f1 ad 0b de c0 17 5a ' 1 ' d4 9b 57 13 ' \
    1 ' 08 07 06 05 04 03 02 01 ' 1 ' 18 17 16 15 14 13 12 11 ' 1 ' 28 27 26 25 24 23 22 21 ' \
    1 ' 38 37 36 35 34 33 32 31 ' 1 ' 48 47 46 45 44 43 42 41 ' \
    0 ' 58 57 56 55 54 53 52 51 ' 0 ' 68 67 66 65 64 63 62 61 '
[ "$(od -An -tx1 -N5 "$T/K.bin" 2>/dev/null | tr -d ' ')" = 7f454c4601 ] || bad "K: the default kernel build is not the ELF32 multiboot image this row means"
# The kmode redeclaration rows. `var X = 5; var X = A;` bakes A (K's KR1 / KI, +1 above).
# `var X = A; var X = <constant>;`: the constant was baked by pass 1 already, and the superseded
# first entry (its store runs into a sink) must record NOTHING — A is not baked over it (R's row 24
# reads the constant in the program).
row KR '' \
    "kernel;\n$PRE""var KR2 = KA;\nvar KR2 = 0x7172737475767778;\n$ASM" \
    "kernel;\n$PRE$ASM""var KR2 = KA;\nvar KR2 = 0x7172737475767778;\n" \
    0 ' 0d f0 ad 0b de c0 17 5a '
[ -s "$T/KR.bin" ] && { [ "$(count "$T/KR.bin" ' 78 77 76 75 74 73 72 71 ')" -ge 1 ] || bad "KR: the constant redeclaration is not in the image"; }
# Array lists with enum elements — a bare byte list and a typed list (C1's bake, the enum arm of the
# replay's folder). A post-statement list is baked too (C1), so the control declares the arrays with
# NO initializer: the same code, the lists' bytes only in the test.
row KL '' \
    "kernel;\n$PRE""enum KM { KM1 = 0x77; }\nvar KBL[1] = { KM1, 0x66, KE.KC & 0xFF };\nvar KTA: u32[2] = { KE.KC, KM1 | 0x5A170000 };\n$ASM" \
    "kernel;\n$PRE""enum KM { KM1 = 0x77; }\nvar KBL[1];\nvar KTA: u32[2];\n$ASM" \
    1 ' 77 66 d0 00 00 00 00 00 ' 1 ' d0 9b 57 13 77 00 17 5a '
# EFI (gnoboot's build shape: `kernel;` + CYRIUS_TARGET_EFI=1 + efi_main): baked the same way.
row E 'CYRIUS_TARGET_EFI=1' \
    "kernel;\n$PRE""var KX1 = KA;\nvar KS = KP { KE.KD, KF };\n$ASM""fn efi_main(handle, st): i64 { return KX1 + KS.b; }\n" \
    "kernel;\n$PRE$ASM""var KX1 = KA;\nvar KS = KP { KE.KD, KF };\nfn efi_main(handle, st): i64 { return KX1 + KS.b; }\n" \
    1 ' 0d f0 ad 0b de c0 17 5a ' 1 ' 08 07 06 05 04 03 02 01 ' 1 ' 18 17 16 15 14 13 12 11 '
if [ -s "$T/E.bin" ]; then
    [ "$(od -An -tx1 -N2 "$T/E.bin" | tr -d ' ')" = 4d5a ] || bad "E: the CYRIUS_TARGET_EFI=1 build is not an MZ/PE image"
fi

# ---------------------------------------------------------------------------------------------
# W — warning rows. K's own stderr: KW and KT, nothing else (KR1 bakes, KS / KN bake).
rows=$((rows + 1))
if [ -s "$T/K.bin" ]; then
    [ "$(nwarn "$T/K.err")" = 2 ] || bad "W1: $(nwarn "$T/K.err") warnings in the kernel build of K, want 2 (KW, KT)"
    grep "$WMSG 'KW'" "$T/K.err" > /dev/null || bad "W1: no warning names KW (a call)"
    grep "$WMSG 'KT'" "$T/K.err" > /dev/null || bad "W1: no warning names KT (a struct literal with a call leaf)"
else
    bad "W1: K did not build"
fi
# W2: a struct literal with a string leaf, a destructure, a float literal: each left late, each once.
rows=$((rows + 1))
printf 'kernel;\nstruct WP { a; b; }\nfn wp(): i64 { return 1; }\nvar W1 = WP { 1, "s" };\nvar W2, W3 = wp();\nvar W4: f64 = 1.5;\nvar W5 = 0;\nvar W6 = 7;\nasm { 0xF4; }\n' > "$T/w2.cyr"
if "$CC" < "$T/w2.cyr" > "$T/w2.bin" 2> "$T/w2.err"; then
    [ "$(nwarn "$T/w2.err")" = 3 ] || bad "W2: $(nwarn "$T/w2.err") warnings, want 3 (W1 a string leaf, W2 a destructure, W4 a float literal)"
    for n in W1 W2 W4; do grep "$WMSG '$n'" "$T/w2.err" > /dev/null || bad "W2: no warning names $n"; done
else
    bad "W2: the kernel build failed: $(grep -m1 '^error' "$T/w2.err")"
fi
# W3: the same source as a host build — no warning (its replay runs before the program).
rows=$((rows + 1))
sed '1d' "$T/w2.cyr" > "$T/w3.cyr"
"$CC" < "$T/w3.cyr" > "$T/w3.bin" 2> "$T/w3.err" || bad "W3: the host build failed"
[ "$(nwarn "$T/w3.err")" = 0 ] || bad "W3: a host build warned"
# W4: an aarch64 kernel build (CYRIUS_KERNEL=1, the compiler built from this tree) — it replays
# BEFORE its program, so nothing is late and nothing is warned.
rows=$((rows + 1))
if "$CC" < src/main_aarch64.cyr > "$T/cycc_a64" 2> "$T/eb" && [ -s "$T/cycc_a64" ]; then
    chmod +x "$T/cycc_a64"
    if CYRIUS_KERNEL=1 "$T/cycc_a64" < "$T/w3.cyr" > "$T/w4.bin" 2> "$T/w4.err"; then
        [ "$(nwarn "$T/w4.err")" = 0 ] || bad "W4: an aarch64 kernel build warned"
    else
        bad "W4: the aarch64 kernel build failed: $(grep -m1 '^error' "$T/w4.err")"
    fi
else
    bad "W4: cannot build src/main_aarch64.cyr"
fi
# W5: EFI with an efi_main — the late replay runs before efi_main is called: no warning. Without
# one the top-level program is the program, as in any kernel build: warned.
rows=$((rows + 1))
printf 'kernel;\nfn wf(x): i64 { return x; }\nvar WE = wf(5);\nasm { 0xF4; }\nfn efi_main(handle, st): i64 { return WE; }\n' > "$T/w5.cyr"
if CYRIUS_TARGET_EFI=1 "$CC" < "$T/w5.cyr" > "$T/w5.bin" 2> "$T/w5.err"; then
    [ "$(nwarn "$T/w5.err")" = 0 ] || bad "W5: an EFI build with efi_main warned (its replay runs before efi_main)"
else
    bad "W5: the EFI build failed: $(grep -m1 '^error' "$T/w5.err")"
fi
sed 's/fn efi_main(/fn efi_other(/' "$T/w5.cyr" > "$T/w5b.cyr"
if CYRIUS_TARGET_EFI=1 "$CC" < "$T/w5b.cyr" > "$T/w5b.bin" 2> "$T/w5b.err"; then
    [ "$(nwarn "$T/w5b.err")" = 1 ] || bad "W5: an EFI build with no efi_main gave $(nwarn "$T/w5b.err") warnings, want 1"
else
    bad "W5: the EFI build (no efi_main) failed: $(grep -m1 '^error' "$T/w5b.err")"
fi
# W6: an error is reported once, as before, and a failing build warns nothing.
rows=$((rows + 1))
printf 'kernel;\nenum E1 { A = 3; }\nenum E2 { Z = 1; }\nvar X = E2.A;\nvar Y = Nope.A;\nasm { 0xF4; }\n' > "$T/w6.cyr"
if "$CC" < "$T/w6.cyr" > "$T/w6.bin" 2> "$T/w6.err"; then
    bad "W6: a wrong-enum initializer compiled"
else
    [ "$(grep -c '^error' "$T/w6.err")" = 1 ] || bad "W6: $(grep -c '^error' "$T/w6.err") errors, want 1"
    grep "'A' is not a variant of 'E2'" "$T/w6.err" > /dev/null || bad "W6: the wrong-enum message changed"
    [ "$(nwarn "$T/w6.err")" = 0 ] || bad "W6: a failing build warned"
fi

[ "$rows" -ge 11 ] || bad "only $rows rows ran (floor 11)"
if [ "$fail" -ne 0 ]; then
    echo "FAIL: kmode_enum_initializer_baked ($fail checks failed over $rows rows)"
    exit 1
fi
echo "PASS: kmode_enum_initializer_baked ($rows rows)"
exit 0
