#!/bin/sh
# Gate: a struct value over 8 bytes is no multi-value `return ( .. )` element (6.7.16, the user's decision D90,
# 2026-10-20: "Refuse the element at the return").
#
# THE DEFECT (measured on 6.7.15 and the 6.7.16 lane before it, x86_64; the shared front end, every target): an element
# of `return (a, b[, c]);` is evaluated as one word, so a struct value handed back its FIRST word — `fn mv(): (Pt, i64)
# { .. return (b, 5); }` with a 16-byte `b` exited 14 (b.x 9 + 5; b.y gone), and the caller's binding passed on as a `Pt`
# (`take(b)`) was read as the struct's address: SIGSEGV. The same in a fn declared `: (i64, i64)` and in an undeclared
# one, from a struct-returning call (`return (mk(), 5)`), a method or operator result, a by-value field, `*p`, a
# by-value parameter, a global (issues/archived/2026-10-20-multi-value-struct-element-returns-its-first-word.md). Now ONE line
# at the element's first token: "'mv' returns struct 'Pt' (16 bytes) as a multi-value element - return its pointer, or
# its fields as elements" (`_mret_sval`, parse/expr.cyr), once per token (a generic's instances name the base, a method
# `P.mv`, a closure "a closure"), no latch (the statement reads on), silent under --syntax-only. The declaration
# `(Pt, i64)`, a word element, an 8-byte struct element (one word: it compiles and passes on whole), a `Str` (its name
# is the header's address), `&b`, a `*Pt` and `b.x` keep compiling; a tuple's and a dyn's own refusals stay theirs.
# A HANDLE named whole keeps compiling too (`_mret_hdl`): a struct local whose one slot holds the address (6.7.10's
# handle line: `var q: Pt = alloc(16);`, `var h: Pt = w;`) or a pointer-mode global — its word IS the struct's address,
# nothing is lost (it computed right before D90: tests/gates/codegen/small_struct_handle_line.sh C5), and D90 refuses
# nothing that computes correctly. The D90 bite refused it (M6e), which turned C5 red; fixed in its own commit.
#
#   M1  the filed mv.cyr verbatim                       M2  the filed `take(b)` program verbatim
#   M2b the filed `return b.y` program: the refusal, and the untyped binding's own line (unchanged)
#   M3  a fn declared `: (i64, i64)`                     M4  an undeclared fn
#   M5  `return (mk(), 5)`, a struct-returning call
#   M6  a by-value parameter, a value global, a by-value field `w.v`, `*pp`, `**ppp`, a method `b.dup()`, an operator
#       `b + b`, a wrapped `((b))`, the middle element of three, `Box<Pt>` (24 B) — each one line at its element
#   M7  a method `P8.mv` and a closure, named as the source spells them
#   M8  a generic `fn g<T>(x: T): (T, i64)` called with a Pt and a scalar — once, naming 'g'
#   M9  two struct elements — one line each        M10 the next fn's own error is reported (no latch)
#   M11 --syntax-only: silent, rc 0
#   M12 controls whose own refusal stays alone: a tuple `t`, a tuple field `w.t`, a dyn `d`, a dyn field `h.d`
#   K1-K4 acceptance, run on x86_64, aarch64 (qemu-aarch64), cx (the tree's cxvm) and PE (wine, a private prefix): an
#       8-byte struct element passed on whole (9); word, `&b`, `*Pt`, `b.x` and `Str` elements; the corpus's
#       `(Box<i64>, i64)` returning a word (tests/tcyr/frontend/nested_type_args.tcyr's shape); K4 a handle element —
#       `alloc(16)`, a word, wrapped, a pointer-mode global, the middle of three — its pointer, read through (20); K4b
#       (6.7.16, f16b FG4, the same fix landed beside it) a 16-byte handle local, wrapped, a handle global is its word
#
# Refusal rows compare the whole error / warning list and check that no binary was written, on five legs: the x86_64
# compiler, its PE (CYRIUS_TARGET_WIN=1) and Mach-O (CYRIUS_MACHO=1) legs, and the aarch64 and cx compilers built from
# this tree. A cross compiler that does not build is RED; a missing qemu-aarch64 or wine is a SKIP line by name.
#
# MUTATION LEDGER (2026-10-21, f16 FG3; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run
# from the copy so every leg's compiler carries the mutant):
#   `_bx_pcmpe_mret` on PCMPE again (the lane before) -> RED M1-M10 on every leg, 80 (each compiled, rc 0; M2b the
#                                                        binding's line alone, M10 the next fn's alone)
#   `_mret_sval` without `_mret_fld_rchk`             -> RED M12b M12c on every leg, 10 (the armed record stood the
#                                                        tuple / dyn field's own refusal down: `w.t` COMPILED)
#   `_mret_sval_err` without its closure arm          -> RED M7 on every leg, 5 ('__cl00NNN' named)
#   `_mret_sval` refusing an 8-byte struct            -> RED K1 on every leg, 5
#   `_mret_sval` without `_mret_hdl` (the D90 bite)   -> RED K4 on every leg, 5 (and small_struct_handle_line.sh C5)
#
# ⛔ 6.7.17 (D25 A, the user's decision, 2026-10-22: "Refuse it at the element") — A VECTOR VALUE IS NO ELEMENT EITHER.
# `fn two(): (f64v2, i64) { var v = mk2(41, 7); return (v, 3); }` handed back v's lane 0 — the filed repro exited 44 (a
# = 41) on x86_64, aarch64, cx and PE — and a parameter, a capture and `*pv` the same. Now one line at the element in
# D90's shape (`_mret_vval`, parse/expr.cyr; the vector value read by `_vval_at`, parse/decl/vector.cyr): "'two' returns vector
# 'f64v2' (16 bytes) as a multi-value element - return its pointer, or its lanes as elements". Rows V1 (the filed repro
# verbatim) - V6, V7 the control (a vector CALL as the element keeps 6.7.16's D100 words), V9 a `*V` global's
# dereference in a program with no vector local (the scan's mark, `_gv_pvd_set`), V8 --syntax-only, K5 the
# declaration `(f64v2, i64)` still compiling and a vector's lanes / pointer as elements (92). Mutations (2026-10-22, a
# scratch copy of the tree, this gate run from it):
#   `_mret_sval` without `_mret_vval` (the tree before) -> RED V1-V6 on every leg, 30 (each compiled, rc 0; V6 the next
#                                                        fn's line alone)
#   `_vval_at` without its dereference arm              -> RED V3 on every leg, 5
#   `_vnm_lty` without its capture arm                  -> RED V4 on every leg, 5 (the closure's line missing)
#
# Exit 77 = could not run (the SKIP protocol): no compiler, or no scratch directory.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=mret_struct_element_refused
[ -x "$CC" ] || { echo "SKIP: $G: compiler $CC missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "SKIP: $G: mktemp -d failed"; exit 77; }
# A PRIVATE wine prefix under $D (never ~/.wine), torn down with its server dir on exit.
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
ulimit -c 0 2>/dev/null || true

pass=0; fail=0; skips=0
ok()  { echo "  ok   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL $1"; fail=$((fail + 1)); }

LEGS="x86 pe macho"
if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then chmod +x "$D/cc_a64"; LEGS="$LEGS a64"
else bad "aarch64: src/main_aarch64.cyr did not build"; fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then chmod +x "$D/cc_cx" "$D/cxvm"; LEGS="$LEGS cx"
else bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
QEMU=0; WINE=0
if command -v qemu-aarch64 > /dev/null 2>&1; then QEMU=1
else echo "  SKIP: the aarch64 run leg (qemu-aarch64 not installed; its refusal rows still run)"; skips=$((skips + 1)); fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: the PE run leg (wine not installed; its refusal rows still run)"; skips=$((skips + 1)); fi

# comp <leg> <src> <out> [cc-arg]: the rc in CRC
comp() {
    CRC=0
    case "$1" in
        x86)   timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        pe)    CYRIUS_TARGET_WIN=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        macho) CYRIUS_MACHO=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        a64)   timeout 60 "$D/cc_a64" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        cx)    timeout 60 "$D/cc_cx" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
    esac
}
# execute <leg> <binary>: the exit in XRC, -1 = not run (NOTE says why)
execute() {
    XRC=-1; NOTE=""
    case "$1" in
        x86)   chmod +x "$2"; XRC=0; timeout 60 "$2" > /dev/null 2>&1 || XRC=$? ;;
        a64)   if [ "$QEMU" = 1 ]; then chmod +x "$2"; XRC=0; timeout 120 qemu-aarch64 "$2" > /dev/null 2>&1 || XRC=$?
               else NOTE="qemu-aarch64 not installed"; fi ;;
        cx)    XRC=0; timeout 120 "$D/cxvm" < "$2" > /dev/null 2>&1 || XRC=$? ;;
        pe)    if [ "$WINE" = 1 ]; then
                   cp "$2" "$2.exe"; XRC=0
                   (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                       WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "$2.exe" > /dev/null 2>&1) || XRC=$?
               else NOTE="wine not installed"; fi ;;
        macho) NOTE="no Mach-O loader on Linux" ;;
    esac
}
N=0
# row <id> <what> <source> <want error / warning lines> [cc-arg]: refused on every leg, the lines exactly, no binary
row() {
    printf '%s' "$3" > "$D/$1.cyr"
    printf '%s\n' "$4" > "$D/$1.want"
    for leg in $LEGS; do
        o="$D/$1_$leg"; comp "$leg" "$D/$1.cyr" "$o" "${5:-}"; N=$((N + 1))
        grep -E '^(error|warning)' "$o.err" > "$o.got" || true
        if [ "$CRC" -eq 0 ]; then bad "$1 [$leg]: $2: rc 0 (compiled)"
        elif ! cmp -s "$o.got" "$D/$1.want"; then bad "$1 [$leg]: $2: got $(wc -l < "$o.got") line(s): $(tr '\n' '|' < "$o.got")"
        elif [ -s "$o" ]; then bad "$1 [$leg]: $2: refused, but a binary was written"
        else ok "$1 [$leg]: $2"; fi
    done
}
# quiet <id> <what> <source>: --syntax-only on every leg is rc 0 with no error / warning line
quiet() {
    printf '%s' "$3" > "$D/$1.cyr"
    for leg in $LEGS; do
        o="$D/$1_$leg"; comp "$leg" "$D/$1.cyr" "$o" --syntax-only; N=$((N + 1))
        if [ "$CRC" -ne 0 ] || grep -qE '^(error|warning)' "$o.err"; then bad "$1 [$leg]: $2: rc $CRC: $(grep -E '^(error|warning)' "$o.err" | tr '\n' '|')"
        else ok "$1 [$leg]: $2"; fi
    done
}
# runs <id> <what> <source> <exit>: compiles clean on every leg, runs <exit> wherever a runner is
runs() {
    printf '%s' "$3" > "$D/$1.cyr"
    for leg in $LEGS; do
        o="$D/$1_$leg"; comp "$leg" "$D/$1.cyr" "$o"; N=$((N + 1))
        if [ "$CRC" -ne 0 ] || [ ! -s "$o" ] || grep -qE '^(error|warning)' "$o.err"; then
            bad "$1 [$leg]: $2: rc $CRC: $(grep -E '^(error|warning)' "$o.err" | tr '\n' '|')"; continue
        fi
        execute "$leg" "$o"
        if [ "$XRC" = -1 ]; then ok "$1 [$leg]: $2 (compiled; not run: $NOTE)"
        elif [ "$XRC" = "$4" ]; then ok "$1 [$leg]: $2 (exit $XRC)"
        else bad "$1 [$leg]: $2: exit $XRC, want $4"; fi
    done
}
E="as a multi-value element - return its pointer, or its fields as elements"
PT="returns struct 'Pt' (16 bytes) $E"
H='include "lib/syscalls.cyr"
struct Pt { x; y; }
struct P8 { v; }
struct W { v: Pt; t: (i64, i64); k; }
impl Pt { fn dup(self): Pt { var q: Pt; q.x = self.x; q.y = self.y; return q; } }
fn Pt_add(a: Pt, b: Pt): Pt { var q: Pt; q.x = a.x + b.x; q.y = a.y + b.y; return q; }
fn mk(): Pt { var q: Pt; q.x = 9; q.y = 4; return q; }
'
# hm <mv's definition> [main body]: the header, a definition at line 8, a main reading two values
hm() { printf '%s%s\nfn main(): i64 { var a, c = mv(); return c; }\nsyscall(60, main());\n' "$H" "$1"; }
# hm3 <mv's definition>: the same for a three-value mv
hm3() { printf '%s%s\nfn main(): i64 { var a, c, d = mv(); return c; }\nsyscall(60, main());\n' "$H" "$1"; }

echo "M — a struct value over 8 bytes as a return element is one line at the element, on every leg ($LEGS):"
row M1 "the filed mv.cyr verbatim (it ran 14: b.x + 5, b.y gone)" 'include "lib/syscalls.cyr"
struct Pt { x; y; }
fn mv(): (Pt, i64) { var b: Pt; b.x = 9; b.y = 4; return (b, 5); }
fn main(): i64 { var b, c = mv(); return b + c; }
syscall(60, main());
' "error:<source>:3:59: 'mv' $PT"
row M2 "the filed take(b) program verbatim (it faulted: SIGSEGV)" 'include "lib/syscalls.cyr"
struct Pt { x; y; }
fn mv(): (Pt, i64) { var b: Pt; b.x = 9; b.y = 4; return (b, 5); }
fn take(p: Pt): i64 { return p.y; }
fn main(): i64 { var b, c = mv(); return take(b); }
syscall(60, main());
' "error:<source>:3:59: 'mv' $PT"
row M2b "the filed return b.y program: the refusal, and the untyped binding's own line (as before)" 'include "lib/syscalls.cyr"
struct Pt { x; y; }
fn mv(): (Pt, i64) { var b: Pt; b.x = 9; b.y = 4; return (b, 5); }
fn main(): i64 { var b, c = mv(); return b.y; }
syscall(60, main());
' "error:<source>:3:59: 'mv' $PT
error:<source>:4:45: no struct type in scope for 'b'; a '.field' access needs its struct declaration (missing include?)"
row M3 "a fn declared : (i64, i64)" "$(hm 'fn mv(): (i64, i64) { var b: Pt; b.x = 9; return (b, 5); }')" "error:<source>:8:51: 'mv' $PT"
row M4 "an undeclared multi-value fn" "$(hm 'fn mv() { var b: Pt; b.x = 9; return (b, 5); }')" "error:<source>:8:39: 'mv' $PT"
row M5 "return (mk(), 5) — a struct-returning call" "$(hm 'fn mv(): (Pt, i64) { return (mk(), 5); }')" "error:<source>:8:30: 'mv' $PT"
row M6a "a by-value parameter" "$H"'fn mv(p: Pt): (i64, i64) { return (p, 5); }
fn main(): i64 { var b: Pt; var a, c = mv(b); return c; }
syscall(60, main());
' "error:<source>:8:36: 'mv' $PT"
row M6b "a value global" "$H"'var G: Pt = Pt { 9, 4 };
fn mv(): (i64, i64) { return (G, 5); }
fn main(): i64 { var a, c = mv(); return c; }
syscall(60, main());
' "error:<source>:9:31: 'mv' $PT"
row M6c "a by-value field w.v, *pp, **ppp" "$(hm3 'fn mv(): (i64, i64, i64) { var w: W; w.v.x = 9; var b: Pt; var pp: *Pt = &b; var ppp: **Pt = &pp; return (w.v, *pp, **ppp); }')" "error:<source>:8:107: 'mv' $PT
error:<source>:8:112: 'mv' $PT
error:<source>:8:117: 'mv' $PT"
row M6d "a method result b.dup(), an operator result b + b, a wrapped ((b))" "$(hm3 'fn mv(): (i64, i64, i64) { var b: Pt; b.x = 9; return (b.dup(), b + b, ((b))); }')" "error:<source>:8:56: 'mv' $PT
error:<source>:8:65: 'mv' $PT
error:<source>:8:72: 'mv' $PT"
row M6e "the middle element of three" "$(hm3 'fn mv(): (i64, i64, i64) { var q: Pt; q.x = 9; return (1, q, 5); }')" "error:<source>:8:59: 'mv' $PT"
row M6g "an inline value var q = Pt { 9, 0 }, the middle element of three" "$(hm3 'fn mv(): (i64, i64, i64) { var q = Pt { 9, 0 }; return (1, q, 5); }')" "error:<source>:8:60: 'mv' $PT"
row M6f "a generic instance Box<Pt> (24 B)" "$H"'struct Box<T> { v: T; n; }
fn mv(): (i64, i64) { var b: Box<Pt>; b.n = 9; return (b, 5); }
fn main(): i64 { var a, c = mv(); return c; }
syscall(60, main());
' "error:<source>:9:56: 'mv' returns struct 'Box<Pt>' (24 bytes) $E"
row M7 "a method P8.mv and a closure, named as written" "$H"'impl P8 { fn mv(self): (Pt, i64) { var b: Pt; b.x = 9; return (b, 5); } }
fn cl(): i64 { var b: Pt; b.x = 9; var f = || { return (b, 5); }; return 1; }
fn main(): i64 { var o: P8; var a, c = o.mv(); return c + cl(); }
syscall(60, main());
' "error:<source>:8:64: 'P8.mv' $PT
error:<source>:9:57: a closure $PT"
row M8 "a generic fn g<T>(x: T): (T, i64) called with a Pt and a scalar — once, naming g" "$H"'fn g<T>(x: T): (T, i64) { return (x, 5); }
fn main(): i64 { var b: Pt; b.x = 9; var a, c = g(b); var d, e = g(3); var f, h = g<Pt>(b); return c + d; }
syscall(60, main());
' "error:<source>:8:35: 'g' $PT"
row M9 "two struct elements — one line each" "$(hm 'fn mv(): (i64, i64) { var b: Pt; b.x = 9; return (b, mk()); }')" "error:<source>:8:51: 'mv' $PT
error:<source>:8:54: 'mv' $PT"
row M10 "the statement reads on: the next fn's own error is reported" "$H"'fn mv(): (i64, i64) { var b: Pt; b.x = 9; return (b, 5); }
fn h(): i64 { return zz; }
fn main(): i64 { var a, c = mv(); return c + h(); }
syscall(60, main());
' "error:<source>:8:51: 'mv' $PT
error:<source>:9:22: undefined variable 'zz' (missing include or enum?)"
quiet M11 "--syntax-only says nothing (M1, M5, M6c)" "$(hm3 'fn mv(): (i64, i64, i64) { var w: W; w.v.x = 9; var b: Pt; var pp: *Pt = &b; return (w.v, *pp, mk()); }')"
row M12a "control: a tuple t keeps its own line alone" "$(hm 'fn mv(): (i64, i64) { var t = (1, 2); return (t, 5); }')" "error:<source>:8:47: tuple 't' used as a value - take an element (\`t.0\`) or copy it whole into a tuple"
row M12b "control: a tuple field w.t keeps its own line alone" "$(hm 'fn mv(): (i64, i64) { var w: W; w.k = 1; return (w.t, 5); }')" "error:<source>:8:52: tuple field 't' used as a value - take an element (\`.0\`) or copy it whole into a tuple"
row M12c "control: a dyn d and a dyn field h.d keep their own lines alone" "$H"'trait Sh { fn sh(self): i64; }
impl Sh for Pt { fn sh(self): i64 { return self.y; } }
struct Hd { d: dyn Sh; k; }
fn mv(): (i64, i64) { var b: Pt; var d: dyn Sh = &b; return (d, 5); }
fn mw(q: *Hd): (i64, i64) { return (q.d, 5); }
fn main(): i64 { var a, c = mv(); return c; }
syscall(60, main());
' "error:<source>:11:62: dyn Sh 'd' used as a value - call one of its methods, or copy it whole into a dyn
error:<source>:12:39: dyn Sh 'd' (a field) used as a value - call one of its methods, or copy it whole into a dyn"

EV="as a multi-value element - return its pointer, or its lanes as elements"
VH='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mk4(a): f64v4 { var v: f64v4; store64(&v, a); return v; }
'
echo "V — (6.7.17, D25) a vector value as a return element is one line at the element, in D90's shape, on every leg ($LEGS):"
row V1 "the filed repro verbatim (it ran 44: a = lane 0, 41)" 'fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn rd(p): i64 { return load64(p) * 10 + load64(p + 8); }
fn take(t): i64 { return t; }
fn two(): (f64v2, i64) { var v = mk2(41, 7); return (v, 3); }
fn r(): i64 { var a, b = two(); return a + b; }
syscall(60, r());
' "error:<source>:4:54: 'two' returns vector 'f64v2' (16 bytes) $EV"
row V2 "a fn declared : (i64, i64), a by-value vector parameter; an undeclared fn, an f32v4 local" "$VH"'fn mv(x: f64v2): (i64, i64) { return (3, x); }
fn mu() { var w: f32v4; return (1, w, 3); }
fn main(): i64 { var a, c = mv(mk2(1, 2)); var d, e, f = mu(); return c + d; }
syscall(60, main());
' "error:<source>:5:42: 'mv' returns vector 'f64v2' (16 bytes) $EV
error:<source>:6:36: 'mu' returns vector 'f32v4' (16 bytes) $EV"
row V3 "a dereference of a pointer to a vector: *pv, **ppv, *(&w) of an f64v4" "$VH"'fn mv(pv: *f64v2, ppv: **f64v2): (i64, i64, i64) { var w: f64v4 = mk4(1); return (*pv, **ppv, *(&w)); }
fn main(): i64 { var v: f64v2 = mk2(1, 2); var pv: *f64v2 = &v; var a, c, d = mv(pv, &pv); return c; }
syscall(60, main());
' "error:<source>:5:83: 'mv' returns vector 'f64v2' (16 bytes) $EV
error:<source>:5:88: 'mv' returns vector 'f64v2' (16 bytes) $EV
error:<source>:5:95: 'mv' returns vector 'f64v4' (32 bytes) $EV"
row V4 "wrapped ((w)) of an i16v8, a method P.mv and a closure's capture, named as written" "$VH"'struct P { k; }
impl P { fn mv(self): (i64, i64) { var w: i16v8; return (((w)), 5); } }
fn cl(): i64 { var b: f64v2 = mk2(1, 2); var f = |k| { return (b, k); }; return 1; }
fn main(): i64 { var o: P; var a, c = o.mv(); return c + cl(); }
syscall(60, main());
' "error:<source>:6:58: 'P.mv' returns vector 'i16v8' (16 bytes) $EV
error:<source>:7:64: a closure returns vector 'f64v2' (16 bytes) $EV"
row V5 "a generic g<T> called at two types — once, naming g" "$VH"'fn g<T>(x: T): (i64, i64) { var w: f64v2 = mk2(x, 1); return (w, 5); }
fn main(): i64 { var a, c = g(1); var d, e = g<i32>(2); return c + e; }
syscall(60, main());
' "error:<source>:5:63: 'g' returns vector 'f64v2' (16 bytes) $EV"
row V6 "the statement reads on: the next fn's own error is reported" "$VH"'fn mv(): (i64, i64) { var w: f64v2 = mk2(41, 7); return (w, 5); }
fn h(): i64 { return zz; }
fn main(): i64 { var a, c = mv(); return c + h(); }
syscall(60, main());
' "error:<source>:5:58: 'mv' returns vector 'f64v2' (16 bytes) $EV
error:<source>:6:22: undefined variable 'zz' (missing include or enum?)"
row V7 "control: a vector CALL as the element keeps D100's words (6.7.16's VO54)" "$VH"'fn mv(): (i64, i64) { return (mk2(41, 7), 3); }
fn main(): i64 { var a, c = mv(); return c; }
syscall(60, main());
' "error:<source>:5:31: vector return type does not match the declared type"
row V9 "a dereference of a *V global in a program with no vector local (6.7.17: the scan's mark)" 'include "lib/syscalls.cyr"
var GW: f64v2 = 0;
var GP: *f64v2 = &GW;
fn two(): (i64, i64) { return (*GP, 3); }
fn main(): i64 { var a, b = two(); return b; }
syscall(60, main());
' "error:<source>:4:32: 'two' returns vector 'f64v2' (16 bytes) $EV"
quiet V8 "--syntax-only says nothing (V1, V3)" "$VH"'fn mv(pv: *f64v2): (i64, i64) { var w: f64v2 = mk2(41, 7); return (w, *pv); }
fn main(): i64 { var v: f64v2 = mk2(1, 2); var a, c = mv(&v); return c; }
syscall(60, main());
'

echo "K — what computes correctly keeps compiling and running, on every leg ($LEGS):"
runs K1 "an 8-byte struct element is one word: passed on whole (9)" 'include "lib/syscalls.cyr"
struct P8 { v; }
fn mv(): (P8, i64) { var b: P8; b.v = 9; return (b, 5); }
fn take(p: P8): i64 { return p.v; }
fn main(): i64 { var b, c = mv(); return take(b); }
syscall(60, main());
' 9
runs K2 "word, *Pt, b.x, q.y and Str elements (44)" 'include "lib/syscalls.cyr"
include "lib/str.cyr"
struct Pt { x; y; }
fn mw(a): (i64, i64) { return (a, 5); }
fn mp(): (i64, i64, i64) { var b: Pt; b.x = 9; b.y = 4; var q: *Pt = &b; return (b.x, q.y, 3); }
fn ma(p: *Pt): (*Pt, i64) { var q: *Pt = p; return (q, 5); }
fn ms(): (Str, i64) { var s: Str = str_from("abc"); return (s, 2); }
fn main(): i64 {
    var b: Pt; b.x = 20; b.y = 1;
    var a, c = mw(7);
    var x, y, z = mp();
    var p, k = ma(&b);
    var s, n = ms();
    return a + c + x + y + z + load64(p) - k + str_len(s) - n;
}
syscall(60, main());
' 44
runs K4 "a HANDLE element is its pointer: var q: Pt = alloc(16), var h: Pt = w (a word), ((q)), a pointer-mode global, the middle of three — the caller reads the fields through it (small_struct_handle_line.sh C5's shape; 4 + 4 + 4 + 4 + 4)" 'include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct Pt { x; y; }
var GH: Pt = 0;
fn m1(): (Pt, i64) { var q: Pt = alloc(16); q.x = 9; q.y = 4; return (q, 5); }
fn m2(w): (i64, i64) { var h: Pt = w; return (h, 5); }
fn m3(): (i64, i64) { var q: Pt = alloc(16); q.y = 4; return (((q)), 5); }
fn m4(): (i64, i64) { return (GH, 5); }
fn m5(): (i64, i64, i64) { var q: Pt = alloc(16); q.y = 4; return (1, q, 5); }
fn main(): i64 {
    var a1, c1 = m1();
    var w = alloc(16); store64(w + 8, 4);
    var a2, c2 = m2(w);
    var a3, c3 = m3();
    GH = alloc(16); GH.y = 4;
    var a4, c4 = m4();
    var b5, a5, c5 = m5();
    return load64(a1 + 8) + load64(a2 + 8) + load64(a3 + 8) + load64(a4 + 8) + load64(a5 + 8);
}
alloc_init();
syscall(60, main());
' 20
runs K3 "the corpus's (Box<i64>, i64) returning a word (nested_type_args.tcyr's shape)" 'include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
fn mv(): (Box<i64>, i64) { return (3, 4); }
fn main(): i64 { var a, b = mv(); return a + b; }
syscall(60, main());
' 7
runs K5 "(6.7.17, D25) the declaration (f64v2, i64) still compiles; a vector's pointer and its lanes as elements pass on (41 + 7 + 41 + 3 = 92)" 'include "lib/syscalls.cyr"
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn two(): (f64v2, i64) { var v = mk2(41, 7); return (load64(&v), 3); }
fn lanes(p): (i64, i64) { return (load64(p), load64(p + 8)); }
fn ptr(pv: *f64v2): (*f64v2, i64) { return (pv, 2); }
fn main(): i64 { var w: f64v2 = mk2(41, 7); var a, b = two(); var c, d = lanes(&w); var p, k = ptr(&w); return c + d + load64(p) + b + k - 2; }
syscall(60, main());
' 92
runs K4b "a 16-byte handle element is its word: a local, wrapped, a handle global (6.7.16)" 'include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct Pt { x; y; }
var GQ: Pt = 0;
fn mv(): (i64, i64, i64) { var q: Pt = alloc(16); q.x = 9; return (1, q, 5); }
fn mw(): (i64, i64) { var q: Pt = alloc(16); q.y = 4; return ((q), 2); }
fn mg(): (i64, i64) { GQ = alloc(16); GQ.x = 7; return (GQ, 3); }
fn main(): i64 {
    alloc_init();
    var a, c, d = mv();
    var e, f = mw();
    var g, h = mg();
    return load64(c) + load64(e + 8) + load64(g) + a + d + f + h;
}
syscall(60, main());
' 31

# The floor: 27 refusal rows, 2 quiet rows and 7 acceptance rows on five legs (6.7.17: + V1-V7, V9, V8, K5). A leg that did
# not build is RED above.
FLOOR=180
[ "$N" -ge "$FLOOR" ] || bad "the rows ran $N row-legs (floor $FLOOR) — rows or legs were lost"
echo "$G: $pass passed, $fail failed, $skips skipped"
[ "$fail" -eq 0 ] || exit 1
exit 0
