#!/bin/sh
# tests/gates/frontend/derive_cstring_field.sh — 6.7.10 (B7-4)
#
# `#derive(Serialize)` TAKES A `: cstring` FIELD (issues/2026-10-08-derive-serialize-cstring-fields.md,
# asked by sigil). Through 6.7.9 the codecs' field dispatch had no cstring arm, so the type name fell
# into the nested-struct arm and the build was refused (`undefined function 'cstring_to_json'` /
# `'cstring_from_json'`); sigil hand-rolls its cert / dm-verity codecs because of it. The wire shape
# is the user's (2026-10-12; sigil's `agnosys_json_emit_cstr_or_null`): a NULL pointer encodes as
# JSON `null`, any other as an escaped JSON string (lib/str.cyr `str_builder_add_json_cstr`, the
# `Str` field escaper over the bytes); decoding gives NULL for `null` and otherwise a FRESH
# NUL-terminated copy (`str_json_unescape_cstr`: RFC 8259 unescape, UTF-8 out, any other value its
# text). The pairs form tells a quoted "null" from a bare null by the byte before bayan's value.
#
#   R  the issue's repro VERBATIM prints {"name":"example.org","bits":256}, exit 0 — on x86_64
#      (default, CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu) and PE (wine)
#   T  tests/tcyr/derive/derive_serialize_cstring.tcyr on the same legs (escapes `" \ / \b \f \n \r
#      \t`, \u0001, UTF-8, a surrogate pair -> 4 bytes, a lone surrogate, the empty string, NULL <->
#      null, a quoted "null" kept in BOTH decoders, bare tokens / an object value copied as text with
#      the fields after it decoded, missing keys, each decode a fresh copy, #derive(Deserialize)
#      alone) — every leg the x86 run's total (floor 167; its checks run per decoder in helper fns,
#      so the RUN total is the count)
#   S  (B7-4b, the user's decision 2026-10-12) a `Str` field decodes through the same unescape, in BOTH
#      decoders, and the pairs form gives a fresh copy: S1 a Str holding the bytes 01 08 22 is written
#      {"s":"\u0001\b\"","n":7} and the scanner and the pairs form each decode it back so that it is
#      written the same again (through 6.7.9 they wrote {"s":"u0001b\"","n":7} and
#      {"s":"\\u0001\\b\\\"","n":7}); S2 tests/tcyr/derive/derive_str_deserialize.tcyr (every escape,
#      a U+0000 kept, UTF-8, a surrogate pair, the fresh copy) — both on the legs above, S2 every leg
#      the x86 run's total (floor 68)
# No cx leg: the cx compiler's code buffer overflows on lib/bayan.cyr (a filed cx issue), which
# every Serialize codec includes.
#
# MUTATION LEDGER (2026-10-12; each a scratch copy of the tree with the one change, its compiler
# built from that copy when the change is in src/, this gate run from the copy with
# CYCC=<that compiler>):
#   real tree                                                     -> GREEN
#   M26 the cstring arm dropped (PP_DFIELD_CSTR answers 0)          -> RED 12: R x6 and T x6 (refused:
#                                                                 undefined cstring_to_json)
#   M27 the pairs form's quote check dropped (a quoted "null" is NULL) -> RED 6: T x6 (3 checks: the
#                                                                 pairs form decodes "null" as NULL)
#   M28 the `\u` decode dropped (an escaped `u` stands for itself)   -> RED 6: T x6 (18 checks)
#   M29 the encoder passes `t`, not `&t`                           -> RED 12: R x6 and T x6 (SIGSEGV: the
#                                                                 cell's first word read as a Str header)
#   M30 the scanner's `null` arm dropped (null copied as its text)   -> RED 6: T x6 (9 checks)
# B7-4b (the same method):
#   M31 the scanner's Str arm back to its 6.7.9 decode (`\n \t \r` only) -> RED 12: S1 x6 (scanned
#                                                                 {"s":"u0001b\"","n":7}) and S2 x6 (11 checks)
#   M32 the pairs form's Str arm back to the borrow (`v` stored)       -> RED 12: S1 x6 (paired
#                                                                 {"s":"\\u0001\\b\\\"","n":7}) and S2 x6 (14 checks)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
G=derive_cstring_field
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

TC=tests/tcyr/derive/derive_serialize_cstring.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
TFLOOR=167

# The legs this box can run: aarch64 under qemu, PE under wine.
A64=""; WINE=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
        chmod +x "$D/cc_a64"; A64="$D/cc_a64"
    else bad "aarch64: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: aarch64 leg (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: PE leg (wine not installed)"; skips=$((skips + 1)); fi

# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build),
# OUT (its whole output, CR stripped) and LAST (the last line).
run_leg() {
    RC=-1; OUT=''; LAST=''
    case "$1" in
        x86)   "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        x86:*) env "${1#x86:}" "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        a64)   "$A64" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        pe)    CYRIUS_TARGET_WIN=1 "$CC" < "$2" > "$3.exe" 2> "$3.err" || return 0 ;;
    esac
    RC=0
    case "$1" in
        x86|x86:*) chmod +x "$3"; timeout 60 "$3" > "$3.out" 2>&1 || RC=$? ;;
        a64)  chmod +x "$3"; timeout 300 qemu-aarch64 "$3" > "$3.out" 2>&1 || RC=$? ;;
        pe)   (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$3.exe" > "$3.out" 2> /dev/null) || RC=$? ;;
    esac
    OUT=$(tr -d '\r' < "$3.out")
    LAST=$(printf '%s\n' "$OUT" | tail -1)
}
LEGS="x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1"
[ -n "$A64" ] && LEGS="$LEGS a64"
[ "$WINE" = 1 ] && LEGS="$LEGS pe"

# The issue's reproduction, verbatim (docs/development/issues/2026-10-08-derive-serialize-cstring-fields.md).
cat > "$D/cert.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/hashmap.cyr"
include "lib/bayan.cyr"

#derive(Serialize)
struct Cert { name: cstring; bits: i64; }

alloc_init();
var c = alloc(16);
store64(c, "example.org");
store64(c + 8, 256);
var sb = str_builder_new();
Cert_to_json(c, sb);
var s = str_builder_build(sb);
syscall(SYS_WRITE, 1, str_data(s), str_len(s));
syscall(SYS_EXIT, 0);
EOF
WANT='{"name":"example.org","bits":256}'
echo "R. the issue's repro, verbatim"
for leg in $LEGS; do
    n=$(printf 'r_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/cert.cyr" "$D/$n"
    if [ "$RC" -eq -1 ]; then bad "R $leg: refused: $(grep '^error\|undefined' "$D/$n.err" | head -1)"
    elif [ "$RC" -ne 0 ] || [ "$OUT" != "$WANT" ]; then bad "R $leg: exit $RC, printed '$OUT' (want '$WANT', exit 0)"
    else ok "R $leg: $OUT"; fi
done

echo "T. $TC"
TT=""
for leg in $LEGS; do
    n=$(printf 't_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/$n"
    t=$(printf '%s' "$LAST" | sed -n 's/^\([0-9][0-9]*\) passed, 0 failed (\1 total)$/\1/p')
    [ -z "$TT" ] && [ -n "$t" ] && [ "$leg" = x86 ] && TT=$t
    if [ "$RC" -eq -1 ]; then bad "T $leg: the codecs file did not build: $(grep '^error\|undefined' "$D/$n.err" | head -1)"
    elif [ "$RC" -ne 0 ] || [ -z "$t" ]; then bad "T $leg: exit $RC, '$LAST' $(grep -m3 'FAIL' "$D/$n.out" | tr '\n' ' ')"
    elif [ "$t" -lt "$TFLOOR" ]; then bad "T $leg: only $t checks ran (floor $TFLOOR) — rows were lost"
    elif [ "$t" != "$TT" ]; then bad "T $leg: $t checks ran, x86 ran ${TT:-none}"
    else ok "T $leg: $LAST"; fi
done

echo "S. a Str field's escapes survive both decoders (B7-4b)"
cat > "$D/s6.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/hashmap.cyr"
include "lib/bayan.cyr"

#derive(Serialize)
struct R { s: Str; n; }

fn show(r) {
    var sb = str_builder_new();
    R_to_json(r, sb);
    var o = str_builder_build(sb);
    syscall(SYS_WRITE, 1, str_data(o), str_len(o));
    syscall(SYS_WRITE, 1, "\n", 1);
    return o;
}
alloc_init();
var b = alloc(4);
store8(b, 1); store8(b + 1, 8); store8(b + 2, 34);
var r = alloc(16);
store64(r, str_new(b, 3));
store64(r + 8, 7);
var j = show(r);
show(R_from_json_str(str_data(j)));
show(R_from_json(bayan_json_parse(j)));
syscall(SYS_EXIT, 0);
EOF
SW='{"s":"\u0001\b\"","n":7}'
SWANT=$(printf '%s\n%s\n%s' "$SW" "$SW" "$SW")
for leg in $LEGS; do
    n=$(printf 's_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/s6.cyr" "$D/$n"
    if [ "$RC" -eq -1 ]; then bad "S1 $leg: refused: $(grep '^error\|undefined' "$D/$n.err" | head -1)"
    elif [ "$RC" -ne 0 ] || [ "$OUT" != "$SWANT" ]; then bad "S1 $leg: exit $RC, printed '$(printf '%s' "$OUT" | tr '\n' '|')' (want $SW three times)"
    else ok "S1 $leg: $SW, written, scanned, paired"; fi
done
SC=tests/tcyr/derive/derive_str_deserialize.tcyr
SFLOOR=68
ST=""
for leg in $LEGS; do
    n=$(printf 's2_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$SC" "$D/$n"
    t=$(printf '%s' "$LAST" | sed -n 's/^\([0-9][0-9]*\) passed, 0 failed (\1 total)$/\1/p')
    [ -z "$ST" ] && [ -n "$t" ] && [ "$leg" = x86 ] && ST=$t
    if [ "$RC" -eq -1 ]; then bad "S2 $leg: $SC did not build: $(grep '^error\|undefined' "$D/$n.err" | head -1)"
    elif [ "$RC" -ne 0 ] || [ -z "$t" ]; then bad "S2 $leg: exit $RC, '$LAST' $(grep -m3 'FAIL' "$D/$n.out" | tr '\n' ' ')"
    elif [ "$t" -lt "$SFLOOR" ]; then bad "S2 $leg: only $t checks ran (floor $SFLOOR) — rows were lost"
    elif [ "$t" != "$ST" ]; then bad "S2 $leg: $t checks ran, x86 ran ${ST:-none}"
    else ok "S2 $leg: $LAST"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a \`: cstring\` field in #derive(Serialize): the issue's repro (R) and the codec rows (T), and a Str field's escapes in both decoders (S), on x86_64 / IR / DCE / aarch64 / PE"
