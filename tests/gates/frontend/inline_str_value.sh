#!/bin/sh
# Gate: an INLINE `Str` is its header's address wherever a `Str` value is taken (6.7.13, the user's
# decision D7 (1), 2026-10-15; issues/archived/2026-10-12-inline-str-local-passed-to-str-param-wrong-value.md).
#
# THE DEFECT (measured on the 6.7.13 structs lane before the fix, 44ab2052, x86_64 / aarch64 under qemu /
# cx under cxvm / PE under wine, all four equal): a `Str` is a heap handle by name — its slot holds the
# address of a 16-byte `{ data; len; }` header — but `var t: Str = Str { "abcdefg", 7 };` is an INLINE
# header on the frame, whose slot is field 0. Every use of the bare name as a `Str` value took
# that slot, the `data` word, as the header, with no diagnostic:
#     f(t), f((t)), str_len(t) with `fn f(s: Str)`        -> 0 (the filed repro), want 7
#     f(30, t) with `fn f(k, s: Str)`                     -> 30, want 37
#     f(gt), gt an inline global                          -> 0
#     var h: Str = t; / var h = t; then f(h)              -> 0
#     h = t into a handle (`var h = str_from("zz")`)      -> 122 (the byte after "abcdefg"'s NUL)
#     return t; from `fn mk(): Str`                       -> 0 (and t dies with the frame)
#     G = t / w.s = t / W { t, 1 } / *ps = t              -> the data word stored as the header
#
# THE RULE (the user's decision D7 (1)): the bare name of an inline `Str` is its header's address wherever a
# `Str` value is taken — a `Str` or `*Str` parameter (any argument loop: a call, a method's argument, a tail call), a
# `Str` declaration (`var h: Str = t;`, and `var h = t;` as D29 types it: h is a second handle to t's header,
# no copy), an assignment into a `Str` handle (`h = t` rebinds h) — with no allocation: `&t` for a local, the
# static address for an inline global, the environment copy's address for a closure's capture (6.6.5). The
# uses that would let a FRAME's header outlive the frame are refused by name, at the name:
#     cannot return the inline Str 't' from a fn returning Str - its header lives in this frame and would
#       dangle (return a handle: str_new(data, len))
#     cannot store the inline Str 't' into a global / into a field / through a pointer - ... (store a handle: ...)
# A global's address is static and a capture is a copy in the closure's environment, so neither is refused
# (a closure returned out of t's frame keeps its copy: K4); a `defer` runs in the frame. A position that takes
# no `Str` value (an untyped parameter, store or fn return) keeps the word (K5, K6).
#
# 6.7.14 (the user's decision D20 (a), 2026-10-16; issues/2026-10-15-str-handle-into-inline-str-stores-one-word.md):
# `t = a` with t an inline `Str` and a a `Str` HANDLE — a local, a parameter, a global, a call or method declared
# `: Str`, a `Str` field — copies the 16-byte header a points at, as `t = u` between inline `Str`s does; through
# 6.7.13 it stored a's address into t.data and left t.len stale (6.6.16's pun: `var t: Str; t = a; return t.len;`
# read the frame's old bytes). So a bare `var t: Str;` (no initialiser) joins D7 (1): `f(t)` passes its header
# and `return t;` from a fn returning `Str` is refused (X3, restored), where 6.7.13's review fix had kept it
# outside the decision (its bare name its first word). An untyped source keeps the one-word store (K8).
#
# 6.7.14 (the user's decision D18 (c), 2026-10-16; issues/2026-10-15-inline-str-into-untyped-or-other-pointer-
# position-passes-data-word.md): only where a type says `Str`. lib/str.cyr types the `Str` methods' operand —
# `Str_eq` / `Str_cat` `other`, `Str_contains` `needle`, `Str_starts_with` `prefix`, `Str_ends_with` `suffix` —
# `Str`, so `h.eq(t)` passes t's header (D18a, the filed repro: 1, was 0) and a string literal argument is passed
# as a `Str` (`h.eq("abc")` 1, was 0); a handle argument compiles byte-identical to the untyped methods (CMP). `var
# p: *Str = t;` takes the header as a `p: *Str` parameter does (the crossos q_* rows). fncallN, callptr, a vec, a
# tuple element and an untyped if-expression branch keep the word (K9).
#
# 6.7.14 (the user's decision D21 (a), 2026-10-16; issues/2026-10-15-top-level-str-declaration-from-
# inline-str-global-copies.md): a top-level `var H: Str = gt;` (gt an inline `Str` global) binds a handle global to
# gt's static header, as the same line in a fn does — in the declaration zone (D21a, the filed repro: 33, was 37)
# and after the first statement (D21b: 33, was 37); a `var P: *Str = gt;` in the zone takes the same address (the
# crossos z_* rows); gt declared BELOW H stays refused (D21c, the zone's "declared below").
#
# ROWS: R0 the filed repro verbatim; R1 tests/tcyr/crossos/inline_str_value.tcyr (its row count derived,
# floor 47) on x86_64 (plain, CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu — EMULATION, not
# hardware), cx (cxvm) and PE (wine, a private prefix); X1-X13 refused (the message first, ONE `^error`, no
# warning, no binary) on the x86_64, aarch64, cx and PE compilers; K1-K8 controls that compile and run on every
# leg (K9 the untyped positions of D18 (c)); U1-U2 a bare `var t: Str;` assigned a handle reads its own header on
# every leg; D20a the filed repro verbatim (5 — the pun read 5 too), D20b its `return t.len;` (5; the pun left it
# unwritten), D20c the filed row 3 (5) on every leg; D18a the D18 filed repro verbatim (1), D18b `var p: *Str = t;`
# (7), D18c `var p: *Str = gt;` (7, no warning); D21a / D21b the D21 filed repro in the zone and after a first
# statement (33), D21c a source declared below stays refused; CMP a handle into the retyped methods builds
# byte-identical to the
# untyped methods on the x86_64, PE, aarch64 and cx compilers; AS1 an inline `Str` in an `async fn` across awaits
# (x86_64, CYRIUS_ASYNC=1).
#
# MUTATION LEDGER (2026-10-15; each mutant a scratch copy of the tree (src, lib, programs, this gate and its
# tcyr) with the one change, its cycc built from the mutated src, this gate run from the copy with CYCC= that
# cycc — so the aarch64 / cx / PE legs are built from the mutated src too):
#   n0 the tree before the fix (44ab2052)          -> RED 75: R0 x7 (exit 0), R1 x7 (SIGSEGV x5, a cx guest fault,
#                                                     a PE crash), X1-X13 x4 (each compiled), K1 x4, K2 x4, AS1 (139)
#   n1 `_istr_arg` returns at once                 -> RED 15: R0 x7, R1 x7 (f(t) 0, then a crash), AS1
#   n2 `_istr_decl` returns at once                -> RED 12: R1 x7 (var h: Str = t / var h = t / gt: 10 rows), K2
#                                                     x4, AS1
#   n3 `_istr_src` answers 0 (the copy-init copies) -> RED 7: R1 x7 (b_decl / b_untyped / b_wrap / g_bind: h a copy)
#   n4 `_istr_asg` returns at once                 -> RED 23: R1 x7 (h = t: 8 rows), X4 X5 X10 x4, K1 x4
#   n5 `_istr_ret` returns at once                 -> RED 31: R1 x7 (return gt), X1-X3 X12 X13 x4, K1 x4
#   n6 `_istr_fsc` answers 0                       -> RED 19: R1 x7 (w2.s = gt, p.s = gt), X6 X7 X11 x4
#   n7 `_istr_lit` returns at once                 -> RED 15: R1 x7 (W { gt, 1 }: a crash), X8 x4, K1 x4
#   n8 `_istr_dsto` returns at once                -> RED 15: R1 x7 (*ps = gt), X9 x4, K1 x4
#   n9 `_istr_ra` without `_fn_local_addr = 1`     -> RED 18: R0 x7 (`return f(t);` jumped out of t's frame: 8-248),
#                                                     R1 x7 (8-10 rows), K2 x4
#   n10 `_istr_name` without the capture rung      -> RED 7: R1 x7 (c_bindcap: `var h: Str = t` copied the capture)
#   (n0-n10 were measured with X3 — `var t: Str;` returned, refused — which the review fix moved out: the bare
#   declaration's D7 question is open, issues/2026-10-15-str-handle-into-inline-str-stores-one-word.md)
#   2026-10-16 (the review fix; the same scratch-copy method):
#   n11 `_istr_bare` / `_istr_bare_cap` answer 0   -> RED 15: R1 x7 (the five u_* rows), U1 x4, U2 x4 (t's unwritten
#                                                     length: 224 / 24 / 0 / 0 and 1 / 0 / 0 / 1)
#   n12 `_istr_cpmark` returns at once             -> RED 7: R1 x7 (u_copy 22, u_cap 22: the copy read its length)
#   (n11 / n12 retired with the marks by 6.7.14's D20 (a): the bare declaration is D7 (1)'s.)
#   2026-10-17 (6.7.14, D20 (a); the same scratch-copy method):
#   d1 the lane before D20 (c778c9817)             -> RED 22: R1 x7 (17 rows: b_bare, u_copy, the h_* copies — 22 the
#                                                     pun, t.len stale), X3 x4 (compiled), D20b x7 (0), D20c x4
#                                                     (224 / 24 / 0 / 0)
#   d2 `_istr_hop` answers 0 (no handle name)      -> RED 21: R1 x7 (8 rows: a local, parameter, global, `(a)`, a for
#                                                     step, an inline global, top level), D20a x7 (0), D20b x7 (0)
#   d3 `_istr_call` answers 0 (no `: Str` call)    -> RED 7: R1 x7 (h_gen 22: a generic call; a plain call is typed
#                                                     by `_istr_hcp` too)
#   d4 `_istr_hcp` answers 0 (no method / field)   -> RED 7: R1 x7 (h_meth, h_field, h_fieldp)
#   2026-10-17 (6.7.14, D18 (c)):
#   e1 the lane before D18 (0807784c2: untyped      -> RED 26: R1 x7 (h.eq(t) 0, then h.cat(t) read "abcdefg" as a
#      methods, no `*Str` declaration arm)              header: SIGSEGV x5, cx 12 rows, a PE crash), D18a x7 (0),
#                                                     D18b x4 (0), D18c x8 (warned; 0)
#   e2 `_istr_pdecl` answers 0                      -> RED 19: R1 x7 (q_ptr 73, q_pglob 33, q_pbare 5, the top-level
#                                                     `*Str`, and two encoder rows the wild `p.len = 3` corrupted),
#                                                     D18b x4, D18c x8
#   e3 `_istr_pdecl` without its SPSC              -> RED 4: D18c x4 (warned "assigning non-pointer to typed pointer")
#   e4 lib/str.cyr's five methods untyped again     -> RED 14: R1 x7, D18a x7 (0)
#   2026-10-17 (6.7.14, D21 (a)):
#   f1 the lane before D21 (11dc74b46)             -> RED 21: R1 x7 (HL, HZ: a copy, 7; HZ2 / PZ: the word), D21a x7
#                                                     (37), D21b x7 (37)
#   f2 `_istr_gz` answers 0 (the zone replay)      -> RED 14: R1 x7 and D21a x7 refused "declared below" (pass 1 made
#                                                     H a handle, the replay's copy path refuses it)
#   f3 `_istr_gsrc` answers 0 (pass 1 inline)      -> RED 14: R1 x7 (z_bind, z_wrap), D21a x7 (37: copied)
#   f4 `_istr_src` after the top-level arm again   -> RED 14: R1 x7 (R_TOP5: a copy), D21b x7 (37)
#   f5 the replay without its declared-below guard -> RED 4: D21c x4 (built)
#   real tree                                       -> GREEN
#
# Exit 1 = a row failed (or the compiler is missing); every leg that cannot run says so by name (a SKIP).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
G=inline_str_value
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
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
rows=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

A64="$T/cc_a64"
QEMU=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$A64" 2> "$T/cc_a64.err" && [ -s "$A64" ]; then chmod +x "$A64"; QEMU=1
    else bad "src/main_aarch64.cyr did not build: $(grep '^error' "$T/cc_a64.err" | head -1 || true)"; fi
else echo "  SKIP the aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
CX=0
CXC="$T/cc_cx"
if "$CC" < src/main_cx.cyr > "$CXC" 2> "$T/cc_cx.err" && [ -s "$CXC" ] \
   && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ]; then
    chmod +x "$CXC" "$T/cxvm"; CX=1
else bad "src/main_cx.cyr or programs/cxvm.cyr did not build: $(grep '^error' "$T/cc_cx.err" "$T/cxvm.err" | head -1 || true)"; fi
WINE=0
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP the PE run leg — wine not installed (the PE refusals still run)"; skips=$((skips + 1)); fi

# compile <leg> <name>: $T/<name>.<leg> (+ .err); rc in $crc. x86_64:VAR=1 is the host compiler under VAR.
compile() {
    crc=0
    case $1 in
        x86_64)   timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        x86_64:*) env "${1#x86_64:}" timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        aarch64)  timeout 60 "$A64" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        cx)       timeout 60 "$CXC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
        pe)       CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || crc=$? ;;
    esac
}
legs() {
    l="x86_64"
    [ "$QEMU" -eq 1 ] && l="$l aarch64"
    [ "$CX" -eq 1 ] && l="$l cx"
    echo "$l pe"
}
# execute <leg> <name>: runs $T/<name>.<leg>; exit in $got, the last output line in $last
execute() {
    got=0
    chmod +x "$T/$2.$1"
    case $1 in
        x86_64*) timeout 60 "$T/$2.$1" > "$T/$2.$1.out" 2>&1 || got=$? ;;
        aarch64) timeout 120 qemu-aarch64 "$T/$2.$1" > "$T/$2.$1.out" 2>&1 || got=$? ;;
        cx)      timeout 120 "$T/cxvm" < "$T/$2.$1" > "$T/$2.$1.out" 2>&1 || got=$? ;;
        pe)      cp "$T/$2.$1" "$T/$2.exe"
                 (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                     WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$2.exe" > "$T/$2.$1.out" 2> /dev/null) || got=$? ;;
    esac
    last=$(tail -1 "$T/$2.$1.out" | tr -d '\r')
}
# refused <name> <fragment> <what>: the source is $T/<name>.cyr; ONE `^error` line, holding <fragment>
refused() {
    rows=$((rows + 1))
    for leg in $(legs); do
        compile "$leg" "$1"
        n=$(grep -c '^error' "$T/$1.$leg.err" || true)
        w=$(grep -c '^warning' "$T/$1.$leg.err" || true)
        if [ "$crc" -eq 0 ]; then bad "$1 $3 ($leg): BUILT (rc 0)"
        elif ! grep '^error' "$T/$1.$leg.err" | head -1 | grep -qF "$2"; then bad "$1 $3 ($leg): refused, but not as expected: $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"
        elif [ "$n" -ne 1 ]; then bad "$1 $3 ($leg): $n error lines (want 1)"
        elif [ "$w" -ne 0 ]; then bad "$1 $3 ($leg): a warning beside the refusal: $(grep '^warning' "$T/$1.$leg.err" | head -1 || true)"
        elif [ -s "$T/$1.$leg" ]; then bad "$1 $3 ($leg): refused, but a binary was written"
        else ok "$1 $3 ($leg): refused"; fi
    done
}
# runs <name> <want> <what> [<legs>]: compiles clean and exits <want> on every leg
runs() {
    rows=$((rows + 1))
    for leg in ${4:-$(legs)}; do
        [ "$leg" = pe ] && [ "$WINE" -eq 0 ] && continue
        compile "$leg" "$1"
        if [ "$crc" -ne 0 ] || [ ! -s "$T/$1.$leg" ]; then bad "$1 $3 ($leg): did not build (rc $crc): $(grep '^error' "$T/$1.$leg.err" | head -1 || true)"; continue; fi
        execute "$leg" "$1"
        if [ "$got" = "$2" ]; then ok "$1 $3 ($leg): exit $got"; else bad "$1 $3 ($leg): exit $got, want $2"; fi
    done
}
XLEGS="x86_64 x86_64:CYRIUS_IR=1 x86_64:CYRIUS_IR=3 x86_64:CYRIUS_DCE=1"
OLEGS=""
[ "$QEMU" -eq 1 ] && OLEGS="$OLEGS aarch64"
[ "$CX" -eq 1 ] && OLEGS="$OLEGS cx"
[ "$WINE" -eq 1 ] && OLEGS="$OLEGS pe"

# --- R0: the filed repro, verbatim (exit 7; 0 = the data word read as the header) ---
cat > "$T/R0.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str) { return str_len(s); }
fn main() { var t: Str = Str { "abcdefg", 7 }; return f(t); }
var r = main();
syscall(SYS_EXIT, r);
EOF
runs R0 7 "the filed repro: f(t) into \`s: Str\`" "$XLEGS $OLEGS"

# --- R1: the crossos values file on every leg ---
TC=tests/tcyr/crossos/inline_str_value.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
N=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TC")
FLOOR=81
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi
cp "$TC" "$T/R1.cyr"
rows=$((rows + 1))
for leg in $XLEGS $OLEGS; do
    compile "$leg" R1
    if [ "$crc" -ne 0 ] || [ ! -s "$T/R1.$leg" ]; then bad "R1 $TC ($leg): did not build: $(grep '^error' "$T/R1.$leg.err" | head -1 || true)"; continue; fi
    execute "$leg" R1
    if [ "$got" -eq 0 ] && [ "$last" = "$N passed, 0 failed ($N total)" ]; then ok "R1 ($leg): $last"
    else bad "R1 ($leg): exit $got, '$last' (want $N passed): $(grep FAIL "$T/R1.$leg.out" | head -2 | tr '\n' ' ')"; fi
done

H='include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str): i64 { return str_len(s); }
struct W { s: Str; n; }
fn new_w(): *W { return alloc(sizeof(W)); }
fn new_slot(): *Str { return alloc(8); }
var gt: Str = Str { "abcdefg", 7 };
var G: Str = 0;
var U = 0;'
row() { printf '%s\n%s\nalloc_init();\nsyscall(60, go());\n' "$H" "$2" > "$T/$1.cyr"; }
MR="cannot return the inline Str 't' from a fn returning Str - its header lives in this frame and would dangle (return a handle: str_new(data, len))"
MG="cannot store the inline Str 't' into a global - its header lives in this frame and would dangle (store a handle: str_new(data, len))"
MF="cannot store the inline Str 't' into a field - its header lives in this frame and would dangle (store a handle: str_new(data, len))"
MP="cannot store the inline Str 't' through a pointer - its header lives in this frame and would dangle (store a handle: str_new(data, len))"

# --- X: a frame's inline Str where it would outlive the frame ---
row X1 'fn mk(): Str { var t: Str = Str { "abcdefg", 7 }; return t; }
fn go(): i64 { var h = mk(); return f(h); }'
refused X1 "$MR" "the filed table's \`return t;\` from \`fn mk(): Str\` (was 0)"
row X2 'fn mk(): Str { var t: Str = Str { "abcdefg", 7 }; return ((t)); }
fn go(): i64 { return f(mk()); }'
refused X2 "$MR" "\`return ((t));\`"
row X3 'fn mk(): Str { var t: Str; t.data = "abc"; t.len = 3; return t; }
fn go(): i64 { return f(mk()); }'
refused X3 "$MR" "\`var t: Str;\` (inline, no literal) returned (D20 (a); 6.7.13 compiled it, the first word)"
row X4 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; G = t; return f(G); }'
refused X4 "$MG" "\`G = t;\` into a Str global"
row X5 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; G = (t); return 0; }'
refused X5 "$MG" "\`G = (t);\`"
row X6 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var w: W = W { 0, 1 }; w.s = t; return f(w.s); }'
refused X6 "$MF" "\`w.s = t;\` into a Str field of a local"
row X7 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var p: *W = new_w(); p.s = (t); return 0; }'
refused X7 "$MF" "\`p.s = (t);\` through a \`*W\`"
row X8 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var w: W = W { t, 1 }; return f(w.s); }'
refused X8 "$MF" "\`W { t, 1 }\`, a literal's Str field"
row X9 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var ps: *Str = new_slot(); *ps = t; return 0; }'
refused X9 "$MP" "\`*ps = t;\` through a \`*Str\`"
row X10 'fn go(): i64 { var c = || { var t: Str = Str { "abcdefg", 7 }; G = t; return 0; }; return callptr(c); }'
refused X10 "$MG" "a closure body's own inline Str into a global"
row X11 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var w: W = W { 0, 1 }; var i = 0; for (i = 0; i < 1; w.s = t) { i = i + 1; } return 0; }'
refused X11 "$MF" "a for step's field store"
row X12 'fn W_name(self: *W): Str { var t: Str = Str { "abc", 3 }; return t; }
fn go(): i64 { var w: W = W { 0, 1 }; return f(w.name()); }'
refused X12 "$MR" "a method returning Str"
row X13 'fn mk(c): Str { if (c == 1) { var t: Str = Str { "abc", 3 }; return t; } return 0; }
fn go(): i64 { return f(mk(1)); }'
refused X13 "$MR" "\`return t;\` inside a block"

# --- K: controls (a global's or a capture's header does not dangle; untyped positions keep the word) ---
row K1 'fn mk(): Str { return gt; }
fn go(): i64 { var w: W = W { gt, 1 }; G = gt; var ps: *Str = new_slot(); *ps = gt; return f(mk()) + f(w.s) + f(G) + f(load64(ps)); }'
runs K1 28 "a global inline Str: returned, into a literal's field, a Str global, through a \`*Str\`"
row K2 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var h: Str = t; return f(h); }'
runs K2 7 "a frame's inline Str bound to a handle, then a tail call (it diverts)"
row K3 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var c = || { G = t; return 0; }; callptr(c); return f(G); }'
runs K3 7 "a captured inline Str (the environment's copy) into a global"
row K4 'fn mkc() { var t: Str = Str { "abcdefg", 7 }; return || { return f(t); }; }
fn go(): i64 { var c = mkc(); var x: i64[8]; var i = 0; while (i < 8) { x[i] = 0 - 1; i = i + 1; } return callptr(c) + x[1] + 1; }'
runs K4 7 "a closure returned out of t's frame keeps its copy"
row K5 'fn mk() { var t: Str = Str { "abcdefg", 7 }; return t; }
fn go(): i64 { var w = mk(); if (w == 0) { return 1; } return 2; }'
runs K5 2 "an untyped fn's \`return t;\` keeps the word (no Str value is taken)"
row K6 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; U = t; if (U == load64(&t)) { return 3; } return 4; }'
runs K6 3 "an untyped global keeps the word"
row K7 'fn mk(): Str { var h = str_from("abcde"); return h; }
fn go(): i64 { return f(mk()); }'
runs K7 5 "a Str handle returned from a fn returning Str"
row K8 'fn go(): i64 { var a = str_from("abcde"); var x = 0; x = a; var t: Str = Str { "zz", 2 }; t = x; return t.len * 10 + f(t); }'
runs K8 22 "an untyped source into an inline Str keeps the one-word store (t.len stays 2)"

row K9 'fn id(x): i64 { return x; }
fn go(): i64 {
    var t: Str = Str { "abcdefg", 7 };
    var w = load64(&t);
    var h = str_from("zz");
    var v = vec_new();
    vec_push(v, t);
    var x = (t, 1);
    var c = 1;
    var b = if (c == 1) { t } else { h };
    var n = 0;
    if (fncall1(&id, t) == w) { n = n + 1; }
    if (callptr(&id, t) == w) { n = n + 1; }
    if (vec_get(v, 0) == w) { n = n + 1; }
    if (x.0 == w) { n = n + 1; }
    if (b == w) { n = n + 1; }
    return n;
}'
runs K9 5 "untyped positions keep t's data word: fncall1, callptr, a vec, a tuple element, an if-expression branch (D18 (c))"

# --- U: a bare `var t: Str;` assigned a Str handle reads its OWN header, the handle's copied (D20 (a)) ---
row U1 'fn go(): i64 { var t: Str; t = str_from("hello"); return str_len(t); }'
runs U1 5 "\`var t: Str; t = a; str_len(t)\` — t's own header, a's copied (6.7.13 read a's string through the pun)"
row U2 'fn g(c): i64 { var t: Str; if (c == 1) { t = str_from("abc"); } else { t = str_from("de"); } return str_len(t); }
fn go(): i64 { return g(1); }'
runs U2 3 "\`var t: Str;\` assigned in one branch"

# --- D20: the filed repro (issues/2026-10-15-str-handle-into-inline-str-stores-one-word.md), verbatim, and its rows ---
cat > "$T/D20a.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn main() {
    alloc_init();
    var a = str_from("abcde");
    var t: Str;
    t = a;
    return str_len(t);
}
var r = main();
syscall(SYS_EXIT, r);
EOF
runs D20a 5 "the filed repro: \`var t: Str; t = a; str_len(t)\` (5 through t's own header)" "$XLEGS $OLEGS"
sed 's/return str_len(t);/return t.len;/' "$T/D20a.cyr" > "$T/D20b.cyr"
runs D20b 5 "the filed repro's \`return t.len;\` (the pun left t.len unwritten)" "$XLEGS $OLEGS"
row D20c 'fn go(): i64 { var t: Str; t = str_from("hello"); var h: Str = Str { "zz", 2 }; h = t; return str_len(h); }'
runs D20c 5 "the filed row 3: \`h = t\` copies t's header, a's copied into t (6.7.13: t's unwritten length)"

# --- D18: the filed repro (issues/2026-10-15-inline-str-into-untyped-or-other-pointer-position-passes-data-word.md), verbatim ---
cat > "$T/D18a.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
include "lib/fnptr.cyr"
fn f(s: Str): i64 { return str_len(s); }
fn main() {
    alloc_init();
    var t: Str = Str { "abcdefg", 7 };
    var h = str_from("abcdefg");
    return h.eq(t);          # Str_eq(self, other): `other` is untyped
}
var r = main();
syscall(SYS_EXIT, r);
EOF
runs D18a 1 "the filed repro: \`h.eq(t)\` — Str_eq's \`other: Str\` takes t's header (was 0)" "$XLEGS $OLEGS"
row D18b 'fn go(): i64 { var t: Str = Str { "abcdefg", 7 }; var p: *Str = t; return str_len(p); }'
runs D18b 7 "the filed table's \`var p: *Str = t; str_len(p)\` (was the data word)"
# D18c: `var p: *Str = gt;` is the header's address, so it is not warned "assigning non-pointer to typed pointer"
# (6.7.13 warned: the factor leaves an inline global's scale 0).
row D18c 'fn go(): i64 { var p: *Str = gt; return str_len(p); }'
rows=$((rows + 1))
for leg in $(legs); do
    compile "$leg" D18c
    if [ "$crc" -ne 0 ] || [ ! -s "$T/D18c.$leg" ]; then bad "D18c ($leg): did not build (rc $crc)"
    elif grep -q '^warning' "$T/D18c.$leg.err"; then bad "D18c ($leg): warned: $(grep '^warning' "$T/D18c.$leg.err" | head -1)"
    else ok "D18c \`var p: *Str = gt;\` ($leg): no warning"; fi
done
runs D18c 7 "\`var p: *Str = gt;\` takes gt's static address"

# --- D21: the filed repro 1 (issues/2026-10-15-top-level-str-declaration-from-inline-str-global-copies.md), verbatim ---
cat > "$T/D21a.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str) { return str_len(s); }
var gt: Str = Str { "abcdefg", 7 };
var H: Str = gt;
fn main() { H.len = 3; return f(H) * 10 + gt.len; }
var r = main();
syscall(SYS_EXIT, r);
EOF
runs D21a 33 "the filed repro 1: a zone \`var H: Str = gt;\` binds gt's header (was 37, a copy)" "$XLEGS $OLEGS"
sed 's/^var H: Str = gt;$/alloc_init();\nvar H: Str = gt;/' "$T/D21a.cyr" > "$T/D21b.cyr"
runs D21b 33 "the same after a first top-level statement (was 37)" "$XLEGS $OLEGS"
cat > "$T/D21c.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn f(s: Str) { return str_len(s); }
var H: Str = gt;
var gt: Str = Str { "abcdefg", 7 };
fn main() { return f(H); }
var r = main();
syscall(SYS_EXIT, r);
EOF
refused D21c "cannot copy-init 'H' from a global declared below it (declare the source first): 'gt'" "gt declared below H stays refused"

# --- CMP: a Str HANDLE passed to the five retyped methods compiles byte-identical to the untyped methods ---
rows=$((rows + 1))
cat > "$T/CMP.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/str.cyr"
fn main(): i64 {
    alloc_init();
    var h = str_from("abcdefg");
    var k = str_from("cde");
    var n = h.eq(k) + h.contains(k) + h.starts_with(k) + h.ends_with(k);
    return n * 100 + str_len(h.cat(k));
}
var r = main();
syscall(SYS_EXIT, r);
EOF
mkdir -p "$T/untyped"
cp -r lib "$T/untyped/lib"
sed -i -e 's/^fn Str_eq(self, other: Str)/fn Str_eq(self, other)/' -e 's/^fn Str_cat(self, other: Str)/fn Str_cat(self, other)/' \
    -e 's/^fn Str_contains(self, needle: Str)/fn Str_contains(self, needle)/' \
    -e 's/^fn Str_starts_with(self, prefix: Str)/fn Str_starts_with(self, prefix)/' \
    -e 's/^fn Str_ends_with(self, suffix: Str)/fn Str_ends_with(self, suffix)/' "$T/untyped/lib/str.cyr"
if [ "$(grep -cE '^fn Str_(eq|cat|contains|starts_with|ends_with)\(self, [a-z]+\)' "$T/untyped/lib/str.cyr")" != 5 ]; then
    bad "CMP: the untyped copy of lib/str.cyr does not hold the five untyped methods (lib/str.cyr changed?)"
else
    for leg in x86_64 pe; do
        compile "$leg" CMP
        cp "$T/CMP.$leg" "$T/CMP.$leg.typed"
        crc2=0
        case $leg in
            x86_64) (cd "$T/untyped" && timeout 60 "$CC" < "$T/CMP.cyr" > "$T/CMP.$leg.untyped" 2> /dev/null) || crc2=$? ;;
            pe)     (cd "$T/untyped" && CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$T/CMP.cyr" > "$T/CMP.$leg.untyped" 2> /dev/null) || crc2=$? ;;
        esac
        if [ "$crc" -ne 0 ] || [ "$crc2" -ne 0 ]; then bad "CMP ($leg): did not build (rc $crc / $crc2)"
        elif cmp -s "$T/CMP.$leg.typed" "$T/CMP.$leg.untyped"; then ok "CMP ($leg): a handle into the typed methods builds byte-identical"
        else bad "CMP ($leg): the typed methods changed a handle argument's code"; fi
    done
    if [ "$QEMU" -eq 1 ]; then
        compile aarch64 CMP
        crc2=0; (cd "$T/untyped" && timeout 60 "$A64" < "$T/CMP.cyr" > "$T/CMP.a64.untyped" 2> /dev/null) || crc2=$?
        if [ "$crc" -eq 0 ] && [ "$crc2" -eq 0 ] && cmp -s "$T/CMP.aarch64" "$T/CMP.a64.untyped"; then ok "CMP (aarch64): byte-identical"
        else bad "CMP (aarch64): differs or did not build (rc $crc / $crc2)"; fi
    fi
    if [ "$CX" -eq 1 ]; then
        compile cx CMP
        crc2=0; (cd "$T/untyped" && timeout 60 "$CXC" < "$T/CMP.cyr" > "$T/CMP.cx.untyped" 2> /dev/null) || crc2=$?
        if [ "$crc" -eq 0 ] && [ "$crc2" -eq 0 ] && cmp -s "$T/CMP.cx" "$T/CMP.cx.untyped"; then ok "CMP (cx): byte-identical"
        else bad "CMP (cx): differs or did not build (rc $crc / $crc2)"; fi
    fi
fi
runs CMP 110 "the handle program runs: (eq 0 + contains 1 + starts 0 + ends 0) * 100 + the cat's 10" "x86_64"

# --- AS1: an inline Str in an async fn (the coroutine's heap frame), across awaits ---
if [ -f lib/async.cyr ]; then
    printf 'include "lib/alloc.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/fnptr.cyr"\ninclude "lib/str.cyr"\ninclude "lib/async.cyr"\nfn f(s: Str): i64 { return str_len(s); }\nasync fn job(x): i64 { return x; }\nasync fn outer(x): i64 {\n    var t: Str = Str { "abcdefg", 7 };\n    var u = await job(x);\n    var h: Str = t;\n    var v = await job(f(t));\n    return u * 100 + v * 10 + str_len(h);\n}\nfn main(): i64 {\n    alloc_init();\n    var C = outer(1);\n    var r = 0;\n    var n = 0;\n    while (n < 4) { r = future_force(C); n = n + 1; }\n    return r %% 256;\n}\nvar rr = main();\nsyscall(60, rr);\n' > "$T/AS1.cyr"
    runs AS1 177 "an async fn: f(t) and var h: Str = t across awaits (1*100 + 7*10 + 7)" "x86_64:CYRIUS_ASYNC=1"
else echo "  SKIP AS1: no lib/async.cyr"; skips=$((skips + 1)); fi

FLOOR_ROWS=39
[ "$rows" -ge "$FLOOR_ROWS" ] || bad "only $rows rows ran (floor $FLOOR_ROWS) — rows were lost"
echo "  $rows rows, $fails failed, $skips skipped"
if [ "$fails" -ne 0 ]; then echo "FAIL: $G ($fails)"; exit 1; fi
echo "PASS: $G — an inline Str is its header's address where a Str value is taken; a frame's escaping it is refused by name"
