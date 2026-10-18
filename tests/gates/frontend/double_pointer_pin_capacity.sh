#!/bin/sh
# tests/gates/frontend/double_pointer_pin_capacity.sh — 6.7.14
#
# A POINTER-TO-POINTER PIN HOLDS 16383 POINTEES. A `**T`'s step word pins its pointee `*T`'s own word (6.7.13, D9 (a))
# in a table whose index rode bits 56-62 of the word (126 pins). 6.7.13's deref-through bite made a pin carry its
# pointee's struct (so `take(**ppq)` of a `**Q3` is refused where a `**P3` is wanted), so two same-size structs took
# two pins where one had served them: the filed generator, 127 two-word structs each taken through `**S`, was refused
# "too many pointer-to-pointer pointee types (max 126)" (rc 1) on x86_64, IR=3, aarch64, cx and PE, where the 6.7.12
# base compiled it. A pinned word is now bit 62 plus a 14-bit pin in bits 48-61 (a `**T`'s word names no vector, so
# bits 48-55 are free there), the tables grow by doubling, and a `**T` global keeps its pin in 16 bits.
# Filed: docs/development/issues/2026-10-16-double-pointer-pins-interned-per-struct-cap.md
#
#   C1 the filed generator verbatim (127 structs): compiles and exits 0 on x86_64, x86_64 CYRIUS_IR=3, aarch64
#      (qemu), cx (cxvm) and PE (wine)
#   C2 the same generator at 1024 structs (REGSTRUCT's own cap, "too many struct definitions (max 1024)", is the most
#      distinct structs a unit holds): the same legs, exit 0
#   C3 2048 pins: 1024 structs each taken through `**S` and `***S`: the same legs, exit 0
#   P1 past pin 1500 (750 structs through `**S` and `***S` globals first): `take(**pps)`, `rw(*ppps)`, `take(*pps)`,
#      `take(**gpps)` of a `**P3` global and `take(***ppps)` each read the field, and `*pps + 1` / `*gpps + 1` step
#      sizeof(P3) (exit 42) on the same legs
#   P2 the DRS1 shape past pin 1500: `take(**ppq)`, ppq a `**Q3` (another 24-byte struct), refused once by name on
#      x86_64, aarch64, cx and PE
#   K1 the cap: the 16384th pin (1024 structs through `**S` .. 17 stars) is refused once, "max 16383" (x86_64)
#   K2 the guide states that cap (docs/guides/cyrius-guide.md, the `**T` paragraph)
#   The 6.7.13 rows stay in tests/gates/codegen/simd_pointer_param.sh (DRS1 / DRSw) and
#   tests/tcyr/crossos/double_pointer_deref_step.tcyr.
#
# MUTATION LEDGER (2026-10-17, 6.7.14, the vectors lane; each change alone in a scratch copy of the tree, this gate run
# there with CYCC=<its 2-stage mutant>; measured):
#   M0 the fix reverted (the 6.7.13 encoding, bits 56-62, 126 pins)   -> RED 25: C1-C3 and P1 on every leg ("max 126"),
#       P2 on x86 / aarch64 / cx / PE (3 lines: two cap refusals before it), K1 (16258 lines, "max 126")
#   M1 `_ps_vdesc` ignoring bit 62 (a pin read as a vector)          -> RED 5: P1 on every leg ("cannot pass '*p' to a
#       parameter that is not a pointer to its vector type": `rw`'s `**P3` read as a phantom `*V`); and
#       tests/tcyr/crossos/double_pointer_deref_step.tcyr refused ("an if expression branch cannot be a vector ..")
#   M2 `_ps_pin` reading 8 bits (`& 0xFF`)                            -> RED 9: P1 on every leg ("cannot pass 'pps' to a
#       parameter of a different struct type": pin 1501 read as 221, a `**S`), P2 on x86 / aarch64 / cx / PE (refuses
#       `**pps`, not `**ppq`)
#   M3 `_gv_ppn` a byte per global (store8 / load8)                  -> RED 5: P1 on every leg ("cannot pass 'gpps' ..":
#       the global's pin cut to 8 bits)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=double_pointer_pin_capacity
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

# build_leg <leg> <src> <out>: compile only; 0 = built.
build_leg() {
    case "$1" in
        x86)   "$CC" < "$2" > "$3" 2> "$3.err" ;;
        x86:*) env "${1#x86:}" "$CC" < "$2" > "$3" 2> "$3.err" ;;
        a64)   "$A64" < "$2" > "$3" 2> "$3.err" ;;
        cx)    "$CXCC" < "$2" > "$3" 2> "$3.err" ;;
        pe)    CYRIUS_TARGET_WIN=1 "$CC" < "$2" > "$3" 2> "$3.err" ;;
    esac
}
# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build).
run_leg() {
    RC=-1
    if [ "$1" = pe ]; then build_leg pe "$2" "$3.exe" || return 0
    else build_leg "$1" "$2" "$3" || return 0; fi
    RC=0
    case "$1" in
        x86|x86:*) chmod +x "$3"; timeout 60 "$3" > "$3.out" 2>&1 || RC=$? ;;
        a64)  chmod +x "$3"; timeout 300 qemu-aarch64 "$3" > "$3.out" 2>&1 || RC=$? ;;
        cx)   timeout 300 "$D/cxvm" < "$3" > "$3.out" 2>&1 || RC=$? ;;
        pe)   (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$3.exe" > "$3.out" 2> /dev/null) || RC=$? ;;
    esac
}
OTHER=""
[ -n "$A64" ] && OTHER="$OTHER a64"
[ -n "$CXCC" ] && OTHER="$OTHER cx"
[ "$WINE" = 1 ] && OTHER="$OTHER pe"
# exit_rows <tag> <src> <want> <what>: on every leg, a clean build (no error line) that exits <want>
exit_rows() {
    for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$D/r_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: did not build: $(grep -h -m1 'error' "$D/r_$n.err" "$D/r_$n.exe.err" 2>/dev/null | head -1)"
        elif grep -qh '^error' "$D/r_$n.err" "$D/r_$n.exe.err" 2>/dev/null; then bad "$1 $leg: built, but with an error line"
        elif [ "$RC" -eq "$3" ]; then ok "$1 $leg: exit $3"
        else bad "$1 $leg: exit $RC, want $3 ($4)"; fi
    done
}
# refused <name> <what> <src> <leg> <frag>: compile fails with exactly one error line holding <frag>, and no binary
refused() {
    rc=0
    case "$4" in
        pe)  CYRIUS_TARGET_WIN=1 timeout 120 "$CC" < "$3" > "$D/$1.bin" 2> "$D/$1.err" || rc=$? ;;
        a64) timeout 120 "$A64" < "$3" > "$D/$1.bin" 2> "$D/$1.err" || rc=$? ;;
        cx)  timeout 120 "$CXCC" < "$3" > "$D/$1.bin" 2> "$D/$1.err" || rc=$? ;;
        *)   timeout 120 "$CC" < "$3" > "$D/$1.bin" 2> "$D/$1.err" || rc=$? ;;
    esac
    n=$(grep -c '^error' "$D/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$2: compiled (rc 0) — want \".. $5 ..\""
    elif [ "$n" -ne 1 ]; then bad "$2: $n error lines, want exactly 1: $(grep '^error' "$D/$1.err" | head -3 | tr '\n' '|')"
    elif ! grep '^error' "$D/$1.err" | grep -qF -- "$5"; then bad "$2: wrong refusal: $(grep '^error' "$D/$1.err" | head -1)"
    elif [ -s "$D/$1.bin" ]; then bad "$2: refused, but a binary was written"
    else ok "$2"; fi
}

# The filed generator, verbatim (the issue's awk program); C2 is the same program at 1024.
awk 'BEGIN{for(i=0;i<127;i++){printf "struct S%d { a; b; }\nfn f%d(pp: **S%d): i64 { return 0; }\n",i,i,i}
     print "fn main(): i64 { return 0; }"; print "syscall(60, main());"}' > "$D/c1.cyr"
awk 'BEGIN{for(i=0;i<1024;i++){printf "struct S%d { a; b; }\nfn f%d(pp: **S%d): i64 { return 0; }\n",i,i,i}
     print "fn main(): i64 { return 0; }"; print "syscall(60, main());"}' > "$D/c2.cyr"
awk 'BEGIN{for(i=0;i<1024;i++){printf "struct S%d { a; b; }\nfn f%d(pp: **S%d): i64 { return 0; }\nfn g%d(pp: ***S%d): i64 { return 0; }\n",i,i,i,i,i}
     print "fn main(): i64 { return 0; }"; print "syscall(60, main());"}' > "$D/c3.cyr"
[ "$(grep -c '^struct S' "$D/c1.cyr")" -eq 127 ] || bad "C1: the generator did not write 127 structs"
[ "$(grep -c '^fn g' "$D/c3.cyr")" -eq 1024 ] || bad "C3: the generator did not write 1024 \`***S\` fns"
echo "C1. the filed generator verbatim: 127 structs each through \`**S\` (refused 'max 126' before)"
exit_rows C1 "$D/c1.cyr" 0 "127 pins"
echo "C2. the generator at 1024 structs (REGSTRUCT's cap)"
exit_rows C2 "$D/c2.cyr" 0 "1024 pins"
echo "C3. 2048 pins: 1024 structs each through \`**S\` and \`***S\`"
exit_rows C3 "$D/c3.cyr" 0 "2048 pins"

# 750 structs through `**S` and `***S` globals: 1500 pins taken before P3's and Q3's (the globals are read before any
# fn, so P3's `**P3` global, declared after them, is pin 1501 and the locals and parameters share it).
awk 'BEGIN{for(i=0;i<750;i++){printf "struct S%d { a; b; }\nvar ga%d: **S%d = 0;\nvar gb%d: ***S%d = 0;\n",i,i,i,i,i}}' > "$D/g750.cyr"
cp "$D/g750.cyr" "$D/p1.cyr"
cat >> "$D/p1.cyr" <<'EOF'
struct P3 { a; b; c; }
struct Q3 { x; y; z; }
var gps: *P3 = 0;
var gpps: **P3 = 0;
fn take(p: *P3): i64 { return p.c; }
fn rw(p: **P3): i64 { return take(*p); }
fn main(): i64 {
    var s: P3; s.a = 1; s.b = 2; s.c = 42;
    var ps: *P3 = &s;
    var pps: **P3 = &ps;
    var ppps: ***P3 = &pps;
    gps = &s; gpps = &gps;
    var q = *pps + 1;
    var g = *gpps + 1;
    return take(**pps) + rw(*ppps) + take(*pps) + take(**gpps) + take(***ppps) + (q - ps) + (g - ps) - 216;
}
syscall(60, main());
EOF
cp "$D/g750.cyr" "$D/p2.cyr"
cat >> "$D/p2.cyr" <<'EOF'
struct P3 { a; b; c; }
struct Q3 { x; y; z; }
fn take(p: *P3): i64 { return p.c; }
fn main(): i64 { var s: P3; var ps: *P3 = &s; var pps: **P3 = &ps; var q: Q3; var pq: *Q3 = &q; var ppq: **Q3 = &pq; return take(**ppq) + take(**pps); }
syscall(60, main());
EOF
echo "P1. past pin 1500: a \`**P3\` local, parameter, global and a \`***P3\` read the field, \`*pps + 1\` steps 24 (exit 42)"
exit_rows P1 "$D/p1.cyr" 42 "five reads of 42, and \`*pps + 1\` / \`*gpps + 1\` stepping 24, less 216"
echo "P2. past pin 1500: take(**ppq), ppq a \`**Q3\` (another 24-byte struct), refused once (the DRS1 shape)"
P2F="cannot pass 'ppq' to a parameter of a different struct type in a call to 'take'"
refused P2x86 "P2 x86" "$D/p2.cyr" x86 "$P2F"
[ -n "$A64" ] && refused P2a64 "P2 aarch64" "$D/p2.cyr" a64 "$P2F"
[ -n "$CXCC" ] && refused P2cx "P2 cx" "$D/p2.cyr" cx "$P2F"
[ "$WINE" = 1 ] && refused P2pe "P2 PE" "$D/p2.cyr" pe "$P2F"

echo "K1. the cap: the 16384th pin is refused once"
awk 'BEGIN{for(i=0;i<1024;i++){printf "struct S%d { a; b; }\n",i; st="*"; for(d=2;d<=17;d++){st=st "*"; printf "fn f%d_%d(pp: %sS%d): i64 { return 0; }\n",i,d,st,i}}
     print "fn main(): i64 { return 0; }"; print "syscall(60, main());"}' > "$D/k1.cyr"
refused K1 "K1 1024 structs through \`**S\` .. 17 stars (16384 pins): 'max 16383' once" "$D/k1.cyr" x86 \
    "too many pointer-to-pointer pointee types (max 16383)"
# K2 — the guide states the cap the compiler prints (its "at most 126" outlived the change by a unit).
if grep -qF "at most 16383 distinct" docs/guides/cyrius-guide.md; then ok "K2 the guide names the cap, 16383"
else bad "K2 docs/guides/cyrius-guide.md does not say 'at most 16383 distinct' pointees of a pointer to a pointer"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — 127 / 1024 distinct \`**S\` structs and 2048 pins compile and run (C1-C3), a pin past 1500 types its dereferences (P1) and keeps its struct (P2), and the 16384th pin is refused once (K1), on x86_64 / IR=3 / aarch64 / cx / PE"
