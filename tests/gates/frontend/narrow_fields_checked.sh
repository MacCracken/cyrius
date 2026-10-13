#!/bin/sh
# tests/gates/frontend/narrow_fields_checked.sh — 6.7.10 (B7-2, B7-3)
#
# u8 / u16 / u32 AND f32 STRUCT FIELDS ARE THEIR WIDTHS (the user's decision, 2026-10-08: packed, no
# padding — the rule i8 / i16 / i32 fields have always followed). A u8..u32 field takes 1 / 2 / 4
# bytes and reads ZERO-extended; an f32 takes 4 (its binary32 bits, typed). Through 6.7.9 each was an
# 8-byte slot, so `struct C4 { r: u8; g: u8; b: u8; a: u8; }` was 32 bytes and `c.r = 250; c.r += 10;`
# read 260. Only a struct declaring one of them moves (its sizeof, offsets and by-value class);
# `#derive` computes the same layout (its own offset table, through the parser's type vocabulary)
# and its accessors read u8..u32 / f32 zero-extended.
#
# The runtime half is tests/tcyr/crossos/narrow_unsigned_f32_fields.tcyr (its header lists the rows:
# sizeof / offsets, zero-extension and wrap, unaligned `*T` access, f32, literals, the by-value class
# sweep at every size 1..17 and 20, operators and self, `*C4` stepping, the handle line). This gate:
#   A  that file on the legs this box has, compilers built from this tree: x86_64 (default,
#      CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm), PE (wine) — "N passed,
#      0 failed (N total)", N derived from the file (floor 199)
#   W  a struct redefined with another narrow kind warns ("redefined with a different layout"):
#      W1 i8 vs u8 and W2 i32 vs f32 (they warned through 6.7.9, when u8 / f32 were 8 bytes, and
#      share a width now: the kind tells them apart), W3 u8 vs u16 and W4 u32 vs f32 (new: their
#      layouts / kinds now differ), W5 an identical redefinition with u8 / u16 / u32 / f32 fields stays
#      silent (anti-vacuous)
#   D  dyn decision 2 (6.7.8) reaches a struct that shrank to 8 B or less: `dyn Show` from `C4 { u8 x4 }`
#      whose method takes `self: C4` is refused by name, once; the untyped `self` forms and calls
#      (exit 9)
#   T  a top-level `h(mk4())` with `F4 { f32 x4 }` (16 B: a pair now) is refused by name, once
#   V  a `#derive(accessors)` struct with u8 / u16 / u32 / f32 / i8 fields builds — the derive's
#      `#assert sizeof` backstop holds (13 bytes) — and its getters read zero-extended (255, 65535,
#      4294967295, the f32 bits) and signed (an i8 -1), its setters write only their bytes (exit 0)
#   S  (6.7.10 B7-3) `#derive(Serialize)` takes u8 / u16 / u32 / f32 fields (through 6.7.9 the build
#      was refused: `undefined function 'u8_to_json'`): S1 tests/tcyr/derive/derive_serialize_narrow.tcyr
#      (u8..u32 written zero-extended — a u32 4000000000 is not -294967296 — and decoded truncating at
#      the width; f32 written widened to f64, the user's decision 2026-10-12 — 0.1f is
#      0.10000000149011612 — and decoded narrowed, bit for bit: subnormals, the largest finite, -0.0;
#      f32 beside f64, a nested derived struct, accessors stacked, `#derive(Deserialize)`; each
#      through `_to_json`, `_from_json_str` and the pairs form) on x86_64 (default, IR=1, IR=3, DCE=1),
#      aarch64 and PE — no cx leg: the cx compiler's code buffer overflows on lib/bayan.cyr (a filed cx
#      issue) — every leg the x86 run's total (floor 113); S2 a `u64` field stays outside the codecs,
#      as through 6.7.9 (refused: u64_to_json / u64_from_json undefined, nothing else); S3 the same
#      program with a u32 builds and round-trips (exit 29)
#
# MUTATION LEDGER (2026-10-12; each a scratch copy of the tree with the one change, its compiler built
# from that copy, this gate run from the copy with CYCC=<that compiler>):
#   real tree                                         -> GREEN
#   the B7-1c compiler (845bbe3f, 8-byte narrow fields) as CYCC -> RED 10: A x86 x4 and PE (71 rows:
#                                                      sizeof, offsets, wrap, literals, the handle line; the
#                                                      aarch64 / cx legs build their compilers from this
#                                                      tree's src), W3, W4, W5, D1, V1 (exit 1: sizeof 41)
#   M16 `_add_narrow_field` never called (8-byte slots) -> RED 12: A x7 (71 rows), W3, W4, W5 (exit 45:
#                                                      sizeof 40), D1 (C4 32 B formed a dyn), V1 (the
#                                                      derive's `#assert sizeof` backstop fails the build);
#                                                      and derive_accessor_widths.tcyr does not build,
#                                                      field_compound_values D1, kmode_enum_initializer_baked
#                                                      RF / KU
#   M17 `_fld_lw` ignoring the unsigned mark          -> RED 8: A x7 (113 rows: 255 read as -1, the class
#                                                      sweep's checksums), V1 (exit 11: `q.c` sign-extended);
#                                                      and gvar_enum_initializer, derive_accessor_widths,
#                                                      kmode R check 15
#   M18 `_fld_compound` negating every narrow width (the 6.7.9 code) -> RED 7: A x7 (the u8 `>>=` and the
#                                                      u8 / u16 / u32 `/=` rows: a sign-extended dividend)
#   M19 an f32 field's float kind not recorded        -> RED 8: A x7 (98 rows), W2 (i32 / f32 one layout);
#                                                      and field_compound_values L5, f32_writes_round,
#                                                      f64_struct_fields, kmode RF / KF / KU
#   M20 the derive's offset table back to the i-only ladder -> RED 1: V1 (the `#assert sizeof` backstop
#                                                      fails the build); and derive_accessor_widths.tcyr
#                                                      does not build
#   M21 `PP_DFIELD_ZX` answering 0 (every narrow getter signed) -> RED 1: V1 (exit 2: 255 read -1); and
#                                                      derive_accessor_widths (7 rows)
#   M22 `_struct_same_layout` without the kind compare -> RED 3: W1, W2, W4 (silent)
# B7-3 (2026-10-12, the same method; each RED only on its S rows, every other section green):
#   M23 Serialize's integer load ignoring PP_DFIELD_ZX (u8..u32 sign-extended) -> RED 6: S1 x6 (6 checks:
#                                                      255 / 65535 / 4294967295 / 4000000000 written negative)
#   M24 PP_DFIELD_FLT not answering f32 (the f32 arm dropped) -> RED 6: S1 x6 (undefined f32_to_json)
#   M25 the `_dfb` pre-scan counting f64 only        -> RED 6: S1 x6 (undefined variable '_dfb': a struct
#                                                      whose only float is an f32)
#   M23u PP_DFIELD_INT without the u64 exclusion     -> RED 1: S2 (a u64 field builds, written signed)
#   M23d the decoders' f32 store without f32_from (store32 of the f64 bits) -> RED 6: S1 x6 (35 checks)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
G=narrow_fields_checked
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $D (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper.
WP="$D/wine"
WHM="$D/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null

fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

TC=tests/tcyr/crossos/narrow_unsigned_f32_fields.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
N=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TC")
FLOOR=199
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi

# The legs this box can run: aarch64 under qemu, cx under the tree's own cxvm, PE under wine.
A64=""; CXCC=""; WINE=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
        chmod +x "$D/cc_a64"; A64="$D/cc_a64"
    else bad "aarch64: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: aarch64 leg (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then
    chmod +x "$D/cc_cx" "$D/cxvm"; CXCC="$D/cc_cx"
else bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: PE leg (wine not installed)"; skips=$((skips + 1)); fi

# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build)
# and LAST (the last line of its output, CR stripped).
run_leg() {
    RC=-1; LAST=''
    case "$1" in
        x86)   "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        x86:*) env "${1#x86:}" "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        a64)   "$A64" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        cx)    "$CXCC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        pe)    CYRIUS_TARGET_WIN=1 "$CC" < "$2" > "$3.exe" 2> "$3.err" || return 0 ;;
    esac
    RC=0
    case "$1" in
        x86|x86:*) chmod +x "$3"; timeout 60 "$3" > "$3.out" 2>&1 || RC=$? ;;
        a64)  chmod +x "$3"; timeout 300 qemu-aarch64 "$3" > "$3.out" 2>&1 || RC=$? ;;
        cx)   timeout 300 "$D/cxvm" < "$3" > "$3.out" 2>&1 || RC=$? ;;
        pe)   (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$3.exe" > "$3.out" 2> /dev/null) || RC=$? ;;
    esac
    LAST=$(tail -1 "$3.out" | tr -d '\r')
}
OTHER=""
[ -n "$A64" ] && OTHER="$OTHER a64"
[ -n "$CXCC" ] && OTHER="$OTHER cx"
[ "$WINE" = 1 ] && OTHER="$OTHER pe"
XLEGS="x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1"

echo "A. $TC ($N rows)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "A $leg: the values file did not build: $(grep '^error' "$D/t_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "A $leg: $LAST"
    else bad "A $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

build() { rc=0; timeout 60 "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?; }
LAY='redefined with a different layout'
# warns <name> <what> <first field type> <second field type>: the redefinition builds and warns once
warns() {
    printf 'struct P { a: %s; b; }\nstruct P { a: %s; b; }\nfn main(): i64 { var p = P { 1, 2 }; return p.b; }\nsyscall(60, main());\n' "$3" "$4" > "$D/$1.cyr"
    build "$1"
    n=$(grep -c "$LAY" "$D/$1.err" || true)
    if [ "$rc" -ne 0 ]; then bad "$2: rc $rc: $(grep '^error' "$D/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$2: $n '$LAY' warnings (want 1)"
    else ok "$2: warns once"; fi
}
echo "W. a struct redefined with another narrow kind"
warns w1 "W1 i8 vs u8 (kept: one width, the kind differs)" i8 u8
warns w2 "W2 i32 vs f32 (kept: one width, the kind differs)" i32 f32
warns w3 "W3 u8 vs u16 (new: the layouts differ)" u8 u16
warns w4 "W4 u32 vs f32 (new: one width, the kind differs)" u32 f32
printf 'struct P { a: u8; b: u16; c: u32; d: f32; e; }\nstruct P { a: u8; b: u16; c: u32; d: f32; e; }\nfn main(): i64 { var p = P { 1, 2, 3, 1.5, 5 }; return p.e + sizeof(P); }\nsyscall(60, main());\n' > "$D/w5.cyr"
build w5
if [ "$rc" -ne 0 ]; then bad "W5: rc $rc: $(grep '^error' "$D/w5.err" | head -1)"
elif grep -q '^warning' "$D/w5.err"; then bad "W5: an identical redefinition warned: $(grep '^warning' "$D/w5.err" | head -1)"
else
    chmod +x "$D/w5.bin"; got=0; timeout 10 "$D/w5.bin" || got=$?
    if [ "$got" -eq 24 ]; then ok "W5 an identical redefinition with u8 / u16 / u32 / f32 fields: silent, exit 24 (5 + 19)"
    else bad "W5: exit $got, want 24"; fi
fi

echo "D. dyn decision 2 meets a struct that shrank to 8 B or less"
DYN='struct C4 { r: u8; g: u8; b: u8; a: u8; }\ntrait Show { fn show(self): i64; }\n'
printf "${DYN}"'impl Show for C4 { fn show(self: C4): i64 { return self.r; } }\nfn main(): i64 { var c = C4 { 9, 2, 3, 4 }; var d: dyn Show = &c; return d.show(); }\nsyscall(60, main());\n' > "$D/d1.cyr"
build d1
n=$(grep -c '^error' "$D/d1.err" || true)
if [ "$rc" -eq 0 ]; then bad "D1: \`self: C4\` (4 B) formed a dyn: BUILT"
elif ! grep -qF "cannot form dyn Show from C4 - its method 'show' takes \`self: C4\` by value" "$D/d1.err"; then bad "D1: refused, but not as expected: $(grep '^error' "$D/d1.err" | head -1)"
elif [ "$n" -ne 1 ]; then bad "D1: $n error lines (want 1)"
else ok "D1 \`dyn Show\` from C4 (u8 x4, 4 B) with \`self: C4\`: refused by name, once"; fi
printf "${DYN}"'impl Show for C4 { fn show(self): i64 { return self.r; } }\nfn main(): i64 { var c = C4 { 9, 2, 3, 4 }; var d: dyn Show = &c; return d.show(); }\nsyscall(60, main());\n' > "$D/d2.cyr"
build d2
if [ "$rc" -ne 0 ]; then bad "D2: rc $rc: $(grep '^error' "$D/d2.err" | head -1)"
else chmod +x "$D/d2.bin"; got=0; timeout 10 "$D/d2.bin" || got=$?
    if [ "$got" -eq 9 ]; then ok "D2 the untyped \`self\`: forms and calls (exit 9)"; else bad "D2: exit $got, want 9"; fi
fi

echo "T. a top-level call into an address-passed parameter"
printf 'struct F4 { a: f32; b: f32; c: f32; d: f32; }\nfn mk4(): F4 { var r = F4 { 1.0, 2.0, 3.0, 4.0 }; return r; }\nfn h(p: F4): i64 { return f64_to(f32_to(p.d)); }\nvar r = h(mk4());\nsyscall(60, r);\n' > "$D/t1.cyr"
build t1
n=$(grep -c '^error' "$D/t1.err" || true)
if [ "$rc" -eq 0 ]; then bad "T1: top-level h(mk4()) with a 16 B F4 BUILT"
elif ! grep -qF "'mk4' returns a struct by value, and a struct result needs storage in a fn's frame" "$D/t1.err"; then bad "T1: refused, but not as expected: $(grep '^error' "$D/t1.err" | head -1)"
elif [ "$n" -ne 1 ]; then bad "T1: $n error lines (want 1)"
else ok "T1 top-level h(mk4()), F4 { f32 x4 } (16 B, a pair): refused by name, once"; fi

echo "V. #derive(accessors) on u8 / u16 / u32 / f32 / i8 fields"
cat > "$D/v1.cyr" <<'EOF'
include "lib/alloc.cyr"
#derive(accessors)
struct UN { a: u8; b: u16; c: u32; d: f32; e: i8; g: u8; }
fn fill(m, n, b) { var i = 0; while (i < n) { store8(m + i, b); i = i + 1; } return 0; }
fn main(): i64 {
    if (sizeof(UN) != 13) { return 1; }
    var p = alloc(32);
    fill(p, 32, 0xEE);
    UN_set_g(p, 0x11);
    UN_set_e(p, 0 - 1);
    UN_set_d(p, 0x3FC00000);
    UN_set_c(p, 0xFFFFFFFF);
    UN_set_b(p, 0xFFFF);
    UN_set_a(p, 0xFF);
    if (UN_a(p) != 255) { return 2; }
    if (UN_b(p) != 65535) { return 3; }
    if (UN_c(p) != 4294967295) { return 4; }
    if (UN_d(p) != 0x3FC00000) { return 5; }
    if (UN_e(p) != 0 - 1) { return 6; }
    if (UN_g(p) != 0x11) { return 7; }
    if (load8(p + 13) != 0xEE) { return 8; }
    if (load8(p + 12) != 0x11) { return 9; }
    if (load32(p + 7) != 0x3FC00000) { return 10; }
    var q: *UN = p;
    if (q.c != UN_c(p)) { return 11; }
    return 0;
}
alloc_init();
syscall(60, main());
EOF
build v1
if [ "$rc" -ne 0 ]; then bad "V1: rc $rc: $(grep '^error' "$D/v1.err" | head -1)"
else chmod +x "$D/v1.bin"; got=0; timeout 10 "$D/v1.bin" || got=$?
    if [ "$got" -eq 0 ]; then ok "V1 a derived { u8; u16; u32; f32; i8; u8 } (13 B): builds, the getters zero-extend (i8 signed), the setters write their bytes"
    else bad "V1: exit $got (the row that failed; 0 = all)"; fi
fi

echo "S. #derive(Serialize) on u8 / u16 / u32 / f32 fields (B7-3)"
SC=tests/tcyr/derive/derive_serialize_narrow.tcyr
# Its checks run in helper fns called per decoder, so the RUN total is the count; the x86 run's is
# the reference every other leg must print (floor 113). No cx leg: the cx compiler's code buffer
# overflows on lib/bayan.cyr (a filed cx issue), which every Serialize codec includes.
SFLOOR=113
ST=""
if [ ! -f "$SC" ]; then bad "S1: $SC is missing"
else
    for leg in $XLEGS $OTHER; do
        [ "$leg" = cx ] && continue
        n=$(printf 's_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$SC" "$D/$n"
        t=$(printf '%s' "$LAST" | sed -n 's/^\([0-9][0-9]*\) passed, 0 failed (\1 total)$/\1/p')
        [ -z "$ST" ] && [ -n "$t" ] && [ "$leg" = x86 ] && ST=$t
        if [ "$RC" -eq -1 ]; then bad "S1 $leg: the codecs file did not build: $(grep '^error\|undefined' "$D/$n.err" | head -1)"
        elif [ "$RC" -ne 0 ] || [ -z "$t" ]; then bad "S1 $leg: exit $RC, '$LAST' $(grep -m3 'FAIL' "$D/$n.out" | tr '\n' ' ')"
        elif [ "$t" -lt "$SFLOOR" ]; then bad "S1 $leg: only $t checks ran (floor $SFLOOR) — rows were lost"
        elif [ "$t" != "$ST" ]; then bad "S1 $leg: $t checks ran, x86 ran ${ST:-none}"
        else ok "S1 $leg: $LAST"; fi
    done
fi
# S2: a u64 field stays outside the codecs, as through 6.7.9 — no unsigned 64-bit printer, and
# `str_builder_add_int` would write 2^63 and over as negative. Refused by the undefined-function
# check, naming u64_to_json / u64_from_json and nothing else. S3 is the same program with u32: it builds.
SHDR='include "lib/syscalls.cyr"\ninclude "lib/string.cyr"\ninclude "lib/str.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/fmt.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/hashmap.cyr"\ninclude "lib/result.cyr"\ninclude "lib/fnptr.cyr"\ninclude "lib/io.cyr"\ninclude "lib/math.cyr"\ninclude "lib/bayan.cyr"\n'
SBODY='fn main(): i64 { alloc_init(); var w = W { 7, 9 }; var sb = str_builder_new(); W_to_json(&w, sb); var s = str_builder_build(sb); var r = W_from_json_str(str_data(s)); return load32(r) + load64(r + sizeof(W) - 8) + str_len(s); }\nsyscall(60, main());\n'
printf "${SHDR}"'#derive(Serialize)\nstruct W { a: u64; n; }\n'"${SBODY}" > "$D/s2.cyr"
build s2
und=$( (grep -o "undefined function '[A-Za-z0-9_]*'" "$D/s2.err" || true) | sort -u | tr '\n' ' ')
if [ "$rc" -eq 0 ]; then bad "S2: a u64 field in #derive(Serialize) BUILT (it would print 2^63 and over negative)"
elif [ "$und" != "undefined function 'u64_from_json' undefined function 'u64_to_json' " ]; then bad "S2: refused, but not as expected: [$und] $(grep '^error' "$D/s2.err" | head -1)"
else ok "S2 a u64 field: refused, u64_to_json / u64_from_json undefined (as through 6.7.9)"; fi
printf "${SHDR}"'#derive(Serialize)\nstruct W { a: u32; n; }\n'"${SBODY}" > "$D/s3.cyr"
build s3
if [ "$rc" -ne 0 ]; then bad "S3: the u32 control did not build: $(grep '^error\|undefined' "$D/s3.err" | head -1)"
else chmod +x "$D/s3.bin"; got=0; timeout 10 "$D/s3.bin" || got=$?
    if [ "$got" -eq 29 ]; then ok "S3 the same struct with a u32: builds and round-trips (exit 29 = 7 + 9 + the 13 bytes of {\"a\":7,\"n\":9})"
    else bad "S3: exit $got, want 29"; fi
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — u8 / u16 / u32 / f32 fields are their widths: the values file on x86_64 / IR / DCE / aarch64 / cx / PE (A), the redefinition warnings (W), the dyn and top-level refusals that follow the size (D, T), the derive's layout and accessors (V), the derive's JSON codecs (S)"
