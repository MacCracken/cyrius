#!/bin/sh
# tests/gates/frontend/intrinsic_names_reserved.sh — 6.6.20
#
# The identifier-spelled intrinsics — `sizeof`, `mulh64` (_is_ident_intrinsic, parse.cyr) and
# `fncall0`..`fncall8` (_IS_FNCALL_NAME, parse_expr.cyr) — are RESERVED NAMES. They lex as
# plain IDENTs and are lowered by NAME at the call, so they sit in neither of util.cyr's
# reserved tables and nothing refused them as a declaration. Measured before 6.6.20:
#   * `fn mulh64(a, b) { return 77; }` compiled (rc 0, the fn "unreachable") and
#     `mulh64(2^62, 8)` returned the INTRINSIC's high word, 2 — on x86 and on aarch64;
#   * `fn fncall1(a, b) { return 77; }` compiled and `fncall1(5, 6)` called THROUGH 5: SIGSEGV;
#   * `fn sizeof()` / `var sizeof` / a param `mulh64` declared, and every use was a parse error
#     about a `(` nobody wrote (`expected '(', got '+'`).
#
# AXIS 1 — a fn of each of the 11 names is refused BY NAME at the name, exit 1, no binary,
#   exactly ONE diagnostic.
# AXIS 2 — every other declaration form is refused the same way: param, generic param (judged
#   once, not again per instance), closure param, local var, top-level var (declaration zone and
#   after top-level code), each name of a local / global destructure, `stack var`, `secret var`,
#   a `for` binding, and a `use mod.NAME;` alias — which binds the BARE name, so a mangled
#   `m_mulh64` re-exposed by `use m.mulh64;` ran the intrinsic (2) and `use m.fncall1;` SIGSEGV'd,
#   the two filed defects again — and a PAYLOAD enum variant, whose constructor is a fn under the
#   bare variant name (heap `mulh64(a, b)` ran 2; a `: stack` `fncall1(a)` with no include SIGSEGV'd).
# AXIS 3 — THE ONE LEGITIMATE DECLARER: lib/fnptr.cyr's fncall0..8 ARE the lowering's enabler
#   (it is gated on FINDFN) and cybs calls them in gen1, so an included file whose BASENAME is
#   `fnptr.cyr` may declare them — from lib/, from another directory, or bare. The exemption is
#   the file, not the content: the same bytes as `myptr.cyr` or `notfnptr.cyr` are refused, and a
#   user `fn fncall1` beside an included lib/fnptr.cyr is still refused. And lib/fnptr.cyr fed
#   AS THE ENTRY is refused, deliberately (the main source has no name; exempting it is the
#   filed repro's own shape): pinned so that is a decision, not an accident.
# AXIS 4 — ANTI-VACUOUS: the intrinsics still work (fncallN in an expression, as a statement
#   and at top level; mulh64; sizeof), near-misses (`mulh64x`, `fncall9`, `sizeofx`, `fncall`)
#   are ordinary names, a mangled definition — an impl method `sizeof`, a `mod` fn — is accepted
#   (only its bare re-exposure by `use` is refused), `use m.foo;` of an ordinary name still
#   aliases, a UNIT enum variant `mulh64 = 77` read as `E.mulh64` runs 77, and an ordinary payload
#   variant still constructs. And a NUMBER where a name belongs is still the plain
#   `expected identifier` error, never a fault.
#
# MUTATION PROOF (6.6.20):
#   * parse.cyr _RSV_INTRINSIC_DECL: `return 0;` first   -> axes 1 + 2 RED (mh_fn exits 0 and runs 2,
#     fc_fn compiles and SIGSEGVs).
#   * parse.cyr _rsv_in_fnptr: `return 0;` first          -> axis 3/4 RED (lib/fnptr.cyr refused).
#   * parse.cyr _rsv_in_fnptr: `return 1;` first          -> axis 1 + 3 RED (fc*_fn, myptr, notfnptr,
#     user_beside_lib and fnptr_entry all compile; 52 RED).
#   * parse_fn_def.cyr: the fn-name call AFTER `_mod_name_intern` moved BEFORE it -> axis 4 RED (impl
#     method `sizeof` refused).
#   * parse.cyr _RSV_INTRINSIC_DECL: the `TOKTYP(S, ti) != 2` guard dropped -> the three
#     number-as-a-name rows RED (rc 139: the number was read as a name-pool offset).
#   * parse_fn_def.cyr _tl_use: the _RSV_INTRINSIC_DECL call dropped -> the four use_* rows RED, 14
#     assertions (use_mh / use_mh_top compile and run 2, use_fc compiles and SIGSEGVs, use_sz is
#     only the bare `expected identifier` parse error).
#   * parse_types.cyr PARSE_ENUM_DEF: the _RSV_INTRINSIC_DECL call dropped -> the six en_* rows RED,
#     24 assertions (each compiles rc 0 and emits a binary).
#   Re-measured with the enum rows: refusal disabled 162 RED (= the 6.6.19 compiler); exemption
#   never / always 17 / 52; _tl_use call dropped 14.
#
# Exit 77 = could not run (no compiler); never 0 for that.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: intrinsic_names_reserved — $CC not built"; exit 77; }
[ -f "$ROOT/lib/fnptr.cyr" ] || { echo "SKIP: intrinsic_names_reserved — lib/fnptr.cyr missing"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "SKIP: intrinsic_names_reserved: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 77; }
trap 'rm -rf "$T"' EXIT   # axis 5 widens it to stop its wine server
# Includes resolve from the CWD under raw `cycc` (no #@incdir marker), so every compile runs in $T,
# which carries lib/fnptr.cyr and the renamed copies.
mkdir -p "$T/lib" "$T/sub"
cp "$ROOT/lib/fnptr.cyr" "$T/lib/fnptr.cyr"
cp "$ROOT/lib/fnptr.cyr" "$T/sub/fnptr.cyr"
cp "$ROOT/lib/fnptr.cyr" "$T/fnptr.cyr"
cp "$ROOT/lib/fnptr.cyr" "$T/sub/myptr.cyr"
cp "$ROOT/lib/fnptr.cyr" "$T/sub/notfnptr.cyr"
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}
# refused <name> <printf-fmt> <reserved-name> [<count>]
refused() {
    printf '%b' "$2" > "$T/$1.cyr"
    judged_refused "$1" "$3" "${4:-1}"
}
# judged_refused <name> <reserved-name> <count> — compiles $T/<name>.cyr as the main source.
judged_refused() {
    rc=0
    (cd "$T" && "$CC" < "$1.cyr" > "$1.out" 2> "$1.err") || rc=$?
    check "$1: exits 1" 1 "$rc"
    check "$1: names '$2'" yes "$(grep -qF -- "reserved intrinsic name '$2'" "$T/$1.err" && echo yes || echo no)"
    check "$1: diagnostics" "$3" "$(grep -c 'reserved intrinsic name' "$T/$1.err")"
    check "$1: emits no binary" 0 "$(wc -c < "$T/$1.out" | tr -d ' ')"
}
# runs <name> <printf-fmt> <want-exit>
runs() {
    printf '%b' "$2" > "$T/$1.cyr"
    rc=0
    (cd "$T" && "$CC" < "$1.cyr" > "$1" 2> "$1.err") || rc=$?
    check "$1: compiles" 0 "$rc"
    check "$1: no reserved-name diagnostic" 0 "$(grep -c 'reserved intrinsic name' "$T/$1.err")"
    chmod +x "$T/$1"
    rc=0; "$T/$1" || rc=$?
    check "$1: exits $3" "$3" "$rc"
}

echo "axis 1 — a fn named for an identifier intrinsic is refused at its name:"
# The two filed repros, verbatim: each used to compile (rc 0) and run wrong (2 / SIGSEGV).
refused mh_fn 'fn mulh64(a, b): i64 { return 77; }\nfn main(): i64 { return mulh64(4611686018427387904, 8); }\nsyscall(60, main());\n' mulh64
refused fc_fn 'fn fncall1(a, b): i64 { return 77; }\nfn main(): i64 { return fncall1(5, 6); }\nsyscall(60, main());\n' fncall1
refused sz_fn 'fn sizeof(): i64 { return 77; }\nsyscall(60, 1);\n' sizeof
for d in 0 2 3 4 5 6 7 8; do
    refused "fc${d}_fn" "fn fncall$d(a): i64 { return a; }\\nsyscall(60, 1);\\n" "fncall$d"
done

echo "axis 2 — every other declaration form is refused the same way:"
refused sz_param   'fn f(sizeof): i64 { return 1; }\nsyscall(60, f(5));\n' sizeof
refused mh_param2  'fn f(a, b, mulh64: i64): i64 { return a; }\nsyscall(60, f(1, 2, 3));\n' mulh64
refused gen_param  'fn g<T>(sizeof: T): i64 { return 1; }\nfn main(): i64 { return g<i64>(1) + g<i32>(2); }\nsyscall(60, main());\n' sizeof
refused cl_param   'fn main(): i64 { var c = |fncall4| 1; return 1; }\nsyscall(60, main());\n' fncall4
refused sz_local   'fn main(): i64 { var sizeof = 5; return 1; }\nsyscall(60, main());\n' sizeof
refused fc_local   'fn main(): i64 { var fncall2 = 5; return fncall2 + 1; }\nsyscall(60, main());\n' fncall2
refused mh_global  'var mulh64 = 5;\nsyscall(60, 1);\n' mulh64
refused fc_global  'var fncall3 = 5;\nfn g(): i64 { return fncall3 + 1; }\nsyscall(60, g());\n' fncall3
refused tl_late    'var a = 1;\nsyscall(1, 1, "x", 0);\nvar sizeof = 5;\nsyscall(60, 1);\n' sizeof
refused dt_local   'fn two(): (i64, i64) { return (1, 2); }\nfn main(): i64 { var a, fncall0 = two(); return a; }\nsyscall(60, main());\n' fncall0
refused dt_local3  'fn three(): (i64, i64, i64) { return (1, 2, 3); }\nfn main(): i64 { var a, b, mulh64 = three(); return a; }\nsyscall(60, main());\n' mulh64
refused dt_global  'fn two(): (i64, i64) { return (1, 2); }\nvar a, sizeof = two();\nsyscall(60, a);\n' sizeof
refused dt_global3 'fn three(): (i64, i64, i64) { return (1, 2, 3); }\nvar a, b, fncall8 = three();\nsyscall(60, a);\n' fncall8
refused stk_var    'fn main(): i64 { stack var mulh64[16]; return 1; }\nsyscall(60, main());\n' mulh64
refused sec_var    'fn main(): i64 { secret var sizeof[16]; return 1; }\nsyscall(60, main());\n' sizeof
refused for_bind   'fn main(): i64 { var s = 0; for fncall5 in 0..3 { s = s + 1; } return s; }\nsyscall(60, main());\n' fncall5
# `use m.NAME;` binds the bare name: each used to compile and run the filed defect again.
refused use_mh     'mod m;\nfn mulh64(a, b): i64 { return 77; }\nmod n;\nuse m.mulh64;\nfn f(): i64 { return mulh64(4611686018427387904, 8); }\nsyscall(60, n_f());\n' mulh64
refused use_mh_top 'mod m;\nfn mulh64(a, b): i64 { return 77; }\nuse m.mulh64;\nsyscall(60, mulh64(4611686018427387904, 8));\n' mulh64
refused use_fc     'include "lib/fnptr.cyr"\nmod m;\nfn fncall1(a, b): i64 { return 77; }\nmod n;\nuse m.fncall1;\nfn f(): i64 { return fncall1(5, 6); }\nsyscall(60, n_f());\n' fncall1
refused use_sz     'mod m;\nfn sizeof(): i64 { return 77; }\nmod n;\nuse m.sizeof;\nfn f(): i64 { return sizeof(); }\nsyscall(60, n_f());\n' sizeof
# A PAYLOAD enum variant `NAME(..)` registers its constructor as a fn under the BARE variant name
# (there is no qualified constructor: `E.mulh64(4, 8)` is a parse error), so it declares NAME. Each
# used to compile rc 0 and run the filed defect again: the heap `mulh64(a, b)` and the `: stack`
# `mulh64(a)` ran the intrinsic (2), the `: stack` `fncall1(a)` with NO include — the variant's
# registration is what enabled the lowering — and the heap `fncall1(a, b)` SIGSEGV'd. Heap, `: stack`,
# nullary `NAME()` and sizeof are all refused; a UNIT variant declares no fn and stays (axis 4).
EA='var ABUF[64];\nfn alloc(n): i64 { return &ABUF; }\n'
refused en_mh      "$EA"'enum E { A; mulh64(a, b); }\nfn main(): i64 { var e = mulh64(4611686018427387904, 8); return e; }\nsyscall(60, main());\n' mulh64
refused en_stk_mh  'enum E : stack { A; mulh64(a); }\nfn main(): i64 { var t, v = mulh64(4611686018427387904, 8); return v; }\nsyscall(60, main());\n' mulh64
refused en_stk_fc  'enum E : stack { A; fncall1(a); }\nfn main(): i64 { var t, v = fncall1(5, 6); return v; }\nsyscall(60, main());\n' fncall1
refused en_fc      "$EA"'enum E { A; fncall1(a, b); }\nfn main(): i64 { var e = fncall1(5, 6); return 3; }\nsyscall(60, main());\n' fncall1
refused en_sz      "$EA"'enum E { A; sizeof(a); }\nsyscall(60, 1);\n' sizeof
refused en_null    "$EA"'enum E { A; mulh64(); }\nsyscall(60, 1);\n' mulh64

echo "axis 3 — only a file named fnptr.cyr may declare fncall0..8:"
FN2='fn add(a, b): i64 { return a + b; }\nfn main(): i64 { return fncall2(&add, 3, 4); }\nsyscall(60, main());\n'
runs lib_fnptr  "include \"lib/fnptr.cyr\"\\n$FN2" 7
runs sub_fnptr  "include \"sub/fnptr.cyr\"\\n$FN2" 7
runs bare_fnptr "include \"fnptr.cyr\"\\n$FN2" 7
# The same bytes under another name: all nine definitions refused.
refused myptr    'include "sub/myptr.cyr"\nsyscall(60, 1);\n' fncall0 9
refused notfnptr 'include "sub/notfnptr.cyr"\nsyscall(60, 1);\n' fncall8 9
# lib/fnptr.cyr included does not license the program's own definition.
refused user_beside_lib 'include "lib/fnptr.cyr"\nfn fncall1(a, b): i64 { return 77; }\nsyscall(60, 1);\n' fncall1
# lib/fnptr.cyr as the ENTRY (`cat | cycc`, `cyrius build`, the LSP's `cyrius check`): the main source
# has no file name, so its nine definitions are refused. DELIBERATE — it is a library; include it.
cp "$ROOT/lib/fnptr.cyr" "$T/fnptr_entry.cyr"
judged_refused fnptr_entry fncall0 9

# A NUMBER where a declared name belongs is still the plain `expected identifier` error, not a
# fault: the check must read a name only from an IDENT token (the first cut read the number as a
# name-pool offset and SIGSEGV'd, rc 139).
for f in 'fn main(): i64 { var 140737488355327 = 1; return 1; }\nsyscall(60, main());\n' \
         'fn f(140737488355327): i64 { return 1; }\nsyscall(60, 1);\n' \
         'var 140737488355327 = 1;\nsyscall(60, 1);\n'; do
    printf '%b' "$f" > "$T/num.cyr"
    rc=0; (cd "$T" && "$CC" < num.cyr > num.out 2> num.err) || rc=$?
    check "a number as a declared name: exits 1 (not a fault)" 1 "$rc"
    check "a number as a declared name: 'expected identifier'" yes "$(grep -qF 'expected identifier, got number' "$T/num.err" && echo yes || echo no)"
done

echo "axis 4 — ANTI-VACUOUS: the intrinsics, near-miss names and mangled names still work:"
runs fc_stmt    'include "lib/fnptr.cyr"\nvar G = 0;\nfn put(a): i64 { G = a; return 0; }\nfn main(): i64 { fncall1(&put, 9); return G; }\nsyscall(60, main());\n' 9
runs fc_toplvl  'include "lib/fnptr.cyr"\nfn add(a, b): i64 { return a + b; }\nsyscall(60, fncall2(&add, 3, 4));\n' 7
# 2^63 * 16 = 2^67: high word 8; + sizeof(i32) 4
runs intrinsics 'fn main(): i64 { return mulh64(0x8000000000000000, 16) + sizeof(i32); }\nsyscall(60, main());\n' 12
runs near_miss  'fn mulh64x(a, b): i64 { return a + b; }\nfn fncall9(a): i64 { return a; }\nfn sizeofx(a): i64 { return a; }\nvar fncall = 1;\nvar sizeof_t = 2;\nsyscall(60, mulh64x(3, 4) + fncall9(fncall) + sizeofx(sizeof_t));\n' 10
runs impl_meth  'struct Foo { a; }\nimpl Foo { fn sizeof(self): i64 { return 9; } }\nfn main(): i64 { var f = Foo { 1 }; return f.sizeof(); }\nsyscall(60, main());\n' 9
runs mod_fn     'mod m;\nfn sizeof(): i64 { return 6; }\nsyscall(60, m_sizeof());\n' 6
runs use_alias  'mod m;\nfn foo(a, b): i64 { return 77; }\nmod n;\nuse m.foo;\nfn f(): i64 { return foo(1, 2); }\nsyscall(60, n_f());\n' 77
# A UNIT variant spelled `mulh64` declares no fn and is read qualified; an ordinary payload
# variant still constructs (tag 1 + its second payload 8).
runs en_unit    'enum E { A; mulh64 = 77; }\nfn main(): i64 { return E.mulh64; }\nsyscall(60, main());\n' 77
runs en_ctor    "$EA"'enum E { A; Pair(a, b); }\nfn main(): i64 { var e = Pair(4, 8); return load64(e + 16) + load64(e); }\nsyscall(60, main());\n' 9

# AXIS 5 (6.7.16, the user's D11, 2026-10-19: "Refuse it by name") — `mulh64(a, b);` / `sizeof(T);` AS A
# STATEMENT is one error at the name, "the value of 'mulh64(..)' is discarded - a statement is an assignment or a
# call", no binary, with or without --allow-undef. The `IDENT (` statement arm sent it to PARSE_FNCALL: "undefined
# function 'mulh64'" (+ "refusing to emit binary"), `sizeof(H);` "undefined variable 'H'" first, and --allow-undef
# wrote a binary that exited 132 (SIGILL at the unresolved call) (issues/2026-10-18-intrinsic-as-bare-statement-is-
# undefined-function.md). Compiled from the checkout (lib/syscalls.cyr resolves). The value forms still run (16), the
# next statement's own error is still reported, and `fncallN(..);` stays a call (fc_stmt above).
# ⛔ EVERY LEG (6.7.16, issues/archived/2026-10-20-intrinsic-statement-refusal-gated-on-x86-64-only.md): each target is its own
# compiler build, so every row runs on the x86_64 compiler, its PE (CYRIUS_TARGET_WIN=1) and Mach-O (CYRIUS_MACHO=1)
# legs, and the aarch64, cx and PE-cross (src/main_win.cyr) compilers built here from the tree; st_val's value forms
# RUN on x86_64, aarch64 (qemu-aarch64 — emulation, not hardware), cx (the tree's cxvm) and both PE legs (wine, a
# private prefix). Mach-O is built, not run: no Mach-O loader on Linux (the cross-OS leg runs it on ecb / ach). A
# missing qemu-aarch64 or wine is a SKIP line by name; a cross compiler that does not build is RED.
# MUTATION (measured 2026-10-19, a scratch copy, CYCC= its compiler): `_stmt_intrinsic` returning 0 at once (the
# slot-open compiler's behaviour) -> RED all ten st_* rows, 12 assertions (the undefined-function lines; st_mh_undef
# rc 0 with a binary); without its `_refuse_in_sync` -> RED st_next and st_next_sz (the resync skipped the next
# statement: one error); without its stand-down at a `.` after the call -> RED call_ptr_field_store.sh's U14 control
# on its four legs (`mulh64(2, 3).n = 5;` keeps "expected ';', got '.'", that statement is no D11 shape).
# Re-measured on the six legs (2026-10-20, f16, a scratch copy of 450ecf2c9, its 2-stage cycc, this gate run from the
# copy with CYCC= it, so every leg's compiler carries the mutant): `_stmt_intrinsic` returning 0 at once -> RED all ten
# st_* rows on all six legs, 71 assertions (60 row-legs; st_mh_undef 3 each but cx, which has no --allow-undef: 1);
# the unmutated tree GREEN on all six, st_val running 16 on x86 / a64 / cx / pe / win.
SI=" is discarded - a statement is an assignment or a call"
cd "$ROOT" || { echo "FAIL: intrinsic_names_reserved — cannot cd to $ROOT"; exit 1; }
# A PRIVATE wine prefix under $T (never ~/.wine), torn down with its server dir on exit.
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
skips=0
# The aarch64, cx and PE-cross compilers and the cxvm, built from this tree's src (a refusal needs no runner).
LEGS="x86 pe macho"
if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> /dev/null && [ -s "$T/cc_a64" ]; then
    chmod +x "$T/cc_a64"; LEGS="$LEGS a64"
else echo "  FAIL: aarch64 — src/main_aarch64.cyr did not build"; fails=$((fails + 1)); fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2> /dev/null && [ -s "$T/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> /dev/null && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"; LEGS="$LEGS cx"
else echo "  FAIL: cx — src/main_cx.cyr or programs/cxvm.cyr did not build"; fails=$((fails + 1)); fi
if "$CC" < src/main_win.cyr > "$T/cc_win" 2> /dev/null && [ -s "$T/cc_win" ]; then
    chmod +x "$T/cc_win"; LEGS="$LEGS win"
else echo "  FAIL: win — src/main_win.cyr (the PE cross compiler) did not build"; fails=$((fails + 1)); fi
QEMU=0; WINE=0
if command -v qemu-aarch64 > /dev/null 2>&1; then QEMU=1
else echo "  SKIP: the aarch64 run leg (qemu-aarch64 not installed; its refusal rows still run)"; skips=$((skips + 1)); fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: the PE run legs (wine not installed; their refusal rows still run)"; skips=$((skips + 1)); fi
# comp <leg> <src> <out> [cc-arg]: compile from the checkout; the rc in CRC
comp() {
    CRC=0
    case "$1" in
        x86)   timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        pe)    CYRIUS_TARGET_WIN=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        macho) CYRIUS_MACHO=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        a64)   timeout 60 "$T/cc_a64" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        cx)    timeout 60 "$T/cc_cx" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        win)   timeout 60 "$T/cc_win" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
    esac
}
# execute <leg> <binary>: run it where this box has a runner; the exit in XRC, -1 = not run (NOTE says why)
execute() {
    XRC=-1; NOTE=""
    case "$1" in
        x86)   chmod +x "$2"; XRC=0; timeout 60 "$2" > /dev/null 2>&1 || XRC=$? ;;
        a64)   if [ "$QEMU" = 1 ]; then chmod +x "$2"; XRC=0; timeout 120 qemu-aarch64 "$2" > /dev/null 2>&1 || XRC=$?
               else NOTE="qemu-aarch64 not installed"; fi ;;
        cx)    XRC=0; timeout 120 "$T/cxvm" < "$2" > /dev/null 2>&1 || XRC=$? ;;
        pe|win) if [ "$WINE" = 1 ]; then
                   cp "$2" "$2.exe"; XRC=0
                   (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                       WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "$2.exe" > /dev/null 2>&1) || XRC=$?
               else NOTE="wine not installed"; fi ;;
        macho) NOTE="no Mach-O loader on Linux" ;;
    esac
}
A5=0
# stmt <name> <printf-fmt> <want error lines> [cc-arg]: on every leg, from the checkout; rc 1, no binary, the `error`
# / `warning` lines exactly <want error lines>
stmt() {
    printf '%b' "$2" > "$T/$1.cyr"
    for leg in $LEGS; do
        A5=$((A5 + 1))
        comp "$leg" "$T/$1.cyr" "$T/$1.$leg" "${4:-}"
        check "$1 $leg: exits 1" 1 "$CRC"
        check "$1 $leg: error lines" "$3" "$(grep -E '^(error|warning)' "$T/$1.$leg.err" | tr '\n' '|')"
        check "$1 $leg: emits no binary" 0 "$(wc -c < "$T/$1.$leg" | tr -d ' ')"
    done
}
echo "axis 5 — an identifier intrinsic as a whole statement is refused by name (D11), on every leg ($LEGS):"
SH='include "lib/syscalls.cyr"\nstruct H { n; m; }\n'
stmt st_mh       "${SH}"'fn go(): i64 { mulh64(2, 3); return 0; }\nsyscall(60, go());\n' "error:<source>:3:16: the value of 'mulh64(..)'$SI|"
stmt st_mh_undef "${SH}"'fn go(): i64 { mulh64(2, 3); return 0; }\nsyscall(60, go());\n' "error:<source>:3:16: the value of 'mulh64(..)'$SI|" --allow-undef
stmt st_sz       "${SH}"'fn go(): i64 { sizeof(H); return 0; }\nsyscall(60, go());\n' "error:<source>:3:16: the value of 'sizeof(..)'$SI|"
stmt st_sz_undef "${SH}"'fn go(): i64 { sizeof(H); return 0; }\nsyscall(60, go());\n' "error:<source>:3:16: the value of 'sizeof(..)'$SI|" --allow-undef
stmt st_mh_syn   "${SH}"'fn go(): i64 { mulh64(2, 3); return 0; }\nsyscall(60, go());\n' "error:<source>:3:16: the value of 'mulh64(..)'$SI|" --syntax-only
stmt st_top      "${SH}"'mulh64(2, 3);\nsyscall(60, 0);\nsizeof(H);\n' "error:<source>:3:1: the value of 'mulh64(..)'$SI|error:<source>:5:1: the value of 'sizeof(..)'$SI|"
stmt st_gen      "${SH}"'fn g<T>(a: T): i64 { sizeof(H); return 0; }\nsyscall(60, g(1) + g<i32>(2));\n' "error:<source>:3:22: the value of 'sizeof(..)'$SI|"
stmt st_expr     "${SH}"'fn go(): i64 { sizeof(H) + 1; return 0; }\nsyscall(60, go());\n' "error:<source>:3:16: the value of 'sizeof(..)'$SI|"
stmt st_next     "${SH}"'fn go(): i64 {\n    var y = 0;\n    mulh64(2, 3);\n    y = zz9;\n    return y;\n}\nsyscall(60, go());\n' "error:<source>:5:5: the value of 'mulh64(..)'$SI|error:<source>:6:12: undefined variable 'zz9' (missing include or enum?)|"
stmt st_next_sz  "${SH}"'fn go(): i64 {\n    var y = 0;\n    if (y == 0) { sizeof(H); y = zz8; }\n    return y;\n}\nsyscall(60, go());\n' "error:<source>:5:19: the value of 'sizeof(..)'$SI|error:<source>:5:37: undefined variable 'zz8' (missing include or enum?)|"
# A `.` after the intrinsic's `)` is no D11 shape: the statement is parsed as the value position parses it, one
# "expected ';', got '.'" and nothing else (6.7.16, issues/2026-10-19-intrinsic-call-with-field-statement-still-
# undefined-function.md). The call statement's field arm took the intrinsic for a call to a fn that cannot exist:
# "expected ';', got '.'", then "undefined function 'mulh64'" twice (`warning:` lines) and "refusing to emit binary"
# (`sizeof(H)`: "undefined variable 'H'" first); under --syntax-only (what `cyrius lint` runs) ONLY the invented lines,
# never the `.`. st_fld_filed is the filed repro verbatim; two such statements on a line are two errors, each its own
# (the resync stops at the first one's `;`). MUTATION (2026-10-20, f16, the scratch-copy procedure above): `_stmt_intrinsic_dot` dropped (the old
# `return 0` at the `.`) -> RED every st_fld_* / st_sz_fld* row on all six legs.
FE="expected ';', got '.'"
stmt st_fld_filed       'struct H { n; m; }\nfn go(): i64 { mulh64(2, 3).n = 5; return 0; }\nsyscall(60, go());\n' "error:<source>:2:28: $FE|"
stmt st_fld_store       "${SH}"'fn go(): i64 { mulh64(2, 3).n = 5; return 0; }\nsyscall(60, go());\n' "error:<source>:3:28: $FE|"
stmt st_fld_store_undef "${SH}"'fn go(): i64 { mulh64(2, 3).n = 5; return 0; }\nsyscall(60, go());\n' "error:<source>:3:28: $FE|" --allow-undef
stmt st_fld_store_syn   "${SH}"'fn go(): i64 { mulh64(2, 3).n = 5; return 0; }\nsyscall(60, go());\n' "error:<source>:3:28: $FE|" --syntax-only
stmt st_fld_read        "${SH}"'fn go(): i64 { mulh64(2, 3).n; return 0; }\nsyscall(60, go());\n' "error:<source>:3:28: $FE|"
stmt st_fld_read_undef  "${SH}"'fn go(): i64 { mulh64(2, 3).n; return 0; }\nsyscall(60, go());\n' "error:<source>:3:28: $FE|" --allow-undef
stmt st_fld_meth        "${SH}"'fn go(): i64 { mulh64(2, 3).n += 1; mulh64(4, 5).f(); return 0; }\nsyscall(60, go());\n' "error:<source>:3:28: $FE|error:<source>:3:49: $FE|"
stmt st_sz_fld          "${SH}"'fn go(): i64 { sizeof(H).n = 5; return 0; }\nsyscall(60, go());\n' "error:<source>:3:25: $FE|"
stmt st_sz_fld_undef    "${SH}"'fn go(): i64 { sizeof(H).n = 5; return 0; }\nsyscall(60, go());\n' "error:<source>:3:25: $FE|" --allow-undef
stmt st_sz_fld_syn      "${SH}"'fn go(): i64 { sizeof(H).n = 5; return 0; }\nsyscall(60, go());\n' "error:<source>:3:25: $FE|" --syntax-only
stmt st_sz_fld_read     "${SH}"'fn go(): i64 { sizeof(H).n; sizeof(H).n.m; return 0; }\nsyscall(60, go());\n' "error:<source>:3:25: $FE|error:<source>:3:38: $FE|"
stmt st_fld_top         "${SH}"'mulh64(2, 3).n = 5;\nsizeof(H).n;\nsyscall(60, 0);\n' "error:<source>:3:13: $FE|error:<source>:4:10: $FE|"
stmt st_fld_gen         "${SH}"'fn g<T>(a: T): i64 { mulh64(2, 3).n = 5; return 0; }\nsyscall(60, g(1) + g<i32>(2));\n' "error:<source>:3:34: $FE|"
stmt st_fld_next        "${SH}"'fn go(): i64 {\n    var y = 0;\n    mulh64(2, 3).n = 5;\n    y = zz9;\n    return y;\n}\nsyscall(60, go());\n' "error:<source>:5:17: $FE|error:<source>:6:12: undefined variable 'zz9' (missing include or enum?)|"
# st_val: the value forms compile on every leg and run 16 (2 * 3 >> 64 = 0, + sizeof(H) 16) wherever a runner is
printf '%b' "${SH}"'fn go(): i64 { var x = mulh64(2, 3); var n = sizeof(H); return x + n; }\nsyscall(60, go());\n' > "$T/st_val.cyr"
for leg in $LEGS; do
    A5=$((A5 + 1))
    comp "$leg" "$T/st_val.cyr" "$T/st_val.$leg"
    check "st_val $leg: the value forms compile" 0 "$CRC"
    check "st_val $leg: a binary is written" yes "$([ -s "$T/st_val.$leg" ] && echo yes || echo no)"
    [ "$CRC" = 0 ] && [ -s "$T/st_val.$leg" ] || continue
    execute "$leg" "$T/st_val.$leg"
    if [ "$XRC" = -1 ]; then echo "  not run: st_val $leg — $NOTE"
    else check "st_val $leg: mulh64(2, 3) + sizeof(H) exits 16" 16 "$XRC"; fi
done
# The corpus floor: 25 rows (10 D11 refusals, 14 st_fld / st_sz_fld rows, st_val) on all six legs. A leg that did not
# build is RED above; this catches rows lost from the list.
A5_FLOOR=150
[ "$A5" -ge "$A5_FLOOR" ] || { echo "  FAIL: axis 5 ran $A5 row-legs (floor $A5_FLOOR) — rows or legs were lost"; fails=$((fails + 1)); }
echo "  axis 5: $A5 row-legs on $LEGS; $skips skipped"

echo ""
# AXIS 6 (6.7.16, f16 FF6) — A TYPE-ARGUMENT LIST ON A CALLEE THAT TAKES NONE IS ONE ERROR AT ITS NAME, in statement and
# value position (issues/archived/2026-10-19-type-arguments-on-non-generic-fn-call-cascade.md). The filed fn shapes (ng1, ng2)
# and the method's (ng5) are genbind's `_eta_gen` / `_meth_ngt` since 9ac212def; the intrinsics and the builtins were
# not: `mulh64<i64>(2, 3);` said "undefined function 'mulh64'", `var x = mulh64<i64>(2, 3);` "expected '(', got '<'" +
# "undefined variable 'i64'", `load64<i64>(&a)` / `syscall<i64>(60, a)` / `callptr<i64>(&cb)` / `f64_sqrt<f64>(2.0)` the
# same, a statement's `store64<i64>(&a, 2);` and an `mulh64<T>(..)` in a generic body went on to "expected '}', got end
# of file" (the next fn read as nested). ERR_EXPECT, asked for a callee's `(`, now asks `_ngt_callee_lt`: a builtin's or an
# intrinsic's list of type names before its `(` is refused with a fn's words — "'mulh64' is not a generic fn: it takes no
# type arguments" — and stepped, the call parsed in sync (its arguments' own errors, the next statement's, reported);
# the statement intrinsic is that one error (`_stmt_intr_targs`; D11's words stand down for it). ng1-ng4 the four filed
# shapes verbatim, ng5 the method forms, ng6 sizeof and the builtins, ng7 a generic body's two instances once, the
# arguments checked, top level, two type arguments, ng8 --syntax-only (lint: the list silent, as D6's are; D11's statement
# line kept), ng9 controls run: a generic `id<i32>(4)`, comparisons `f(a < b, c > (d))` and `sizeof(H) < a`.
# MUTATION LEDGER (2026-10-21, f16 FF6; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run
# from the copy so every leg's compiler carries the mutant):
#   the lane before it (68a340f16)                     -> RED ng3 ng4 ng6 ng7 ng8 ng8b on all six legs, 54 assertions
#   ERR_EXPECT without its `_ngt_callee_lt` hook      -> RED ng3 ng4 ng6 ng7 ng8b, 36 ("expected '(', got '<'")
#   `_stmt_undef_gcall` without its intrinsic arm     -> RED ng3 ng6 ng7 ng8, 35 ("undefined function 'mulh64'")
#   `_stmt_intr_at` saying D11's words anyway          -> RED ng3 ng6 ng7, 18 (two errors for the statement)
#   `_ngt_say_s` latching after its report             -> RED ng6 ng7, 12 (the next statement's / argument's error lost)
echo "axis 6 — a type-argument list on a callee that takes none is one error at its name, on every leg ($LEGS):"
A6=0
NG=" is not a generic fn: it takes no type arguments"
ZE="undefined variable 'zz' (missing include or enum?)"
ng() { A5=0; stmt "$@"; A6=$((A6 + A5)); }
ng ng1 'fn f(a, b): i64 { return a + b; }\nfn go(): i64 { f<i64>(2, 3); return 0; }\nsyscall(60, go());\n' "error:<source>:2:16: 'f'$NG|"
ng ng2 'fn f(a, b): i64 { return a + b; }\nfn go(): i64 { var x = f<i64>(2, 3); return x; }\nsyscall(60, go());\n' "error:<source>:2:24: 'f'$NG|"
ng ng3 'fn go(): i64 { mulh64<i64>(2, 3); return 0; }\nsyscall(60, go());\n' "error:<source>:1:16: 'mulh64'$NG|"
ng ng4 'fn go(): i64 { var x = mulh64<i64>(2, 3); return x; }\nsyscall(60, go());\n' "error:<source>:1:24: 'mulh64'$NG|"
ng ng5 "${SH}"'impl H { fn m2(self, k): i64 { return k; } }\nfn go(): i64 { var h = H { 1, 2 }; h.m2<i64>(2); var y = h.m2<i64>(3); return y + zz; }\nsyscall(60, go());\n' "error:<source>:4:38: 'H.m2' is not a generic method: it takes no type arguments|error:<source>:4:60: 'H.m2' is not a generic method: it takes no type arguments|error:<source>:4:85: $ZE|"
ng ng6 "${SH}"'fn cb(): i64 { return 1; }\nfn go(): i64 {\n    var a: i64 = 1;\n    var s = sizeof<i64>(H);\n    var l = load64<i64>(&a);\n    store64<i64>(&a, 2);\n    syscall<i64>(60, a);\n    var c = callptr<i64>(&cb);\n    var q = f64_sqrt<f64>(2.0);\n    sizeof<H>(H);\n    return s + l + c + q + zz;\n}\nsyscall(60, go());\n' "error:<source>:6:13: 'sizeof'$NG|error:<source>:7:13: 'load64'$NG|error:<source>:8:5: 'store64'$NG|error:<source>:9:5: 'syscall'$NG|error:<source>:10:13: 'callptr'$NG|error:<source>:11:13: 'f64_sqrt'$NG|error:<source>:12:5: 'sizeof'$NG|error:<source>:13:30: $ZE|"
ng ng7 'include "lib/syscalls.cyr"\nfn g<T>(x: T): i64 { mulh64<i64>(2, 3); return mulh64<T>(x, 3); }\nfn go(): i64 { mulh64<i64>(zq, 3); return g<i64>(1) + g<i32>(2); }\nvar a = 1;\na = 2;\nmulh64<i64>(2, 3);\nvar b = mulh64<i64, u8>(a, 3);\na = zz;\nsyscall(60, go());\n' "error:<source>:2:22: 'mulh64'$NG|error:<source>:2:48: 'mulh64'$NG|error:<source>:3:16: 'mulh64'$NG|error:<source>:3:30: undefined variable 'zq' (missing include or enum?)|error:<source>:6:1: 'mulh64'$NG|error:<source>:7:9: 'mulh64'$NG|error:<source>:8:7: $ZE|"
ng ng8 'fn go(): i64 { mulh64<i64>(2, 3); return 0; }\nsyscall(60, go());\n' "error:<source>:1:16: the value of 'mulh64(..)'$SI|" --syntax-only
# ng8b: --syntax-only says nothing for the value forms (rc 0, no error line) on every leg
printf '%b' "${SH}"'fn f(a): i64 { return a; }\nfn go(): i64 { var a = 1; var x = mulh64<i64>(2, 3) + load64<i64>(&a) + f<i64>(1) + sizeof<i64>(H); return x; }\nsyscall(60, go());\n' > "$T/ng8b.cyr"
for leg in $LEGS; do
    A6=$((A6 + 1))
    comp "$leg" "$T/ng8b.cyr" "$T/ng8b.$leg" --syntax-only
    check "ng8b $leg: --syntax-only on the value forms exits 0" 0 "$CRC"
    check "ng8b $leg: --syntax-only says nothing" "" "$(grep -E '^(error|warning)' "$T/ng8b.$leg.err" | tr '\n' '|')"
done
# ng9: controls compile on every leg and run 42 wherever a runner is: a generic's explicit list, comparisons beside a call
printf '%b' "${SH}"'fn id<T>(x: T): i64 { return x; }\nfn f3(a, b): i64 { return a * 10 + b; }\nfn go(): i64 { var a = 1; var b = 2; var c = 3; var d = 4; var s = sizeof(H) < a; return id<i32>(4) + f3(a < b, c > (d)) + s + 28; }\nsyscall(60, go());\n' > "$T/ng9.cyr"
for leg in $LEGS; do
    A6=$((A6 + 1))
    comp "$leg" "$T/ng9.cyr" "$T/ng9.$leg"
    check "ng9 $leg: the controls compile" 0 "$CRC"
    [ "$CRC" = 0 ] && [ -s "$T/ng9.$leg" ] || continue
    execute "$leg" "$T/ng9.$leg"
    if [ "$XRC" = -1 ]; then echo "  not run: ng9 $leg — $NOTE"
    else check "ng9 $leg: id<i32>(4) + f3(a < b, c > (d)) + (sizeof(H) < a) + 28 exits 42" 42 "$XRC"; fi
done
A6_FLOOR=60
[ "$A6" -ge "$A6_FLOOR" ] || { echo "  FAIL: axis 6 ran $A6 row-legs (floor $A6_FLOOR) — rows or legs were lost"; fails=$((fails + 1)); }
echo "  axis 6: $A6 row-legs on $LEGS"

echo ""
if [ "$fails" = 0 ]; then
    echo "PASS: intrinsic_names_reserved — sizeof / mulh64 / fncall0..8 are refused as declared names"
    exit 0
fi
echo "FAIL: intrinsic_names_reserved — $fails assertion(s) failed"
exit 1
