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
#   a `for` binding.
# AXIS 3 — THE ONE LEGITIMATE DECLARER: lib/fnptr.cyr's fncall0..8 ARE the lowering's enabler
#   (it is gated on FINDFN) and cybs calls them in gen1, so an included file whose BASENAME is
#   `fnptr.cyr` may declare them — from lib/, from another directory, or bare. The exemption is
#   the file, not the content: the same bytes as `myptr.cyr` or `notfnptr.cyr` are refused, and a
#   user `fn fncall1` beside an included lib/fnptr.cyr is still refused.
# AXIS 4 — ANTI-VACUOUS: the intrinsics still work (fncallN in an expression, as a statement
#   and at top level; mulh64; sizeof), near-misses (`mulh64x`, `fncall9`, `sizeofx`, `fncall`)
#   are ordinary names, and a mangled name — an impl method `sizeof`, a `mod` fn — is accepted,
#   because nothing can call it as `sizeof(`. And a NUMBER where a name belongs is still the plain
#   `expected identifier` error, never a fault.
#
# MUTATION PROOF (6.6.20):
#   * parse.cyr _RSV_INTRINSIC_DECL: `return 0;` first   -> axes 1 + 2 RED (mh_fn exits 0 and runs 2,
#     fc_fn compiles and SIGSEGVs).
#   * parse.cyr _rsv_in_fnptr: `return 0;` first          -> axis 3/4 RED (lib/fnptr.cyr refused).
#   * parse.cyr _rsv_in_fnptr: `return 1;` first          -> axis 3 RED (myptr / notfnptr compile).
#   * parse_fn.cyr: the fn-name call AFTER `_mod_name_intern` moved BEFORE it -> axis 4 RED (impl
#     method `sizeof` refused).
#   * parse.cyr _RSV_INTRINSIC_DECL: the `TOKTYP(S, ti) != 2` guard dropped -> the three
#     number-as-a-name rows RED (rc 139: the number was read as a name-pool offset).
#
# Exit 77 = could not run (no compiler); never 0 for that.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: intrinsic_names_reserved — $CC not built"; exit 77; }
[ -f "$ROOT/lib/fnptr.cyr" ] || { echo "SKIP: intrinsic_names_reserved — lib/fnptr.cyr missing"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "SKIP: intrinsic_names_reserved: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 77; }
trap 'rm -rf "$T"' EXIT
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
    rc=0
    (cd "$T" && "$CC" < "$1.cyr" > "$1.out" 2> "$1.err") || rc=$?
    check "$1: exits 1" 1 "$rc"
    check "$1: names '$3'" yes "$(grep -qF -- "reserved intrinsic name '$3'" "$T/$1.err" && echo yes || echo no)"
    check "$1: diagnostics" "${4:-1}" "$(grep -c 'reserved intrinsic name' "$T/$1.err")"
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
runs impl_meth  'struct Foo { a; }\nimpl Sz for Foo { fn sizeof(self): i64 { return 9; } }\nfn main(): i64 { var f = Foo { 1 }; return f.sizeof(); }\nsyscall(60, main());\n' 9
runs mod_fn     'mod m;\nfn sizeof(): i64 { return 6; }\nsyscall(60, m_sizeof());\n' 6

echo ""
if [ "$fails" = 0 ]; then
    echo "PASS: intrinsic_names_reserved — sizeof / mulh64 / fncall0..8 are refused as declared names"
    exit 0
fi
echo "FAIL: intrinsic_names_reserved — $fails assertion(s) failed"
exit 1
