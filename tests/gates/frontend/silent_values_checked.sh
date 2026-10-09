#!/bin/sh
# tests/gates/frontend/silent_values_checked.sh — 6.7.6 (Break 1, lane D)
#
# SILENT WRONG VALUES (the user's decisions, 2026-10-08 — roadmap "Break 1 decisions"):
#   F  `var x: f32 = <an f64 value>` ROUNDS to f32 (a local, a global in either zone, a for-init),
#      as a 6.7.4 `f32[N]` list element does; it stored the f64 bits, which read as 0.0. The
#      runtime half is tests/tcyr/crossos/f32_scalar_init_rounds.tcyr (A rows).
#   I  CYRIUS_IR=3 keeps the x86 f32 conversions (`f32_from`, `f32_to`, and the initializer's): their
#      raw bytes were not IR-recorded, so the opt-in pass forwarded rax across them (a prerequisite
#      of F under IR=3; pre-existing since the builtins landed).
#   P  a top-level `var v = pair_fn();` is REFUSED by name, with the fn-body rule's wording (v6.5.67):
#      it kept the tag and dropped the payload, silently — in the declaration zone (the replay's
#      `_gvi_expr`) and after the first statement (PARSE_VAR) alike; the destructure still binds.
#   R  a name DECLARED an integer (a local, a parameter — #inline too —, a closure capture, a global)
#      as the whole first argument routes to the base's `_int` overload: `println(n)` with `n: i64`
#      ran println's cstring body over 42 (rc 139). The runtime half is
#      tests/tcyr/crossos/int_name_routes_int_overload.tcyr (A rows).
#   O  `OP=` on a SIMD vector (a local or parameter), a TYPED array (`var a: T[N]`, any T, local, global
#      or static) or a slice is REFUSED by name, as 6.7.5 refused it on a struct: each integer-operated
#      on the first word (`a += 8` added to a[0], `s += 1` to `.ptr`), as a statement and a for step.
#      The element forms and the slice fields keep working (a bare `var b[N]`: B, below).
#   U  (D2, the second round) u128 `+` and `-` CARRY and BORROW across all 128 bits in both spellings
#      (`b = b + x`, `b += x`), a u128 or an integer on either side, unary minus `0 - x`; a u128
#      declaration takes its whole value (a local stored it into BOTH halves); every OTHER operator
#      with a u128 operand — `* / % << >> >>> & | ^ ~`, `*% *| *? +| +? -| -?`, and their OP= — is
#      REFUSED by name (each computed on the low word). Runtime: u128_add_sub_carry.tcyr and
#      u128_compound_matches_long_form.tcyr (A rows; lane D's D-7 pin, now carrying).
#   C  (D3, the third round) a u128 COMPARISON — `== != < <= > >=` — compares all 128 bits, UNSIGNED,
#      against a u128 or a zero-extended integer on either side, wherever a comparison is parsed (a
#      condition, an `&&` / `||` operand, a value, an if-expression condition, a chained `a < b < c`),
#      at fn and top level: it compared the low words, signed. Runtime: u128_compare_all_bits.tcyr
#      (A rows).
#   T  (D4, the user's decision 2026-10-08: a truth test IS a comparison with zero) a u128 TRUTH TEST
#      reads all 128 bits — a bare `if` / `elif` / `while` / `do .. while` / `for` / if-expression
#      condition, an `&&` / `||` operand, `!b` (`b == 0`) — and a `match b` / `switch (b)` on a u128
#      subject compares it on all 128 bits, each arm / case value zero-extended (a u128 arm as it is),
#      the subject read once: each read the low word (2^64 was false, `!b` 1, the 0 arm taken). Fn and
#      top level. Runtime: u128_compare_all_bits.tcyr's T rows (A rows).
#   S  (D3) a PLAIN u128 assignment takes the whole value, as the declaration does: `b = c` (a u128
#      variable or a `+` / `-` result) copies all 16 bytes and `b = 5` zero-extends — local and global,
#      statement, for step and top level. Only a `+` / `-` result did; `b = c` / `b = 5` stored the low
#      word and kept the old high word. Runtime: u128_assign_whole_value.tcyr (A rows).
#   W  (D2) EVERY write of an f64 value into an `f32` rounds, as F's initializer does: an assignment
#      (statement and for step, local and global), a field store, a struct-literal field and an
#      argument to an `f32` parameter. Runtime: f32_writes_round.tcyr (A rows).
#   B  (D2) a whole-array assignment `a = v` to a TYPED array (local, global, static; any element) and
#      `OP=` on a BARE `var b[N]` (local, global, static, `stack var`) are REFUSED by name: each stored
#      into the first word. A bare `b = v` and every element form keep working (not decided).
#   A  ANTI-VACUOUS: each crossos tcyr on x86_64 (default, CYRIUS_IR=3, CYRIUS_DCE=1) and with
#      compilers built from this tree on aarch64 (qemu), cx (cxvm) and PE (wine, a private prefix),
#      with its full assertion count.
#
# MUTATION LEDGER (scratch trees, each rebuilt with the one change, run as CYCC=<mutant>; 2026-10-08):
#   M1 `_f32_init_round` never narrows                    -> RED I1 I2 and AF on every leg (25 rows)
#   M2 `_gvi_store` without the rounding (decl zone)      -> RED AF on every leg (F1-F9: 11 rows)
#   M3 `_decl_float_init` without the rounding (PARSE_VAR) -> RED I1 I2 and AF (L/V/A/R/T: 14 rows)
#   M4 EF32_FROM not IR-recorded                          -> RED I1 and AF under CYRIUS_IR=3 (V1)
#   M4b EF32_TO not IR-recorded                           -> RED I1 and AF under CYRIUS_IR=3 (A1)
#   M5 `_refuse_single_pair_bind` gated on GINFN again    -> RED P1-P5 (each BUILDS); P6 green
#   M6 the replay's `_gvi_pair_bind` not called           -> RED P1 P3 P4 (the declaration zone)
#   M7 `_od_arg_kind` never routes a name                 -> RED AR on every leg (rc 139 at P1)
#   M8 `_inl_param_marks` not called                      -> RED AR R11 on every leg
#   M9 `_od_arg_kind` without the capture arm             -> RED AR R16 on every leg
#   M10 `_gv_last_marks` without SVINTD                   -> RED AR R12 R13 (and the crash at P3)
#   M11 `_bx_ptype` never answers 2 (no parameter mark)   -> RED AR R7 R8 R11
#   M14 `_asg_wide_refused` never refuses                 -> RED O1-O10 (each BUILDS)
#   M15 no 0x80 typed mark in the array descriptor        -> RED O4 O5 (f64 / struct elements BUILD)
#   M16 `_bx_pcmpe_arg` reading `== 0` again (2 is a bool) -> RED every A leg (print_num's `n: i64`
#      refused as "not a bool"; cx's compiler does not build)
#   (M12 / M13 — the pkgver scan — are in pkgver_visible_in_includes.sh's ledger.)
# D2 (the follow-up lane, 2026-10-08; each a scratch tree with the one change, its compiler built by
# build/cycc, this gate run FROM the scratch tree so the aarch64 / cx / PE compilers carry the mutant;
# "on every leg" = x86 default / IR=3 / DCE, aarch64, cx, PE):
#   M17 `_w128_pexpr` never takes a u128 `+` / `-`              -> RED U12 U31 U32, AU and AU2 on every leg
#   M18 `_ptr_add` / `_ptr_sub` without the u128 hook           -> RED AU2 on every leg (U9 U10 U13 U14:
#       an integer on the left)
#   M19 `_w128_store` never stores                              -> RED U31 U32, AU and AU2 on every leg
#   M20 `_w16_local_init` stores the value into both halves     -> RED U33, AU2 on every leg (U23-U26)
#   M21 `_gvi_store` without its u128 arm                       -> RED AU2 on every leg (U29 U30 U33)
#   M22 `_w128_lchk` never refuses                              -> RED U1 U3-U10 U12-U16 (each BUILDS; U10
#       is then reported at its right operand)
#   M23 `_w128_rchk` never refuses                              -> RED U2 U11 U17
#   M24 `_w128_cop` refuses nothing                             -> RED U20-U28
#   M25 x86 EW128_ACCI `adc` emitted as `add`                   -> RED U31, AU and AU2 on x86 and PE only
#   M26 `_neg_int` without its u128 arm                         -> RED AU2 on every leg (U15)
#   M27 `_w128_addr` without the IR_RAW_EMIT mark               -> RED AU2 under CYRIUS_IR=3 (U26)
#   M28 `_asg_plain_chk` without the f32 rounding               -> RED W1 W2, AW on every leg (W1-W6 W9 W10)
#   M29 `_ifs_bx` / `_spi_leaf_check` without it                -> RED W1 W2, AW on every leg (W11-W14 W16)
#   M30 `_bx_pcmpe_arg` without the f32 arm                     -> RED W1 W2, AW on every leg (W17-W20)
#   M31 `_bx_pscan` without the f32 mark (pass 1)               -> RED AW on every leg (W19, a forward call)
#   M32 `_asg_plain_chk` without the array refusal              -> RED B1-B7 (each BUILDS)
#   M33 `_arr_named_marks` without SLBARR                       -> RED B11 B16
#   M34 `_arr_gsgn` returning 0 for a bare array again          -> RED B12 B13 B15
#   M35 `_stk_named_marks` without SLBARR                       -> RED B14
# D3 (the third round, 2026-10-08; the same method — a scratch tree per mutation, its compiler built
# by build/cycc, this gate run FROM it with CYCC=<mutant>):
#   M36 `_w128_cmp` never takes a u128 on the left              -> RED C1 C2 C3, AU2 (U22), AC and AS
#       (S12) on every leg
#   M37 `_w128_cmp_r` never takes a u128 on the right           -> RED AC on every leg (C23; C36 C37,
#       the chain's hook is the same fn)
#   M38 ECONDCMP's chain without its u128 hook                  -> RED AC on every leg (C36 C37)
#   M39 x86 EW128_CMP: `>` / `<=` without the operand swap      -> RED C1 C2 C3, AC on x86 and PE only
#       (C5 C7 C10 C11 C16 C22 C30 C32 C35 C41 C44)
#   M40 aarch64 EW128_CMP: `sbcs` (the high words) as `subs`    -> RED AC on aarch64 only (C27 C39)
#   M41 cx EW128_CMP without the 2^63 bias (a signed compare)   -> RED AC on cx only (C11 C12 C13 ...)
#   M42 `_w128_cmp` reads a u128 LOCAL on the left in place     -> RED AC on every leg (C41: the right
#       side ran first)
#   M43 `_w128_store` takes only a `+` / `-` result (D2's)      -> RED U35, S1 S2 S3, AS on every leg
#   (M44 x86 EW128_CMP without its IR_RAW_EMIT mark stayed GREEN, the IR=3 legs included: the `lea`
#   before it is already marked opaque. The mark is kept, as EW128_ACCM's.)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=silent_values_checked
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
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
cd "$ROOT"
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; timeout 60 env ${2:-} "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
exits() {   # <name> <want> <what> <source> [ENV=V]: builds (under ENV), runs, exits <want>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1" "${5:-}"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
refused() {   # <name> <message fragment> <what> <source>: refused once, with the fragment
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$rc" -eq 124 ]; then bad "$3: the compiler did not finish (timeout)"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    else ok "$3: refused once"; fi
}

# ── P: a `: stack` pair bound to ONE global is refused, as in a fn body ─────────────────────────
PR='include "lib/syscalls.cyr"\nenum R: stack { ROk(v); RErr(e); }\nfn mk(n) { if (n == 0) { return RErr(99); } return ROk(n); }\nfn mkg<T>(n: T) { return ROk(n); }\nstruct Pt { x; }\nfn Pt_mk(self: Pt, n) { return ROk(n); }\nfn one(): i64 { return 7; }\n'
BB="a \`: stack\` enum returns two values — bind both: \`var tag, val = f();\`"
refused p01 "$BB" "P1: \`var v = mk(42);\` in the declaration zone" "${PR}var v = mk(42);\nsyscall(60, v);\n"
refused p02 "$BB" "P2: ... after the first top-level statement" "${PR}syscall(1, 1, \"\", 0);\nvar v = mk(42);\nsyscall(60, v);\n"
refused p03 "$BB" "P3: ... annotated \`var v: i64 = mk(42);\`" "${PR}var v: i64 = mk(42);\nsyscall(60, v);\n"
refused p04 "$BB" "P4: ... the generic spelling \`mkg<i64>(..)\`" "${PR}var v = mkg<i64>(42);\nsyscall(60, v);\n"
refused p05 "$BB" "P5: ... the method spelling \`p.mk(..)\`" "${PR}var p = Pt { 1 };\nsyscall(1, 1, \"\", 0);\nvar v = p.mk(42);\nsyscall(60, v);\n"
refused p06 "$BB" "P6: inside a fn (the v6.5.67 rule, unchanged)" "${PR}fn main(): i64 { var v = mk(42); return v; }\nsyscall(60, main());\n"
exits p07 42 "P7: the top-level destructure binds both (both zones)" "${PR}var t, v = mk(42);\nsyscall(1, 1, \"\", 0);\nvar t2, v2 = mk(0);\nvar o = one();\nsyscall(60, v + t + (t2 - 1) * 100 + (v2 - 99) + o - 7);\n"
exits p08 7 "P8: a one-value global from a plain fn is untouched" "${PR}var o = one();\nsyscall(1, 1, \"\", 0);\nvar o2 = one();\nsyscall(60, o * o2 / 7);\n"

# ── O: `OP=` on a vector, a typed array or a slice is refused by name ──────────────────────────
OS='struct P { x; y; }\nvar GA: i64[4];\n'
OV="compound assignment to vector"
OA="compound assignment to array"
OL="compound assignment to slice"
refused o01 "$OV 'v' is refused - a vector value is not an integer or a float" "O1: \`v += 1\` on an i64v2 local" "${OS}fn main(): i64 { var v: i64v2 = 0; v += 1; return 0; }\nsyscall(60, main());\n"
refused o02 "$OV 'v'" "O2: ... on an f64v2 parameter" "${OS}fn f(v: f64v2): i64 { v -= 1.0; return 0; }\nsyscall(60, 0);\n"
refused o03 "$OA 'a' is refused - an array is not an integer or a float (index an element: \`a[i] += b\`)" "O3: \`a += 8\` on a \`var a: i64[4]\` local" "${OS}fn main(): i64 { var a: i64[4]; a += 8; return 0; }\nsyscall(60, main());\n"
refused o04 "$OA 'fa'" "O4: ... an f64[2] local" "${OS}fn main(): i64 { var fa: f64[2]; fa += 1.5; return 0; }\nsyscall(60, main());\n"
refused o05 "$OA 'pa'" "O5: ... a struct-element array" "${OS}fn main(): i64 { var pa: P[2]; pa |= 1; return 0; }\nsyscall(60, main());\n"
refused o06 "$OA 'GA'" "O6: ... a typed-array global, at top level" "${OS}GA += 8;\nsyscall(60, 0);\n"
refused o07 "$OA 'a'" "O7: ... a for step" "${OS}fn main(): i64 { var a: i64[4]; var i = 0; for (i = 0; i < 2; a += 8) { i = i + 1; } return 0; }\nsyscall(60, main());\n"
refused o08 "$OA 'big'" "O8: ... an array over the frame budget (static storage)" "${OS}fn main(): i64 { var big: u8[130000]; big >>>= 1; return 0; }\nsyscall(60, main());\n"
refused o09 "$OL 's' is refused - a slice is not an integer or a float (step a field: \`s.ptr += n\`, \`s.len -= n\`)" "O9: \`s += 1\` on a slice local" "${OS}fn main(): i64 { var s: [u8] = 0; s += 1; return 0; }\nsyscall(60, main());\n"
printf '%b' "${OS}fn main(): i64 { var a: i64[4]; a += 1; var s: [u8] = 0; s -= 1; return 0; }\nsyscall(60, main());\n" > "$T/o10.cyr"
build o10
if [ "$(grep -c '^error' "$T/o10.err")" -eq 2 ]; then ok "O10: an array then a slice: both reported (the parse stays in sync)"
else bad "O10: want 2 error lines: $(grep '^error' "$T/o10.err" | tr '\n' '|')"; fi
exits o11 21 "O11: the element forms and the slice fields still work" "${OS}fn main(): i64 { var a: i64[4]; a[0] = 1; a[0] += 8; var d: u8[4]; var s: [u8] = 0; store64(&s, &d); store64(&s + 8, 4); s.ptr += 1; s.len -= 2; return a[0] + (s.ptr - &d) * 10 + s.len; }\nsyscall(60, main());\n"
# (O12 asserted that a bare `var b[16]` kept its OP=; D2 refuses it — the B rows below.)

# ── U (D2): u128 + / - carry; every other u128 operator is refused by name ─────────────────────
UR='var G: u128 = 0;\nfn main(): i64 {\n    var b: u128 = 0;\n    var c: u128 = 0;\n    var x = 0;\n'
UE='    return 0;\n}\nsyscall(60, main());\n'
UB="is refused - it is not implemented for u128 yet (only \`+\` and \`-\` are; lib/bayan.cyr's bayan_u128_* helpers cover the rest)"
UC="is refused - it is not implemented for u128 yet (only \`+=\` and \`-=\` are"
refused u01 "\`*\` on u128 'b' $UB" "U1: \`b * 2\`" "${UR}    x = b * 2;\n${UE}"
refused u02 "\`*\` on u128 'b' $UB" "U2: \`2 * b\` (the right operand)" "${UR}    x = 2 * b;\n${UE}"
refused u03 "\`/\` on u128 'b'" "U3: \`b / 3\`" "${UR}    x = b / 3;\n${UE}"
refused u04 "\`%\` on u128 'b'" "U4: \`b % 3\`" "${UR}    x = b % 3;\n${UE}"
refused u05 "\`<<\` on u128 'b'" "U5: \`b << 1\`" "${UR}    x = b << 1;\n${UE}"
refused u06 "\`>>\` on u128 'b'" "U6: \`b >> 1\`" "${UR}    x = b >> 1;\n${UE}"
refused u07 "\`>>>\` on u128 'b'" "U7: \`b >>> 1\`" "${UR}    x = b >>> 1;\n${UE}"
refused u08 "\`&\` on u128 'b'" "U8: \`b & 1\`" "${UR}    x = b & 1;\n${UE}"
refused u09 "\`|\` on u128 'b'" "U9: \`b | 1\`" "${UR}    x = b | 1;\n${UE}"
refused u10 "\`^\` on u128 'b'" "U10: \`b ^ c\` (reported at its left operand)" "${UR}    x = b ^ c;\n${UE}"
refused u11 "\`~\` on u128 'b'" "U11: \`~b\`" "${UR}    x = ~b;\n${UE}"
refused u12 "\`*\` on a u128 value $UB" "U12: \`(b + 1) * 2\` (a computed u128)" "${UR}    x = (b + 1) * 2;\n${UE}"
refused u13 "\`*%\` on u128 'b'" "U13: \`b *% 2\`" "${UR}    x = b *% 2;\n${UE}"
refused u14 "\`+|\` on u128 'b'" "U14: \`b +| 1\` (saturating)" "include \"lib/overflow.cyr\"\n${UR}    x = b +| 1;\n${UE}"
refused u15 "\`-?\` on u128 'b'" "U15: \`b -? 1\` (checked)" "include \"lib/overflow.cyr\"\n${UR}    x = b -? 1;\n${UE}"
refused u16 "\`*\` on u128 'G'" "U16: a u128 global, at top level" "var G: u128 = 0;\nvar x = G * 2;\nsyscall(60, x);\n"
refused u17 "\`&\` on u128 'c'" "U17: \`x & c\` (the right operand of \`&\`)" "${UR}    x = x & c;\n${UE}"
refused u20 "compound assignment \`*=\` to u128 'b' $UC" "U20: \`b *= 2\`" "${UR}    b *= 2;\n${UE}"
refused u21 "compound assignment \`/=\` to u128 'b'" "U21: \`b /= 2\`" "${UR}    b /= 2;\n${UE}"
refused u22 "compound assignment \`%=\` to u128 'b'" "U22: \`b %= 2\`" "${UR}    b %= 2;\n${UE}"
refused u23 "compound assignment \`<<=\` to u128 'b'" "U23: \`b <<= 1\`" "${UR}    b <<= 1;\n${UE}"
refused u24 "compound assignment \`>>=\` to u128 'b'" "U24: \`b >>= 1\`" "${UR}    b >>= 1;\n${UE}"
refused u25 "compound assignment \`>>>=\` to u128 'b'" "U25: \`b >>>= 1\`" "${UR}    b >>>= 1;\n${UE}"
refused u26 "compound assignment \`&=\` to u128 'b'" "U26: \`b &= 1\`" "${UR}    b &= 1;\n${UE}"
refused u27 "compound assignment \`^=\` to u128 'G'" "U27: on a u128 global, at top level" "var G: u128 = 0;\nG ^= 1;\nsyscall(60, 0);\n"
refused u28 "compound assignment \`|=\` to u128 'b'" "U28: a for step \`b |= 1\`" "${UR}    var i = 0;\n    for (i = 0; i < 1; b |= 1) { i = i + 1; }\n${UE}"
# The filed repros (lane D's /home/macro/.cache/c6/b1_D/u/u5-u7.cyr): exit lo * 10 + hi.
exits u31 1 "U31: \`b = b + 1\` on 2^64 - 1 carries (u5.cyr: exited 0)" "fn main(): i64 {\n    var b: u128 = 0;\n    store64(&b, 0xFFFFFFFFFFFFFFFF); store64(&b + 8, 0);\n    b = b + 1;\n    return load64(&b) * 10 + load64(&b + 8);\n}\nsyscall(60, main());\n"
exits u32 65 "U32: \`b = b + c\`, both u128 (u6.cyr: exited 63)" "fn main(): i64 {\n    var b: u128 = 0;\n    store64(&b, 7); store64(&b + 8, 3);\n    var c: u128 = 0;\n    store64(&c, 0xFFFFFFFFFFFFFFFF); store64(&c + 8, 1);\n    b = b + c;\n    return load64(&b) * 10 + load64(&b + 8);\n}\nsyscall(60, main());\n"
exits u33 0 "U33: \`var a: u128 = 5\` has a high word of 0, as the global (u7.cyr: exited 50)" "var G: u128 = 5;\nfn main(): i64 {\n    var a: u128 = 5;\n    return load64(&a + 8) * 10 + load64(&G + 8);\n}\nsyscall(60, main());\n"
exits u34 7 "U34: not refused — an address, a deref through a \`*u128\` and an argument (the low word), a compare (all 128 bits)" "fn f(n): i64 { return n; }\nfn main(): i64 {\n    var b: u128 = 0;\n    store64(&b, 7);\n    var p = &b;\n    var x = *p;\n    if (b == 7) { x = x * 1; }\n    return f(b) + x - 7;\n}\nsyscall(60, main());\n"
exits u35 10 "U35: \`b = c\` takes c's whole value (D3, S below; it kept b's high word: exited 13)" "fn main(): i64 {\n    var b: u128 = 0;\n    store64(&b + 8, 3);\n    var c: u128 = 1;\n    b = c;\n    var r = load64(&b) * 10 + load64(&b + 8);\n    return r;\n}\nsyscall(60, main());\n"

# ── C (D3): a u128 comparison compares all 128 bits ─────────────────────────────────────────────
# The planning repro (c1.cyr, exit 170): b = 2^64 + 5, c = 2^65 + 5 — `==` was true, `<` false.
C1='fn main(): i64 {\n    var b: u128 = 0;\n    var c: u128 = 0;\n    store64(&b, 5); store64(&b + 8, 1);\n    store64(&c, 5); store64(&c + 8, 2);\n    var r = 0;\n    if (b == c) { r = r + 1; }\n    if (b != c) { r = r + 2; }\n    if (b < c) { r = r + 4; }\n    if (b > c) { r = r + 8; }\n    if (b == 5) { r = r + 16; }\n    var x = b < c;\n    return r * 10 + x;\n}\nsyscall(60, main());\n'
exits c01 61 "C1: \`==\` / \`!=\` / \`<\` / \`>\` and a value read the high words (c1.cyr: exited 170)" "$C1"
exits c02 61 "C2: ... the same program under CYRIUS_IR=3" "$C1" CYRIUS_IR=3
exits c03 3 "C3: unsigned — a low word of 2^63 is above 1, and an integer is zero-extended" "var G: u128 = 0;\nstore64(&G, 0x8000000000000000);\nvar r = 0;\nif (G > 1) { r = r + 1; }\nif (G == 0x8000000000000000) { r = r + 2; }\nif (G < 0) { r = r + 4; }\nsyscall(60, r);\n"

# ── T (D4): a u128 truth test reads all 128 bits; match / switch compare a u128 subject on all 128 ──
# The planning probe (lane D3's k2.cyr, exit 27): b = 2^64 — `if (b)` was false, `!b` 1, match and
# switch took the 0 arm (the comparison, r, was already right): want r 1 + t 4 = 5.
T1='fn main(): i64 {\n    var b: u128 = 0;\n    store64(&b + 8, 1);\n    var r = if (b > 4) { 1 } else { 0 };\n    var m = 0;\n    match b { 0 => { m = 1; } _ => { m = 0; } }\n    var t = 0;\n    if (b) { t = t + 1; }\n    var u = 0;\n    if (!b) { u = 1; }\n    var w = 0;\n    switch (b) { case 0: w = 1; default: w = 0; }\n    return r + m * 2 + t * 4 + u * 8 + w * 16;\n}\nsyscall(60, main());\n'
exits t01 5 "T1: \`if (b)\`, \`!b\`, \`match b\`, \`switch (b)\` read the high word (k2.cyr: exited 27)" "$T1"
exits t02 5 "T2: ... the same program under CYRIUS_IR=3" "$T1" CYRIUS_IR=3
exits t03 173 "T3: top level — \`if (G)\`, \`!G\`, \`G && 1\`, \`0 || G\`, \`match G\`, \`switch (G)\` on 2^64 (exited 82)" "var G: u128 = 0;\nstore64(&G + 8, 1);\nvar r = 0;\nif (G) { r = r + 1; }\nif (!G) { r = r + 2; }\nif (G && 1) { r = r + 4; }\nif (0 || G) { r = r + 8; }\nmatch G { 0 => { r = r + 16; } _ => { r = r + 32; } }\nswitch (G) { case 0: r = r + 64; default: r = r + 128; }\nsyscall(60, r);\n"
exits t04 100 "T4: a table-sized \`switch\` (four dense cases) on 2^64 + 2 takes default; \`!d\` and \`d || 0\` as values (exited 13)" "fn main(): i64 {\n    var d: u128 = 0;\n    store64(&d, 2); store64(&d + 8, 1);\n    var w = 0;\n    switch (d) { case 0: w = 10; case 1: w = 11; case 2: w = 12; case 3: w = 13; default: w = 99; }\n    var x = !d;\n    var y = d || 0;\n    return w + x * 100 + y;\n}\nsyscall(60, main());\n"

# ── S (D3): a plain u128 assignment takes the whole value ───────────────────────────────────────
# The D2 finding's repro (a1.cyr, exit 73 = 1353 % 256): `b = c` and `b = 5` over a high word of 3.
S1='fn main(): i64 {\n    var b: u128 = 0;\n    store64(&b + 8, 3);\n    var c: u128 = 1;\n    b = c;\n    var r = load64(&b) * 10 + load64(&b + 8);\n    store64(&b + 8, 3);\n    b = 5;\n    r = r * 100 + load64(&b) * 10 + load64(&b + 8);\n    return r;\n}\nsyscall(60, main());\n'
exits s01 26 "S1: \`b = c\` copies, \`b = 5\` zero-extends (1050 % 256; a1.cyr: exited 73)" "$S1"
exits s02 26 "S2: ... the same program under CYRIUS_IR=3" "$S1" CYRIUS_IR=3
exits s03 70 "S3: globals and top level: \`G = H\` copies, \`G = 7\` zero-extends" "var G: u128 = 0;\nvar H: u128 = 0;\nstore64(&G + 8, 9);\nstore64(&H, 2);\nG = H;\nvar r = load64(&G) * 10 + load64(&G + 8);\nstore64(&G + 8, 9);\nG = 5;\nr = r + load64(&G) * 10 + load64(&G + 8);\nsyscall(60, r);\n"

# ── W (D2): every write of an f64 into an f32 rounds ────────────────────────────────────────────
# The filed repro (lane D's f4.cyr, exit 16 — only the initializer row): all five rows, exit 31.
W4='struct P { x: f32; }\nfn tk(a: f32): i64 { return load32(&a) & 0xFFFFFFFF; }\nfn rt(): f64 { return 1.5; }\nfn main(): i64 {\n    var h: f32 = 0;\n    h = 1.5;\n    var p = P { 1.5 };\n    var q = P { 0 };\n    q.x = 1.5;\n    var r: f32 = rt();\n    var ok = 0;\n    if ((load32(&h) & 0xFFFFFFFF) == 0x3FC00000) { ok = ok + 1; }\n    if ((load32(&p) & 0xFFFFFFFF) == 0x3FC00000) { ok = ok + 2; }\n    if ((load32(&q) & 0xFFFFFFFF) == 0x3FC00000) { ok = ok + 4; }\n    if (tk(1.5) == 0x3FC00000) { ok = ok + 8; }\n    if ((load32(&r) & 0xFFFFFFFF) == 0x3FC00000) { ok = ok + 16; }\n    return ok;\n}\nsyscall(60, main());\n'
exits w01 31 "W1: an assignment, a struct literal, a field store and an argument round (f4.cyr: exited 16)" "$W4"
exits w02 31 "W2: ... the same program under CYRIUS_IR=3" "$W4" CYRIUS_IR=3

# ── B (D2): a whole typed array and a bare array's OP= are refused by name ──────────────────────
BS='struct P { x; y; }\nvar GA: i64[4];\nvar GB[32];\n'
BA="is refused - an array is not an integer or a float (assign an element: \`a[i] = v\`)"
BB2="is refused - an array is not an integer or a float (a bare array has no element type"
refused b01 "assignment to array 'a' $BA" "B1: \`a = 8\` on a \`var a: i64[4]\` local" "${BS}fn main(): i64 { var a: i64[4]; a = 8; return 0; }\nsyscall(60, main());\n"
refused b02 "assignment to array 'a'" "B2: \`a = c\` (another array: it stored c's first word)" "${BS}fn main(): i64 { var a: i64[4]; var c: i64[4]; a = c; return 0; }\nsyscall(60, main());\n"
refused b03 "assignment to array 'GA'" "B3: a typed-array global, at top level" "${BS}GA = 8;\nsyscall(60, 0);\n"
refused b04 "assignment to array 'fa'" "B4: an f64[2] local" "${BS}fn main(): i64 { var fa: f64[2]; fa = 1.5; return 0; }\nsyscall(60, main());\n"
refused b05 "assignment to array 'pa'" "B5: a struct-element array" "${BS}fn main(): i64 { var pa: P[2]; var pb: P[2]; pa = pb; return 0; }\nsyscall(60, main());\n"
refused b06 "assignment to array 'big'" "B6: a typed local in static storage" "${BS}fn main(): i64 { var big: u8[130000]; big = 1; return 0; }\nsyscall(60, main());\n"
refused b07 "assignment to array 'a'" "B7: a for step \`a = 3\`" "${BS}fn main(): i64 { var a: i64[4]; var i = 0; for (i = 0; i < 1; a = 3) { i = i + 1; } return 0; }\nsyscall(60, main());\n"
refused b11 "compound assignment to array 'b' $BB2" "B11: \`b += 8\` on a bare local \`var b[16]\`" "${BS}fn main(): i64 { var b[16]; b += 8; return 0; }\nsyscall(60, main());\n"
refused b12 "compound assignment to array 'GB'" "B12: a bare global (the declaration zone)" "${BS}fn main(): i64 { GB -= 1; return 0; }\nsyscall(60, main());\n"
refused b13 "compound assignment to array 'LB'" "B13: a bare global declared after the first statement" "${BS}syscall(1, 1, \"\", 0);\nvar LB[8];\nLB |= 1;\nsyscall(60, 0);\n"
refused b14 "compound assignment to array 'sb'" "B14: a \`stack var sb[16]\`" "${BS}fn main(): i64 { stack var sb[16]; sb ^= 1; return 0; }\nsyscall(60, main());\n"
refused b15 "compound assignment to array 'big'" "B15: a bare local in static storage" "${BS}fn main(): i64 { var big[130000]; big >>>= 1; return 0; }\nsyscall(60, main());\n"
refused b16 "compound assignment to array 'b'" "B16: a for step \`b += 1\`" "${BS}fn main(): i64 { var b[16]; var i = 0; for (i = 0; i < 1; b += 1) { i = i + 1; } return 0; }\nsyscall(60, main());\n"
exits b20 43 "B20: kept — a bare \`b = v\` (its first word, not decided), the element forms, a typed array's address" "${BS}fn main(): i64 { var b[16]; b = 3; var a: i64[4]; a[1] = 4; a[1] += 36; var p = &a; return load64(&b) + a[1] + (p - &a); }\nsyscall(60, main());\n"

# ── I: CYRIUS_IR=3 and the x86 f32 conversions ──────────────────────────────────────────────────
I1='fn lo32(p): i64 { return load32(p) & 0xFFFFFFFF; }\nfn main(): i64 {\n    var y: f64 = 1.5;\n    var fy: f32 = f32_from(y);\n    var ok = 0;\n    if (lo32(&fy) == 0x3FC00000) { ok = ok + 1; }\n    var m: f32 = f32_from(1.5);\n    var m2: f32 = m * f32_from(2.0);\n    if (f32_to(m2) == 0x4008000000000000) { ok = ok + 2; }\n    var g: f32 = y;\n    if (lo32(&g) == 0x3FC00000) { ok = ok + 4; }\n    return ok;\n}\nsyscall(60, main());\n'
exits i1 7 "I1: f32_from / f32_to / an f32 initializer under CYRIUS_IR=3" "$I1" CYRIUS_IR=3
exits i2 7 "I2: ... the same program, default pipeline" "$I1"

# ── A: each crossos tcyr, every leg, with its full assertion count ─────────────────────────────
X86_LEGS="plain IR3 DCE"
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2>/dev/null && [ -s "$T/cc_a64" ]; then chmod +x "$T/cc_a64"
    else bad "A0: could not build src/main_aarch64.cyr"; fi
fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2>/dev/null && [ -s "$T/cc_cx" ] && \
   "$CC" < programs/cxvm.cyr > "$T/cxvm" 2>/dev/null && [ -s "$T/cxvm" ]; then chmod +x "$T/cc_cx" "$T/cxvm"
else bad "A0: could not build src/main_cx.cyr / programs/cxvm.cyr"; fi
tcyr_ok() {   # <label> <output file> <exit> <want>
    if [ "$3" -eq 0 ] && grep -q "^$4 passed, 0 failed" "$2"; then ok "$1: $4 passed"
    else bad "$1: exit $3, $(grep -E 'passed|FAIL' "$2" | tr -d '\r' | head -3 | tr '\n' '|')"; fi
}
tcyr_all() {   # <tag> <tcyr path> <assertion floor>
    tg=$1; TC="$ROOT/$2"
    want=$(grep -cE '^ *assert_eq\(' "$TC")
    [ "$want" -ge "$3" ] || bad "$tg: only $want assertions derived from $2 (floor $3)"
    for mode in $X86_LEGS; do
        case $mode in
            plain) env_=""; lbl="$tg x86" ;;
            IR3) env_="CYRIUS_IR=3"; lbl="$tg x86, CYRIUS_IR=3" ;;
            DCE) env_="CYRIUS_DCE=1"; lbl="$tg x86, CYRIUS_DCE=1" ;;
        esac
        rc=0; env $env_ "$CC" < "$TC" > "$T/$tg.$mode" 2> "$T/$tg.$mode.err" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/$tg.$mode.err" | head -1)"; continue; fi
        chmod +x "$T/$tg.$mode"; got=0; timeout 60 "$T/$tg.$mode" > "$T/$tg.$mode.out" 2>&1 || got=$?
        tcyr_ok "$lbl" "$T/$tg.$mode.out" "$got" "$want"
    done
    if [ -x "$T/cc_a64" ]; then
        if "$T/cc_a64" < "$TC" > "$T/$tg.a" 2> "$T/$tg.aerr"; then
            chmod +x "$T/$tg.a"; got=0; (cd "$T" && timeout 120 qemu-aarch64 "./$tg.a" > "$T/$tg.aout" 2>&1) || got=$?
            tcyr_ok "$tg aarch64 (qemu)" "$T/$tg.aout" "$got" "$want"
        else bad "$tg aarch64: the tcyr did not compile: $(grep '^error' "$T/$tg.aerr" | head -1)"; fi
    else echo "  SKIP $tg aarch64 — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
    if [ -x "$T/cc_cx" ]; then
        if "$T/cc_cx" < "$TC" > "$T/$tg.cyx" 2> "$T/$tg.cxerr" && [ -s "$T/$tg.cyx" ]; then
            got=0; timeout 120 "$T/cxvm" < "$T/$tg.cyx" > "$T/$tg.cxout" 2>&1 || got=$?
            tcyr_ok "$tg cx (cxvm)" "$T/$tg.cxout" "$got" "$want"
        else bad "$tg cx: the tcyr did not compile: $(grep '^error' "$T/$tg.cxerr" | head -1)"; fi
    fi
    if command -v wine > /dev/null 2>&1; then
        if CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$T/$tg.exe" 2> "$T/$tg.werr" && [ -s "$T/$tg.exe" ]; then
            got=0
            (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$tg.exe" > "$T/$tg.wout" 2>/dev/null) || got=$?
            tcyr_ok "$tg PE (wine)" "$T/$tg.wout" "$got" "$want"
        else bad "$tg PE: the tcyr did not compile: $(grep '^error' "$T/$tg.werr" | head -1)"; fi
    else echo "  SKIP $tg PE — wine not installed"; skips=$((skips + 1)); fi
}
tcyr_all AF tests/tcyr/crossos/f32_scalar_init_rounds.tcyr 30
tcyr_all AR tests/tcyr/crossos/int_name_routes_int_overload.tcyr 20
tcyr_all AU tests/tcyr/crossos/u128_compound_matches_long_form.tcyr 14
tcyr_all AU2 tests/tcyr/crossos/u128_add_sub_carry.tcyr 33
tcyr_all AC tests/tcyr/crossos/u128_compare_all_bits.tcyr 85
tcyr_all AS tests/tcyr/crossos/u128_assign_whole_value.tcyr 21
tcyr_all AW tests/tcyr/crossos/f32_writes_round.tcyr 21

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — f32 initializers round (F); a top-level pair bind refused (P); an integer name routes to _int (R); vector / typed-array / slice OP= refused (O); u128 + / - carry and every other u128 operator refused (U); u128 comparisons compare all 128 bits (C); a u128 truth test and match / switch subject read all 128 bits (T); a plain u128 assignment takes the whole value (S); every f32 write rounds (W); a whole typed array and a bare array OP= refused (B); IR=3 keeps the f32 conversions (I); every tcyr on x86_64 / IR / DCE / aarch64 / cx / PE (A)"
