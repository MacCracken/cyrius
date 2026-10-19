#!/bin/sh
# tests/gates/frontend/str_field_method.sh — 6.7.15
#
# A METHOD ON A `Str` FIELD PARSES AND PASSES THE FIELD'S VALUE AS `self`. `struct W { s: Str; n; }` with
# `w.s.len()`, `var k = w.s.clone();` or `w.s.eq(w.s)` was "expected ';', got '.'" on every target: a `Str` field is
# one pointer slot holding the header's address (6.6.17), so the field walk stopped before the `.m(` and nothing
# continued from there, while a method on a nested INLINE field (6.7.0 A5) and on a `Str` local (`h.len()`) parsed.
# The field's value — the header, as `h.len()` passes a handle's and `str_len(w.s)` passes the field — is parked as a
# `*Str` receiver and the method continues from it (`_load_str_hop`, src/frontend/parse_decl.cyr), as a `*T` field's
# method does. Filed: docs/development/issues/2026-10-17-method-call-on-str-field-does-not-parse.md
#
#   F  the filing's repros, verbatim: F1 `return w.s.len();` (5), F2 its `var k = w.s.clone();` (then `str_len(k)`: 5),
#      F3 its `return w.s.eq(w.s);` (1)
#   C  the filing's controls, unchanged: C1 `return w.s.len;` (5), C2 `return str_len(w.s);` (5)
#   T  tests/tcyr/crossos/str_field_method.tcyr (a local, `*W`, two levels down, through a `*T` field, call and method
#      results, `self.s`, a global, a capture, wraps, statements writing through `self`, a chain on the result, an
#      8 B struct, top level): "N passed, 0 failed (N total)", N derived from the file
# every row on x86_64, x86_64 CYRIUS_IR=1 / CYRIUS_IR=3 / CYRIUS_DCE=1, aarch64 (qemu), cx (cxvm) and PE (wine); the
# release gate's cross-OS leg runs T on ecb / ach / cass / pi.
#
# MUTATION LEDGER (2026-10-18; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run FROM
# that copy with CYCC= it, so every leg's compiler carries the mutant):
#   `_load_inline_hop` without its `Str` arm (the field's ADDRESS as `self`, the inline arm's) -> RED 28: F1-F3 and T
#       on every leg (F1 / F2 exit 1 — the slot read as the header, its len the next field w.n; F3 0; T 2 / 16); C green
#   `_fld_meth_inline` answering 0 for a `Str` field again (the lane head's behaviour) -> RED 28: F1-F3 and T on every
#       leg refused "expected ';', got '.'"; C green
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=str_field_method
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

TC=tests/tcyr/crossos/str_field_method.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
N=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TC")
if [ "$N" -lt 16 ]; then echo "FAIL: $G: only $N rows in $TC (floor 16) — rows were lost"; exit 1; fi

# The legs this box can run: aarch64 under qemu, cx under the tree's own cxvm, PE under wine.
A64=""; CXCC=""; WINE=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
        chmod +x "$D/cc_a64"; A64="$D/cc_a64"
    else bad "aarch64: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: aarch64 legs (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then
    chmod +x "$D/cc_cx" "$D/cxvm"; CXCC="$D/cc_cx"
else bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: PE legs (wine not installed)"; skips=$((skips + 1)); fi

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
LEGS="x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER"

# xr <id> <src> <want> <what>: compiles with no diagnostic but notes, exits <want> on every leg
xr() {
    for leg in $LEGS; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$D/x_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: $4 did not build: $(grep -m1 'error' "$D/x_$n.err")"
        elif grep -q '^error\|^warning' "$D/x_$n.err"; then bad "$1 $leg: $4 built with a diagnostic: $(grep -m1 '^error\|^warning' "$D/x_$n.err")"
        elif [ "$RC" -eq "$3" ]; then ok "$1 $leg: $4 exits $3"
        else bad "$1 $leg: $4 exits $RC, want $3"; fi
    done
}

echo "F. the filing's repros, verbatim"
cat > "$D/f1.cyr" <<'X'
include "lib/syscalls.cyr"
include "lib/str.cyr"
struct W { s: Str; n; }
fn main(): i64 {
    alloc_init();
    var w: W = W { str_from("abcde"), 1 };
    return w.s.len();
}
var r = main();
syscall(SYS_EXIT, r);
X
xr F1 "$D/f1.cyr" 5 "return w.s.len();"
sed 's/    return w.s.len();/    var k = w.s.clone();\n    return str_len(k);/' "$D/f1.cyr" > "$D/f2.cyr"
xr F2 "$D/f2.cyr" 5 "var k = w.s.clone(); then str_len(k)"
sed 's/    return w.s.len();/    return w.s.eq(w.s);/' "$D/f1.cyr" > "$D/f3.cyr"
xr F3 "$D/f3.cyr" 1 "return w.s.eq(w.s);"

echo "C. the filing's controls"
sed 's/    return w.s.len();/    return w.s.len;/' "$D/f1.cyr" > "$D/c1.cyr"
xr C1 "$D/c1.cyr" 5 "return w.s.len; (the field's .len)"
sed 's/    return w.s.len();/    return str_len(w.s);/' "$D/f1.cyr" > "$D/c2.cyr"
xr C2 "$D/c2.cyr" 5 "return str_len(w.s);"

echo "T. $TC ($N rows)"
for leg in $LEGS; do
    n=$(printf 'T_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: $TC did not build: $(grep -m1 'error' "$D/t_$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a method on a Str field passes the field's value: the filed repros (F), the controls (C) and $N rows (T) on x86_64 / IR=1 / IR=3 / DCE / aarch64 / cx / PE"
