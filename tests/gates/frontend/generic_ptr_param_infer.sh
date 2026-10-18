#!/bin/sh
# tests/gates/frontend/generic_ptr_param_infer.sh — 6.7.14
#
# A `p: *T` PARAMETER BINDS WHAT ITS POINTER ARGUMENT POINTS AT; AN `x: T` ONE BINDS NO POINTER (the user's decision
# D8 (a), 2026-10-16). With `fn gsz<T>(x: *T): i64 { return sizeof(T); }` and a 24-byte `struct S`, only a `*S`
# LOCAL bound S — through `x: *T` and, against the guide, through `x: T` too (6.6.17 gave it SLTYPE `0 - sid`, which
# the argument reader `_infer_conc_at_cursor` read as a struct argument) — while `gsz(&GS)`, a `*S` global, field,
# parameter or `: *S` call ran the i64 base (sizeof(T) 8, a struct-using body refused as its stub). The reader now
# knows the carrying parameter's shape (`_ic_arg` / `_ic_ptr_param`): through `p: *T` a `*S` local, parameter,
# capture or global, a `*S` field chain, a `: *S` call and `&G` / `&l` bind S (`_infer_conc_at`'s rungs, `_ic_addr`,
# `_ic_cap`, `_ic_rps`, `_gsc_chain`); through `x: T` a typed-pointer slot answers i64. 6.6.10 - 6.7.13, every target.
# Filed: docs/development/issues/archived/2026-10-14-generic-pointer-parameter-binds-only-from-pointer-local-decision.md
#
#   R  the filed repro, verbatim (one program per row, `syscall(60, <row>());` appended): ma 24, mb 24, mc 24, md 24,
#      mf 24, mg 24, mh 24, mi 8, mj 8 (before: 8 8 8 8 8 24 24 24 8) — and, appended the same way after the
#      repro's text, mk `gsz(mkp())` with `fn mkp(): *S` 24 (was 8) and ml `gsz(GS)`, a struct VALUE, 24 (unchanged)
#      — on x86_64, x86_64 CYRIUS_IR=3, aarch64 (qemu), cx (cxvm) and PE (wine)
#   N  refusals (x86_64): `gst(q)` with `fn gst<T>(x: T): i64 { return x.v; }` and `var q: *S` — through `x: T` a
#      `*S` local is a pointer now, so the call reaches the stub base and is refused once naming gst (it compiled:
#      the `*S` local bound S); `ga(&p)` with `p: *T1` — `&p` of a pointer is a `**` and binds nothing (refused
#      once naming ga, unchanged); `gst<S>(q)`, the explicit spelling, compiles (the migration's fix)
#   T  tests/tcyr/crossos/generic_struct_inference.tcyr (its PB group: every source above, a capture, `wp.p` / `G.p`,
#      a generic `: *T` call, a generic method, a forward, an 8 B struct's stub through `&t` / `&G`, an untyped impl
#      `self`, a `: T` result) on x86_64 (default, CYRIUS_IR=3), aarch64 (qemu), cx (cxvm) and PE (wine):
#      "N passed, 0 failed (N total)", N derived from the file (cx: the rows outside `#ifndef CYRIUS_TARGET_CX`)
#
# MUTATION LEDGER (2026-10-16; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run with
# CYCC= it — the aarch64 / cx legs build their compilers from the tree's own src, so a mutant shows on x86_64 / IR /
# PE):
#   MP1 the fix reverted (the tree before it)          -> RED R ma mb mc md mf mk (8), mi (24); N1 (compiled); T (the
#                                                         file does not build: `return pb_gd(&pb_gpt);` refused)
#   MP2 `_ic_ptr_param` answers 0 (no `*T` shape)     -> RED R ma mb mc md mf mg mk (8: a `*S` local is a pointer
#                                                         now); T (does not build); mi, mj green
#   MP3 `_ic_ptr_slot` binds through both shapes      -> RED R mi, mj (24); N1 (compiled); T (does not build: the W row's
#                                                         `id1(pp)` with `pp: *Pt` binds Pt: undefined `Pt_add`)
#   MP4 `_ic_addr` answers i64 (no `&G` / `&l`)       -> RED R ma md (8); T (does not build)
#   MP5 `_ic_arg` without its chain arm              -> RED R mc (8); T (2 failed: `w.p`, `wp.p` / `G.p`)
#   MP6 `_infer_conc_global` without the `*S` rung   -> RED R mb (8); T (rc 139: `var q: Pt = pb_gd(pb_gpp)`)
#   MP7 `_ic_call_rs` without `_ic_rps`              -> RED R mk (8); T (2 failed: a `: *S` call, a `: *T` generic)
#   MP8 `_ic_cap` answers 0 (no capture rung)        -> RED T (2 failed: the two captures, 8)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=generic_ptr_param_infer
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

TC=tests/tcyr/crossos/generic_struct_inference.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
N=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TC")
NCX=$(awk '/^[[:space:]]*#ifndef CYRIUS_TARGET_CX/{s=1; next} /^[[:space:]]*#endif/{s=0; next} !s && /^[[:space:]]*assert(_[a-z]+)?\(/{n++} END{print n+0}' "$TC")
FLOOR=261
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi
NPB=$(grep -c 'assert_eq(.*"PB: ' "$TC")
if [ "$NPB" -lt 21 ]; then echo "FAIL: $G: only $NPB PB rows in $TC (floor 21) — rows were lost"; exit 1; fi

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

# xr <id> <src> <want> <what>: the exit on every leg
xr() {
    for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$D/x_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: $4 did not build: $(grep -m1 'error' "$D/x_$n.err")"
        elif [ "$RC" -eq "$3" ]; then ok "$1 $leg: $4 exits $3"
        else bad "$1 $leg: $4 exits $RC, want $3"; fi
    done
}

# The filed repro's text, verbatim (the issue's heredoc).
cat > "$D/gz.cyr" <<'X'
struct S { v; w; x; }
struct W { p: *S; }
var GS = S { 5, 8, 3 };
var GP: *S = &GS;
fn gsz<T>(x: *T): i64 { return sizeof(T); }
fn gs<T>(x: T): i64 { return sizeof(T); }
fn ma(): i64 { return gsz(&GS); }
fn mb(): i64 { return gsz(GP); }
fn mc(): i64 { var w = W { &GS }; return gsz(w.p); }
fn md(): i64 { var l = S { 1, 2, 3 }; return gsz(&l); }
fn me(q: *S): i64 { return gsz(q); }
fn mf(): i64 { return me(&GS); }
fn mg(): i64 { var p: *S = &GS; return gsz(p); }
fn mh(): i64 { return gsz<S>(&GS); }
fn mi(): i64 { var q: *S = &GS; return gs(q); }
fn mj2(pp: *S): i64 { return gs(pp); }
fn mj(): i64 { return mj2(&GS); }
X
# The brief's two more rows, after the repro's text: a `: *S` call and a struct value.
cat > "$D/gz_more.cyr" <<'X'
fn mkp(): *S { return &GS; }
fn mk(): i64 { return gsz(mkp()); }
fn ml(): i64 { return gsz(GS); }
X

echo "R. the filed repro, verbatim: which pointer arguments bind T (D8 (a))"
for kv in ma:24 mb:24 mc:24 md:24 mf:24 mg:24 mh:24 mi:8 mj:8; do
    k=${kv%%:*}; v=${kv#*:}
    { cat "$D/gz.cyr"; printf 'syscall(60, %s());\n' "$k"; } > "$D/r_$k.cyr"
    xr "R $k" "$D/r_$k.cyr" "$v" "the repro's $k()"
done
for kv in mk:24 ml:24; do
    k=${kv%%:*}; v=${kv#*:}
    { cat "$D/gz.cyr" "$D/gz_more.cyr"; printf 'syscall(60, %s());\n' "$k"; } > "$D/r_$k.cyr"
    xr "R $k" "$D/r_$k.cyr" "$v" "$k() (gsz(mkp()) / gsz(GS))"
done

STUB="has no i64 (or other scalar) instance: it uses its type parameter as a struct"
echo "N. refusals, once each (x86_64)"
# nrow <id> <body of fn m> <fragment> <what>: refused with exactly one error, containing <fragment>
nrow() {
    { cat "$D/gz.cyr"; printf 'struct T1 { a; }\nfn gst<T>(x: T): i64 { return x.v; }\nfn ga<T>(x: *T): i64 { return x.a; }\nfn m(): i64 { %s }\nsyscall(60, m());\n' "$2"; } > "$D/$1.cyr"
    erc=0; "$CC" < "$D/$1.cyr" > "$D/$1" 2> "$D/$1.err" || erc=$?
    ne=$(grep -c '^error' "$D/$1.err" || true)
    if [ "$erc" -eq 0 ]; then bad "$1: $4 compiled (want it refused)"
    elif [ "$ne" -ne 1 ]; then bad "$1: $4: $ne errors, want 1: $(grep '^error' "$D/$1.err" | tr '\n' ' ')"
    elif grep -qF "$3" "$D/$1.err"; then ok "$1: $4 is refused once: $3"
    else bad "$1: $4: not refused as '$3': $(grep '^error' "$D/$1.err")"; fi
}
nrow N1 'var q: *S = &GS; return gst(q);' "generic 'gst' $STUB" "gst(q) with var q: *S through x: T (a pointer: the stub base)"
nrow N2 'var t = T1 { 9 }; var p: *T1 = &t; return ga(&p);' "generic 'ga' $STUB" "ga(&p) with p: *T1 (a **, binds nothing)"
{ cat "$D/gz.cyr"; printf 'fn gst<T>(x: T): i64 { return x.v; }\nfn m(): i64 { var q: *S = &GS; return gst<S>(q); }\nsyscall(60, m());\n'; } > "$D/n3.cyr"
run_leg x86 "$D/n3.cyr" "$D/n3"
if [ "$RC" -eq 5 ]; then ok "N3: gst<S>(q), the explicit spelling, exits 5"
else bad "N3: gst<S>(q) exits $RC, want 5 $(grep -m1 error "$D/n3.err")"; fi

echo "T. $TC ($N rows; cx $NCX)"
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    want=$N
    [ "$leg" = cx ] && want=$NCX
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(grep -m1 'error' "$D/t_$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$want passed, 0 failed ($want total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$want passed, 0 failed ($want total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a \`p: *T\` parameter binds what its pointer argument points at and an \`x: T\` one binds no pointer (D8 (a)): the filed repro's nine rows and gsz(mkp()) / gsz(GS) (R) on x86_64 / IR / aarch64 / cx / PE, the refusals (N), and $N rows (T) on x86_64 / IR / aarch64 / cx / PE"
