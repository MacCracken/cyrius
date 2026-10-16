#!/bin/sh
# Gate: an INLINE `Str` is its header's address wherever a `Str` value is taken (6.7.13, the user's
# decision D7 (1), 2026-10-15; issues/2026-10-12-inline-str-local-passed-to-str-param-wrong-value.md).
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
# no `Str` value (an untyped parameter, store or fn return) keeps the word (K5, K6). A `var t: Str;` declared
# with NO initialiser is outside the decision (worded for `var t: Str = Str { .. }`): its bare name stays its
# first word, as through 6.7.12, so 6.6.16's pun `t = a; str_len(t)` reads a's string (U1, U2; the review fix,
# 2026-10-16 — the lane had widened D7 (1) to it and the pun read t's unwritten length: 0 where 5 is right).
#
# ROWS: R0 the filed repro verbatim; R1 tests/tcyr/crossos/inline_str_value.tcyr (its row count derived,
# floor 47) on x86_64 (plain, CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu — EMULATION, not
# hardware), cx (cxvm) and PE (wine, a private prefix); X1-X2 and X4-X13 refused (the message first, ONE
# `^error`, no warning, no binary) on the x86_64, aarch64, cx and PE compilers; K1-K7 controls that compile and
# run on every leg; U1-U2 a bare `var t: Str;` keeps its word on every leg; AS1 an inline `Str` in an
# `async fn` across awaits (x86_64, CYRIUS_ASYNC=1).
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
FLOOR=47
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

# --- U: `var t: Str;` with no initialiser keeps its first word (outside D7 (1)), as through 6.7.12 ---
row U1 'fn go(): i64 { var t: Str; t = str_from("hello"); return str_len(t); }'
runs U1 5 "\`var t: Str; t = a; str_len(t)\` — the 6.6.16 pun reads a's string (the lane read t's unwritten length)"
row U2 'fn g(c): i64 { var t: Str; if (c == 1) { t = str_from("abc"); } else { t = str_from("de"); } return str_len(t); }
fn go(): i64 { return g(1); }'
runs U2 3 "\`var t: Str;\` assigned in one branch (the lane read t's unwritten length)"

# --- AS1: an inline Str in an async fn (the coroutine's heap frame), across awaits ---
if [ -f lib/async.cyr ]; then
    printf 'include "lib/alloc.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/fnptr.cyr"\ninclude "lib/str.cyr"\ninclude "lib/async.cyr"\nfn f(s: Str): i64 { return str_len(s); }\nasync fn job(x): i64 { return x; }\nasync fn outer(x): i64 {\n    var t: Str = Str { "abcdefg", 7 };\n    var u = await job(x);\n    var h: Str = t;\n    var v = await job(f(t));\n    return u * 100 + v * 10 + str_len(h);\n}\nfn main(): i64 {\n    alloc_init();\n    var C = outer(1);\n    var r = 0;\n    var n = 0;\n    while (n < 4) { r = future_force(C); n = n + 1; }\n    return r %% 256;\n}\nvar rr = main();\nsyscall(60, rr);\n' > "$T/AS1.cyr"
    runs AS1 177 "an async fn: f(t) and var h: Str = t across awaits (1*100 + 7*10 + 7)" "x86_64:CYRIUS_ASYNC=1"
else echo "  SKIP AS1: no lib/async.cyr"; skips=$((skips + 1)); fi

FLOOR_ROWS=24
[ "$rows" -ge "$FLOOR_ROWS" ] || bad "only $rows rows ran (floor $FLOOR_ROWS) — rows were lost"
echo "  $rows rows, $fails failed, $skips skipped"
if [ "$fails" -ne 0 ]; then echo "FAIL: $G ($fails)"; exit 1; fi
echo "PASS: $G — an inline Str is its header's address where a Str value is taken; a frame's escaping it is refused by name"
