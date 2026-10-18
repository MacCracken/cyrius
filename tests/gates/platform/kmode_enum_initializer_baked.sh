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
# _gvk_pre / _spc_try); the store stayed, so the code did not change. 6.7.14 drops a baked SCALAR's
# store where the image already holds its value (_gvk_quiet; issues/2026-10-08-const-init-redundant-
# store-and-unfolded-const-operand.md): its `movabs rax, imm64` is gone from the code, the baked copy
# stays in the data — the D rows count that copy apart from the code form. 6.7.15 drops a baked
# STRUCT literal's stores the same way (_gvs_quiet) — the S rows.
#
# HOW IT IS MEASURED.
#   R  RUN rows. A CYRIUS_ELF64_KERNEL=1 build (agnos's own build mode) is an ELF64 that also runs
#      as a Linux process: its top-level program runs, then the late replay, then the exit. So the
#      program reads exactly what the IMAGE holds — the strongest form of the claim. Every form
#      (scalars, narrow annotations, struct fields, nested structs, an f64 field, an array list's
#      enum elements, the redeclaration orders, a forward enum, the shadow) is checked by value; the exit code names the first wrong
#      one. A literal control (baked since v5.11.64) proves the program does read the image. RF
#      (6.7.10): an f32 field's float literal is baked as its binary32 bits.
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
# MUTATION LEDGER (6.7.10, B7-0 — the baked f32 field; each compiler built from a mutated scratch
# copy of src/, run with CYCC=):
#   0. real tree                                   -> GREEN (13 rows)
#   M1. _spc_leaf's `v = _gai_f32(v)` dropped      -> RED, 5 checks: RF check 1 (1.5 read as the low
#                                                     half of its binary64 bits), the four KF patterns
#   M1b. converted for every float field (`!= 0`)  -> RED, 2 checks: R check 21 and RF check 8 (an f64
#                                                     field narrowed)
# MUTATION LEDGER (6.7.14 — the baked scalar's store dropped):
#   0. real tree                                   -> GREEN (15 rows)
#   D1. _gvk_pre's record removed (`S64(_vgsi_base ..)` dropped in _gvk_one) -> RED, 10 checks: R row 2,
#       three K deltas, every D row (no data copy; the stores come back) and E's data copy
#   D2. _gvk_quiet returning 0 (the stores kept, as 6.6.16 - 6.7.13) -> RED, 6 checks: the three K
#       scalar deltas, the two D code-form rows and E's KX1 delta
# MUTATION LEDGER (6.7.14 — a float scalar's float literal baked, RS / KS / W2;
# issues/archived/2026-10-08-kernel-float-global-init-not-baked.md):
#   0. real tree                                   -> GREEN (17 rows)
#   F0. the compiler before the fix (c0d6d1ba)     -> RED, 7 checks: RS check 1 and its 9 warnings, KS's warning,
#       image bytes and late store, W2's count and W4 named
#   F1. _gvk_flt's f32 narrowing dropped           -> RED, 1 check: RS check 2 (an f32 read as binary64 bits)
#   F2. _gvk_flt's untyped arm dropped             -> RED, 2 checks: RS check 4 and its warning count (4)
# MUTATION LEDGER (6.7.15 — a baked struct literal's stores dropped; issues/2026-10-16-zone-struct-literal-baked-and-
# stored.md; each compiler built from a mutated scratch copy of src/, run with CYCC=):
#   0. real tree                                   -> GREEN (18 rows)
#   Z0. the compiler before the fix (50b9a8817)    -> RED, 11 checks: K's four struct deltas, the S row's four code
#       forms, KF's binary64 1.5, E's two KS deltas
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
# RF (6.7.10, B7-0) — an f32 field's float literal is baked as its BINARY32 bits, zero-extended:
# what the replayed store writes (it rounds, _f32_init_round). It baked the literal's binary64 bits,
# so a kernel read 1.5 as 0 (the low half of 0x3FF8000000000000). Rounded to nearest (0.1 is
# 0x3DCCCCCD), negated, nested, beside an f64 field (still binary64). An integer leaf keeps its bits,
# as the replayed store does (KI: 3, with the warning a host build gives). Since B7-2 (6.7.10) an f32
# field is 4 bytes (packed): the next field starts right after it (checks 3, 13, 15), and a u8 / u16
# after an f32 bakes at offsets 4 / 5 (KU, checks 16-19).
cat > "$T/rf.cyr" <<'EOF'
kernel;
enum RE { RA = 0x37; }
struct KP { g: f32; n; }
struct KM { d: f64; g: f32; n; }
struct KO { a; p: KP; }
struct KU { f: f32; n: u8; m: u16; }
var KS = KP { 1.5, 7 };
var KN = KP { -2.25, 9 };
var KT = KP { 0.1, RA };
var KD = KM { 1.5, 1.5, 5 };
var KQ = KO { 3, 0.1, 4 };
var KI = KP { 3, 6 };
var KV = KU { 1.5, RA, 0xBEEF };
fn ck(got, want, k): i64 { if (got != want) { syscall(60, k); } return 0; }
ck(load32(&KS), 0x3FC00000, 1); ck(KS.n, 7, 2);
ck(load64(&KS + 4), 7, 3);
ck(load32(&KN), 0xC0100000, 4); ck(KN.n, 9, 5);
ck(load32(&KT), 0x3DCCCCCD, 6); ck(KT.n, 0x37, 7);
ck(load64(&KD), 0x3FF8000000000000, 8); ck(load32(&KD + 8), 0x3FC00000, 9); ck(KD.n, 5, 10);
ck(KQ.a, 3, 11); ck(load32(&KQ + 8), 0x3DCCCCCD, 12); ck(load64(&KQ + 12), 4, 13);
ck(load32(&KI), 3, 14); ck(load64(&KI + 4), 6, 15);
ck(load32(&KV), 0x3FC00000, 16); ck(load8(&KV + 4), 0x37, 17); ck(load16(&KV + 5), 0xBEEF, 18);
ck(sizeof(KU), 7, 19);
syscall(60, 100);
EOF
rows=$((rows + 1))
if CYRIUS_ELF64_KERNEL=1 "$CC" < "$T/rf.cyr" > "$T/rf.bin" 2> "$T/rf.err" && [ -s "$T/rf.bin" ]; then
    chmod +x "$T/rf.bin"
    rc=0
    "$T/rf.bin" > /dev/null 2>&1 || rc=$?
    [ "$rc" = 100 ] || bad "RF: the kernel program read a wrong f32 field at check $rc (1-7 an f32 field's binary32 bits; 8-10 beside an f64 field; 11-13 nested; 14-15 an integer leaf; 16-19 a packed { f32; u8; u16 })"
    [ "$(nwarn "$T/rf.err")" = 0 ] || bad "RF: an f32 struct literal is left to the late replay ($(nwarn "$T/rf.err") warnings, want 0)"
else
    bad "RF: the ELF64 kernel build failed: $(grep -m1 '^error' "$T/rf.err")"
fi
# RS (6.7.14) — a float SCALAR's float literal, optionally negated, is baked: an `f64` global and an
# untyped `var K = 1.5;` as their binary64 bits, an `f32` global as its binary32 bits zero-extended (what
# the replayed store writes: it rounds). The integer folder refused the literal, so the store was left
# to the late replay and the kernel's program read 0 (issues/2026-10-08-kernel-float-global-init-not-
# baked.md). A float initializer that is not a literal (a call, arithmetic) stays late and is named.
cat > "$T/rs.cyr" <<'EOF'
kernel;
var G: f64 = 1.5;
var F: f32 = 2.5;
var N: f64 = -1.5;
var K = 1.5;
var KN = -2.5;
var M: f32 = 0.1;
var Z: f32 = -0.0;
fn fk(): f64 { return 1.5; }
var CX: f64 = fk();
var CA: f64 = 1.5 + 1.0;
var H = 7;
fn ck(got, want, k): i64 { if (got != want) { syscall(60, k); } return 0; }
ck(load64(&G), 0x3FF8000000000000, 1);
ck(load64(&F), 0x40200000, 2);
ck(load64(&N), 0xBFF8000000000000, 3);
ck(load64(&K), 0x3FF8000000000000, 4);
ck(load64(&KN), 0xC004000000000000, 5);
ck(load64(&M), 0x3DCCCCCD, 6);
ck(load64(&Z), 0x80000000, 7);
ck(load64(&CX), 0, 8);
ck(load64(&CA), 0, 9);
ck(H, 7, 10);
syscall(60, 100);
EOF
rows=$((rows + 1))
if CYRIUS_ELF64_KERNEL=1 "$CC" < "$T/rs.cyr" > "$T/rs.bin" 2> "$T/rs.err" && [ -s "$T/rs.bin" ]; then
    chmod +x "$T/rs.bin"
    rc=0
    "$T/rs.bin" > /dev/null 2>&1 || rc=$?
    [ "$rc" = 100 ] || bad "RS: the kernel program read a wrong float scalar at check $rc (1 f64, 2 f32 binary32, 3 f64 negated, 4-5 untyped, 6 f32 rounded, 7 f32 -0.0; 8-9 the computed ones read 0, 10 the literal control)"
    [ "$(nwarn "$T/rs.err")" = 2 ] || bad "RS: $(nwarn "$T/rs.err") late-initializer warnings, want 2 (CX a call, CA arithmetic)"
    grep "$WMSG 'CX'" "$T/rs.err" > /dev/null || bad "RS: no warning names CX (a call is left to the late replay)"
    grep "$WMSG 'CA'" "$T/rs.err" > /dev/null || bad "RS: no warning names CA (float arithmetic is left to the late replay)"
else
    bad "RS: the ELF64 kernel build failed: $(grep -m1 '^error' "$T/rs.err")"
fi
# KS (6.7.14) — the filed repro, a default `kernel;` build (the ELF32 multiboot image): no warning, G's
# image bytes are 1.5's binary64 bits with H's 7 after them, and no `movabs rax, 1.5` (the late store)
# is left in the code. Through 6.7.13 G's bytes were zero and the store came after `call kmain`.
rows=$((rows + 1))
printf 'kernel;\nvar G: f64 = 1.5;\nvar H = 7;\nfn kmain(): i64 { return load64(&G) + H; }\nkmain();\n' > "$T/ks.cyr"
if "$CC" < "$T/ks.cyr" > "$T/ks.bin" 2> "$T/ks.err" && [ -s "$T/ks.bin" ]; then
    [ "$(nwarn "$T/ks.err")" = 0 ] || bad "KS: the filed repro warned ($(nwarn "$T/ks.err") late-initializer warnings, want 0)"
    [ "$(count "$T/ks.bin" ' 00 00 00 00 00 00 f8 3f 07 00 00 00 00 00 00 00 ')" = 1 ] || bad "KS: the image does not hold G = 1.5 (00 .. f8 3f) followed by H = 7"
    [ "$(count "$T/ks.bin" ' 48 b8 00 00 00 00 00 00 f8 3f ')" = 0 ] || bad "KS: a late store of 1.5 (movabs rax) is still in the code"
else
    bad "KS: the kernel build of the filed repro failed: $(grep -m1 '^error' "$T/ks.err")"
fi

# ---------------------------------------------------------------------------------------------
# The DATA copies of $2 in file $1: its occurrences minus those that are a `movabs rax, imm64`'s
# immediate (" 48 b8" + the pattern) — the code form a replayed store loads. 6.7.14
dcount() { echo $(( $(count "$1" "$2") - $(count "$1" " 48 b8$2") )); }
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
        [ "$ct" = $((cc + $1)) ] || bad "$id: '$2' occurs $ct times in the image, $cc in the control's; want $1 more"
        shift 2
    done
}
# A post-statement declaration of the same name is a program-order store: the same immediates in
# the code, nothing baked — the control. Every value is an 8-byte slot pattern no code holds.
DECL='var KX1 = KA;\nvar KX2 = KE.KB;\nvar KX3 = KA + 0x100;\nvar KX4: u32 = KE.KC | 4;\nvar KS = KP { KE.KD, KF };\nvar KN = KQ { 0x77, KG, KH };\nvar KR1 = 5;\nvar KR1 = KI;\nvar KW = kf(KJ);\nvar KT = KP { kf(1), KL };\n'
PRE='enum KE { KA = 0x5A17C0DE0BADF00D; KB = 0x2F3E4D5C6B7A8990; KC = 0x13579BD0; KD = 0x0102030405060708; KF = 0x1112131415161718; KG = 0x2122232425262728; KH = 0x3132333435363738; KI = 0x4142434445464748; KJ = 0x5152535455565758; KL = 0x6162636465666768; }\nstruct KP { a; b; }\nstruct KQ { x; p: KP; }\nfn kf(x): i64 { return x; }\n'
ASM='asm { 0xF4; 0xF4; 0xF4; 0xF4; }\n'
# KW (a call) and KT (a literal with a call leaf) are NOT baked: their constants occur equally often.
# 6.7.14: a baked scalar's replayed store is dropped — KX1's and KX3's (`KA + 0x100` loads KA) take
# KA's code form twice (-1 over the baked copy), KX2's (KB) and KR1's (KI) once (+0); the D rows below
# count the data copies.
# 6.7.15: a baked struct literal's stores are dropped too (issues/2026-10-16-zone-struct-literal-baked-and-stored.md) —
# KS's (KD, KF) and KN's (KG, KH) leaves keep their data copy and lose their code form: +0 (through 6.7.14 +1, the
# stores' `movabs rax, imm64` beside the bake); the S rows below count the two forms apart.
row K '' "kernel;\n$PRE$DECL$ASM" "kernel;\n$PRE$ASM$DECL" \
    -1 ' 0d f0 ad 0b de c0 17 5a ' 0 ' 90 89 7a 6b 5c 4d 3e 2f ' 1 ' 0d f1 ad 0b de c0 17 5a ' 1 ' d4 9b 57 13 ' \
    0 ' 08 07 06 05 04 03 02 01 ' 0 ' 18 17 16 15 14 13 12 11 ' 0 ' 28 27 26 25 24 23 22 21 ' \
    0 ' 38 37 36 35 34 33 32 31 ' 0 ' 48 47 46 45 44 43 42 41 ' \
    0 ' 58 57 56 55 54 53 52 51 ' 0 ' 68 67 66 65 64 63 62 61 '
# D (6.7.14) — the baked scalars' DATA copy: one more than the control's (which computes them in its
# code), and no store of them left in the test's code.
rows=$((rows + 1))
if [ -s "$T/K.bin" ] && [ -s "$T/K.ctl" ]; then
    for p in ' 0d f0 ad 0b de c0 17 5a ' ' 90 89 7a 6b 5c 4d 3e 2f ' ' 48 47 46 45 44 43 42 41 '; do
        dt=$(dcount "$T/K.bin" "$p"); dc=$(dcount "$T/K.ctl" "$p")
        [ "$dt" = $((dc + 1)) ] || bad "D: '$p' has $dt data copies in the image, $dc in the control's; want +1 (the bake)"
    done
    # KX2 / KR1 are stored by nothing now: their value's code form is the control's minus one each.
    for p in ' 90 89 7a 6b 5c 4d 3e 2f ' ' 48 47 46 45 44 43 42 41 '; do
        ct=$(count "$T/K.bin" " 48 b8$p"); cc=$(count "$T/K.ctl" " 48 b8$p")
        [ "$ct" = $((cc - 1)) ] || bad "D: '$p' is loaded $ct times in the image's code, $cc in the control's; want -1 (no replayed store)"
    done
fi
# S (6.7.15) — the baked struct literals KS / KN: each leaf's DATA copy is one more than the control's, and its code
# form (the replayed store's `movabs rax, imm64`) one less: no store of the literal is left in the test's code.
rows=$((rows + 1))
if [ -s "$T/K.bin" ] && [ -s "$T/K.ctl" ]; then
    for p in ' 08 07 06 05 04 03 02 01 ' ' 18 17 16 15 14 13 12 11 ' ' 28 27 26 25 24 23 22 21 ' ' 38 37 36 35 34 33 32 31 '; do
        dt=$(dcount "$T/K.bin" "$p"); dc=$(dcount "$T/K.ctl" "$p")
        [ "$dt" = $((dc + 1)) ] || bad "S: '$p' has $dt data copies in the image, $dc in the control's; want +1 (the bake)"
        ct=$(count "$T/K.bin" " 48 b8$p"); cc=$(count "$T/K.ctl" " 48 b8$p")
        [ "$ct" = $((cc - 1)) ] || bad "S: '$p' is loaded $ct times in the image's code, $cc in the control's; want -1 (no replayed store)"
    done
fi
[ "$(od -An -tx1 -N5 "$T/K.bin" 2>/dev/null | tr -d ' ')" = 7f454c4601 ] || bad "K: the default kernel build is not the ELF32 multiboot image this row means"
# The kmode redeclaration rows. `var X = 5; var X = A;` bakes A (K's KR1 / KI, +1 above).
# `var X = A; var X = <constant>;`: the constant was baked by pass 1 already, and the superseded
# first entry must record NOTHING — A is not baked over it (R's row 24 reads the constant in the
# program): A's data copies are the control's. ⛔ 6.7.15 (the user's decision D2 (a), 2026-10-18): an
# earlier constant declaration leaves no startup store, so the entry's store into a sink (A's code form,
# the control's one store) is gone too: -1 (through 6.7.14 +0).
row KR '' \
    "kernel;\n$PRE""var KR2 = KA;\nvar KR2 = 0x7172737475767778;\n$ASM" \
    "kernel;\n$PRE$ASM""var KR2 = KA;\nvar KR2 = 0x7172737475767778;\n" \
    -1 ' 0d f0 ad 0b de c0 17 5a '
[ -s "$T/KR.bin" ] && { [ "$(count "$T/KR.bin" ' 78 77 76 75 74 73 72 71 ')" -ge 1 ] || bad "KR: the constant redeclaration is not in the image"; }
if [ -s "$T/KR.bin" ] && [ -s "$T/KR.ctl" ]; then
    dt=$(dcount "$T/KR.bin" ' 0d f0 ad 0b de c0 17 5a '); dc=$(dcount "$T/KR.ctl" ' 0d f0 ad 0b de c0 17 5a ')
    [ "$dt" = "$dc" ] || bad "KR: A has $dt data copies in the image, $dc in the control's: the superseded entry was baked"
fi
# Array lists with enum elements — a bare byte list and a typed list (C1's bake, the enum arm of the
# replay's folder). A post-statement list is baked too (C1), so the control declares the arrays with
# NO initializer: the same code, the lists' bytes only in the test.
row KL '' \
    "kernel;\n$PRE""enum KM { KM1 = 0x77; }\nvar KBL[1] = { KM1, 0x66, KE.KC & 0xFF };\nvar KTA: u32[2] = { KE.KC, KM1 | 0x5A170000 };\n$ASM" \
    "kernel;\n$PRE""enum KM { KM1 = 0x77; }\nvar KBL[1];\nvar KTA: u32[2];\n$ASM" \
    1 ' 77 66 d0 00 00 00 00 00 ' 1 ' d0 9b 57 13 77 00 17 5a '
# KF (6.7.10, B7-0): the ELF32 image holds an f32 field's binary32 bits (1.5 = 3fc00000, -2.25 =
# c0100000), once more than the control; the literals' binary64 bits (the replayed store's
# immediates) are not baked. 6.7.15: the test's stores are dropped, so 1.5's binary64 bits (the
# control's `movabs rax`) occur once less (-1; through 6.7.14 equally often); -2.25's never occur
# (the control loads 2.25 and negates it).
row KF '' \
    "kernel;\n$PRE""struct KG { g: f32; n; }\nvar KF1 = KG { 1.5, KE.KL };\nvar KF2 = KG { -2.25, KE.KJ };\n$ASM" \
    "kernel;\n$PRE""struct KG { g: f32; n; }\n$ASM""var KF1 = KG { 1.5, KE.KL };\nvar KF2 = KG { -2.25, KE.KJ };\n" \
    1 ' 00 00 c0 3f ' 1 ' 00 00 10 c0 ' -1 ' 00 00 00 00 00 00 f8 3f ' 0 ' 00 00 00 00 00 00 02 c0 '
# KU (6.7.10, B7-2): a packed { f32; u8; u16 } bakes as its 7 contiguous bytes — 1.5's binary32 bits,
# the u8, the u16 — once more than the control (through 6.7.9 each field took an 8-byte slot).
row KU '' \
    "kernel;\n$PRE""struct KZ { f: f32; n: u8; m: u16; }\nvar KU1 = KZ { 1.5, 0x37, 0xBEEF };\n$ASM" \
    "kernel;\n$PRE""struct KZ { f: f32; n: u8; m: u16; }\n$ASM""var KU1 = KZ { 1.5, 0x37, 0xBEEF };\n" \
    1 ' 00 00 c0 3f 37 ef be '
# EFI (gnoboot's build shape: `kernel;` + CYRIUS_TARGET_EFI=1 + efi_main): baked the same way.
row E 'CYRIUS_TARGET_EFI=1' \
    "kernel;\n$PRE""var KX1 = KA;\nvar KS = KP { KE.KD, KF };\n$ASM""fn efi_main(handle, st): i64 { return KX1 + KS.b; }\n" \
    "kernel;\n$PRE$ASM""var KX1 = KA;\nvar KS = KP { KE.KD, KF };\nfn efi_main(handle, st): i64 { return KX1 + KS.b; }\n" \
    0 ' 0d f0 ad 0b de c0 17 5a ' 0 ' 08 07 06 05 04 03 02 01 ' 0 ' 18 17 16 15 14 13 12 11 '
if [ -s "$T/E.bin" ]; then
    [ "$(od -An -tx1 -N2 "$T/E.bin" | tr -d ' ')" = 4d5a ] || bad "E: the CYRIUS_TARGET_EFI=1 build is not an MZ/PE image"
    # 6.7.14: KX1's store dropped (+0 above) — its baked copy is in the data. 6.7.15: KS's stores too.
    for p in ' 0d f0 ad 0b de c0 17 5a ' ' 08 07 06 05 04 03 02 01 ' ' 18 17 16 15 14 13 12 11 '; do
        dt=$(dcount "$T/E.bin" "$p"); dc=$(dcount "$T/E.ctl" "$p")
        [ "$dt" = $((dc + 1)) ] || bad "E: '$p' has $dt data copies in the image, $dc in the control's; want +1 (the bake)"
    done
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
# W2: a struct literal with a string leaf, a destructure: each left late, each once. A float literal
# (W4) is baked since 6.7.14 (RS / KS above) and named no more.
# (6.6.17: `wp` returns the PAIR the destructure binds — a one-value fn there is now refused.)
rows=$((rows + 1))
printf 'kernel;\nstruct WP { a; b; }\nfn wp(): (i64, i64) { return (1, 2); }\nvar W1 = WP { 1, "s" };\nvar W2, W3 = wp();\nvar W4: f64 = 1.5;\nvar W5 = 0;\nvar W6 = 7;\nasm { 0xF4; }\n' > "$T/w2.cyr"
if "$CC" < "$T/w2.cyr" > "$T/w2.bin" 2> "$T/w2.err"; then
    [ "$(nwarn "$T/w2.err")" = 2 ] || bad "W2: $(nwarn "$T/w2.err") warnings, want 2 (W1 a string leaf, W2 a destructure)"
    for n in W1 W2; do grep "$WMSG '$n'" "$T/w2.err" > /dev/null || bad "W2: no warning names $n"; done
    grep "$WMSG 'W4'" "$T/w2.err" > /dev/null && bad "W2: the float literal W4 is named (it is baked since 6.7.14)"
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

[ "$rows" -ge 16 ] || bad "only $rows rows ran (floor 16)"
if [ "$fail" -ne 0 ]; then
    echo "FAIL: kmode_enum_initializer_baked ($fail checks failed over $rows rows)"
    exit 1
fi
echo "PASS: kmode_enum_initializer_baked ($rows rows)"
exit 0
