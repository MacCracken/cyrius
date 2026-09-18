#!/bin/sh
# tests/gates/frontend/public_marker_scoped_to_its_item.sh — v6.6.4
#
# `public` marks ONE item. The marker `_TL_VIS` arms is consumed by the fn and global-var
# paths only; a struct / union / enum / impl (never private by design) consumed nothing, so
# `public enum E {..}` in a `private` file re-exposed the NEXT fn or var instead — silently,
# and only the first one. hisab's public-surface gate found `_ad_pow` reachable while its
# 456 private siblings were refused (issue 2026-09-13-hisab-public-enum-leaks-onto-next-
# declaration). Bare `public struct`, `public union` and the FORWARD-call shape after
# `public impl` (pass 1 skips the impl body) leaked the same way; the filing's matrix only
# saw struct through #derive, whose generated `public fn` accessors happened to consume it.
# The reverse defect rode along: `public var A, B = f();` exposed A only.
#
# The adversarial review widened it further: `public use a.b;` leaked the same way (never
# consumed); the pass-2 driver's inline `var` skip re-armed at `public var` and nothing
# consumed it before the next PASS-2-ONLY definition — an impl's FIRST method, or the
# first relaxed-ordering fn after top-level code; and closing the leak exposed that the
# derive CODECS (Serialize / Deserialize / enum) were emitted without the struct's `public`
# (only the v6.6.3 accessors honoured it), so a public type's `_to_json` would have become
# unreachable — plus the shared `_cy_enum_name_eq` helper, emitted once per translation
# unit and private to whichever file derived first.
#
# Fix shape: `_TL_VIS` arms the marker only for tokens that can carry it (`_PUB_CAN_ARM`,
# a POSITIVE list), PARSE_IMPL and the relaxed-ordering path clear a stale marker on
# entry, the destructure/array/PARSE_PROG var paths stamp + consume themselves, and the
# codec emitters carry the `vis` prefix the accessor emitter already had. Semantics
# change recorded here: `public impl` now marks NO method (its first method used to be
# public by the leak); per-method `public fn` inside an impl is the form.
#
# Every row compiles a `private` lib + a consumer that reaches ONE name across the file
# boundary, and asserts refused / accepted by the exact error line. `rowraw` takes the
# whole lib text (for shapes the `row` template cannot express — top-level code before
# a fn, a second derive file).
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { printf "  SKIP: public_marker_scoped_to_its_item — %s not built\n" "$CC"; exit 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
n=0

# row <name> <expect: refused|accepted> <callee-expr> <fwd:0|1> <preceding item...>
row() {
    name=$1; expect=$2; callee=$3; fwd=$4; shift 4; item=$*
    d="$T/$name"; mkdir -p "$d/lib"
    printf 'private\n\n%s\nfn _after() { return 3; }\nfn _second() { return 4; }\npublic fn api() { return 1; }\n' "$item" > "$d/lib/p.cyr"
    if [ "$fwd" = 1 ]; then
        printf 'fn main() { return %s; }\ninclude "lib/p.cyr"\n' "$callee" > "$d/m.cyr"
    else
        printf 'include "lib/p.cyr"\nfn main() { return %s; }\n' "$callee" > "$d/m.cyr"
    fi
    rc=0; ( cd "$d" && "$CC" < m.cyr > out 2> err ) || rc=$?
    got=accepted
    grep -q "is private to its file" "$d/err" && got=refused
    [ "$rc" != 0 ] && [ "$got" = accepted ] && got="compile-error($(grep -m1 '^error' "$d/err" || head -1 "$d/err"))"
    n=$((n + 1))
    [ "$got" = "$expect" ] || { echo "  FAIL: public_marker_scoped_to_its_item — $name: expected $expect, got $got"; fail=1; }
}

# ── the leak: the item AFTER a public type declaration must stay private ─────────────
row enum_oneline   refused '_after()' 0 'public enum E1 { A1 = 1 }'
row enum_multiline refused '_after()' 0 'public enum E2 {
    A2 = 1;
    B2 = 2;
}'
row enum_ctor      refused '_after()' 0 'public enum E4 { None(); Some(v); }'
row enum_stack     refused '_after()' 0 'public enum E5: stack { N5(); S5(v); }'
row struct_bare    refused '_after()' 0 'public struct S1 { x; y; }'
row struct_typed   refused '_after()' 0 'public struct S3 { x: i64; y: i64; }'
row union_bare     refused '_after()' 0 'public union U1 { a; b; }'
row impl_fwd       refused '_after()' 1 'struct T1 { n; }
public impl Tr for T1 { fn get(self) { return load64(self); } }'
row enum_then_var  refused '_v' 0 'public enum E6 { A6 = 1 }
var _v = 5;'
# ── the paths that already consumed it must keep doing so ────────────────────────────
row var_then_fn    refused '_after()' 0 'public var V1 = 7;'
row fn_then_fn     refused '_after()' 0 'public fn f1() { return 9; }'
# 6.6.5 — the same two rows in FORWARD order (the caller precedes the include), plus a
# positive control. This is ORDER-COVERAGE ONLY, and saying so is the point: the whole
# matrix above was written backward-only, so a fix that got the forward order wrong would
# not have shown here.
# ⚠ NOT mutation-proven, MEASURED: these three rows stay GREEN on the pre-fix compiler AND
# under the 6.6.5 mutant that deletes the `_fn_by_defti` pass-1 authority (M6 in
# tests/gates/frontend/private_forward_reference.sh). What the authority is proven by is
# the pre-existing BACKWARD var_then_fn / arr_then_fn rows, which M6 turns red — pass 2's
# inline `var` skip re-arms `public` and never consumes it, so pass 2 computes the wrong
# visibility for the next fn, and clearing the pass-1 private bit (6.6.5) is what stopped
# masking it. An earlier draft of this comment claimed these three rows were what M6
# reddened; they are not, and a gate comment that overstates its own reach is the same
# defect class as a gate that reads green over one.
row var_then_fn_fwd refused '_after()' 1 'public var V1 = 7;'
row arr_then_fn_fwd refused '_after()' 1 'public var PARR[4];'
row var_then_pub_fwd accepted 'api()'  1 'public var V1 = 7;'
row iofn_then_fn   refused '_after()' 0 'public #io fn f2() { return 9; }'
row derive_struct  refused '_after()' 0 '#derive(accessors)
public struct S4 { x; y; }'
# ── positive controls: `public` must still re-expose its OWN item, and enum constants
#    are public by design (the guide: visibility covers fns and global vars) ─────────
row api_reachable  accepted 'api()' 0 'public enum E7 { A7 = 1 }'
row enum_const     accepted 'A8' 0 'public enum E8 { A8 = 1 }'
row pub_fn_fwd     accepted 'f9()' 1 'public enum E9 { A9 = 1 }
public fn f9() { return 9; }'
# ── one `public` covers EVERY name of a destructuring declaration ────────────────────
row destr_first    accepted 'PA' 0 'fn _pair(): (i64, i64) { return (5, 6); }
public var PA, PB = _pair();'
row destr_second   accepted 'PB' 0 'fn _pair(): (i64, i64) { return (5, 6); }
public var PA, PB = _pair();'
row destr_third    accepted 'PC' 0 'fn _tri(): (i64, i64, i64) { return (5, 6, 7); }
public var PA, PB, PC = _tri();'
row destr_nonpub   refused 'PB' 0 'fn _pair(): (i64, i64) { return (5, 6); }
var PA, PB = _pair();'


# rowraw <name> <expect> <callee-expr> <fwd> <extra-consumer-prelude> <full lib text>
rowraw() {
    name=$1; expect=$2; callee=$3; fwd=$4; pre=$5; libtxt=$6
    d="$T/$name"; mkdir -p "$d/lib"; ln -s "$ROOT/lib"/* "$d/lib/" 2>/dev/null || true
    printf '%s\n' "$libtxt" > "$d/lib/p.cyr"
    if [ "$fwd" = 1 ]; then
        printf '%sfn main() { return %s; }\ninclude "lib/p.cyr"\n' "$pre" "$callee" > "$d/m.cyr"
    else
        printf '%sinclude "lib/p.cyr"\nfn main() { return %s; }\n' "$pre" "$callee" > "$d/m.cyr"
    fi
    rc=0; ( cd "$d" && "$CC" < m.cyr > out 2> err ) || rc=$?
    got=accepted
    grep -q "is private to its file" "$d/err" && got=refused
    [ "$rc" != 0 ] && [ "$got" = accepted ] && got="compile-error($(grep -m1 '^error' "$d/err"))"
    n=$((n + 1))
    [ "$got" = "$expect" ] || { echo "  FAIL: public_marker_scoped_to_its_item — $name: expected $expect, got $got"; fail=1; }
}
# ── `use` and a top-level ARRAY never consumed the marker either ──────────────────────
row use_then_fn    refused '_after()' 0 'fn _lib_x() { return 1; }
public use lib.x;'
row arr_then_fn    refused '_after()' 0 'public var PARR[4];'
# ── pass-2-only definitions after a `public var`: an impl's first method, and the first
#    relaxed-ordering fn after top-level code (the pass-2 `var` skip re-armed the marker) ──
row var_then_impl  refused 'T4_m(0)' 0 'struct T4 { n; }
public var V4 = 7;
impl Tr for T4 { fn m(self) { return 42; } }'
rowraw var_stmt_fn refused '_late()' 0 '' 'private

public var V6 = 7;
_touch();
fn _late() { return 5; }
fn _late2() { return 6; }
fn _touch() { return 0; }'
# ── globals declared AFTER the first top-level statement take the PARSE_PROG path
#    (PARSE_VAR / PARSE_ARRAY / PARSE_STRUCT_INIT), which never stamped them at all ────
rowraw stmt_then_var refused '_late_v' 0 '' 'private

fn _early() { return 0; }
_early();
var _late_v = 5;'
rowraw stmt_then_destr refused '_QA' 0 '' 'private

fn _pair(): (i64, i64) { return (5, 6); }
_pair();
var _QA, _QB = _pair();'
rowraw stmt_then_arr refused 'load64(&_late_arr)' 0 '' 'private

fn _early() { return 0; }
_early();
var _late_arr[4];'
rowraw stmt_then_struct refused '_late_s.a' 0 'struct LS { a; b; }
' 'private

fn _early() { return 0; }
_early();
var _late_s = LS { 1, 2 };'
rowraw stmt_then_var_ctrl accepted 'late_pub' 0 '' 'fn early() { return 0; }
early();
var late_pub = 5;'
# ── the POSITIVE list must keep arming for every token it names — a missing entry
#    fails CLOSED (the item becomes private) and no negative row would notice ─────────
row pub_fn_arms    accepted 'f1()'  0 'public fn f1() { return 9; }'
row pub_var_arms   accepted 'V1'    0 'public var V1 = 7;'
row pub_io_arms    accepted 'f2()'  0 'public #io fn f2() { return 9; }'
row pub_pure_arms  accepted 'f3()'  0 'public #pure fn f3() { return 9; }'
row pub_alloc_arms accepted 'f4()'  0 'public #alloc fn f4() { return 9; }'
row pub_mustuse_arms accepted 'f5()' 0 'public #must_use fn f5() { return 9; }'
row pub_inline_arms accepted 'f6()' 0 'public #inline fn f6() { return 9; }'
row pub_naked_arms accepted 'f7()' 0 'public #naked fn f7() { asm { 0xC3; } }'
row pub_regalloc_arms accepted 'f8()' 0 'public #regalloc fn f8() { return 9; }'
row pub_deprecated_arms accepted 'f9()' 0 'public #deprecated("old") fn f9() { return 9; }'
# ── a marker armed BEFORE the first top-level statement is STALE at PARSE_PROG entry:
#    pass 2's `var` skip re-arms at `public var`, and the first PARSE_PROG-path
#    declaration used to consume it (found by the bite-3 review) ─────────────────────
rowraw stale_into_var refused 'L1' 0 '' 'private

public var V2 = 55;
_touch();
var L1 = 16;
fn _touch() { return 0; }'
rowraw stale_into_arr refused 'load64(&L2)' 0 '' 'private

public var PA2[4];
_touch();
var L2[4];
fn _touch() { return 0; }'
rowraw stale_into_sinit refused 'L3.a' 0 'struct LS3 { a; b; }
' 'private

public var V3 = 55;
_touch();
var L3 = LS3 { 1, 2 };
fn _touch() { return 0; }'
rowraw stale_var_ctrl accepted 'V2' 0 '' 'private

public var V2 = 55;
_touch();
var L1 = 16;
fn _touch() { return 0; }'
# ── PARSE_PROG-path destructure: EVERY bound name is stamped ─────────────────────────
rowraw stmt_then_destr2 refused '_QB' 0 '' 'private

fn _pair(): (i64, i64) { return (5, 6); }
_pair();
var _QA, _QB = _pair();'
rowraw stmt_then_destr3 refused '_QC' 0 '' 'private

fn _tri(): (i64, i64, i64) { return (5, 6, 7); }
_tri();
var _QA, _QB, _QC = _tri();'
# ── `public impl` marks NO method (it used to expose the first one by the leak);
#    per-method `public fn` is the form and must keep working ──────────────────────────
row pubimpl_first  refused 'T5_m(0)' 0 'struct T5 { n; }
public impl Tr for T5 { fn m(self) { return 42; } fn m2(self) { return 43; } }'
row impl_pub_method accepted 'T6_get(0)' 0 'struct T6 { n; }
impl Tr for T6 { public fn get(self) { return 42; } fn hid(self) { return 43; } }'
row impl_hid_method refused 'T6_hid(0)' 0 'struct T6 { n; }
impl Tr for T6 { public fn get(self) { return 42; } fn hid(self) { return 43; } }'
# ── derive codecs inherit the type's `public`, like the accessors already did ────────
LIBPRE='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/result.cyr"
'
rowraw ser_pub_to    accepted 'Ser_to_json(0, 0)' 0 "$LIBPRE" 'private

#derive(Serialize)
public struct Ser { x: i64; y: i64; }
public fn api() { return 1; }'
rowraw ser_pub_from  accepted 'Ser_from_json_str("{}")' 0 "$LIBPRE" 'private

#derive(Serialize)
public struct Ser { x: i64; y: i64; }
public fn api() { return 1; }'
rowraw ser_priv_to   refused 'Ser_to_json(0, 0)' 0 "$LIBPRE" 'private

#derive(Serialize)
struct Ser { x: i64; y: i64; }
public fn api() { return 1; }'
rowraw enum_pub_to   accepted 'Col_to_json(1, 0)' 0 "$LIBPRE" 'private

#derive(Serialize)
public enum Col { Red = 1; Green = 2; }
public fn api() { return 1; }'
rowraw enum_pub_from accepted 'Col_from_json_str("\"Red\"")' 0 "$LIBPRE" 'private

#derive(Serialize)
public enum Col { Red = 1; Green = 2; }
public fn api() { return 1; }'
rowraw ser_pub_fromp accepted 'Ser_from_json(0)' 0 "$LIBPRE"'include "lib/bayan.cyr"
' 'private

#derive(Serialize)
public struct Ser { x: i64; y: i64; }
public fn api() { return 1; }'
rowraw enum_priv_to  refused 'Col_to_json(1, 0)' 0 "$LIBPRE" 'private

#derive(Serialize)
enum Col { Red = 1; Green = 2; }
public fn api() { return 1; }'
# the shared `_cy_enum_name_eq` helper is emitted ONCE per translation unit, with the
# FIRST enum derive — when that file is `private`, a SECOND private file's enum codec
# called a helper private to the first (measured on 6.6.3: two diagnostics, no binary).
# The helper is now emitted `public` unconditionally.
d="$T/enum_helper_shared"; mkdir -p "$d/lib"; ln -s "$ROOT/lib"/* "$d/lib/" 2>/dev/null || true
printf 'private\n\n#derive(Serialize)\nenum One { X = 1; Y = 2; }\npublic fn api() { return 1; }\n' > "$d/lib/p.cyr"
printf 'private\n\n#derive(Serialize)\nenum Two { A = 1; B = 2; }\npublic fn q_api(): (i64, i64) { return Two_from_json_str("\\"A\\""); }\n' > "$d/lib/q.cyr"
printf '%sinclude "lib/p.cyr"\ninclude "lib/q.cyr"\nfn main() { var t, v = q_api(); return v; }\n' "$LIBPRE" > "$d/m.cyr"
rc=0; ( cd "$d" && "$CC" < m.cyr > out 2> err ) || rc=$?
n=$((n + 1))
if [ "$rc" != 0 ] || grep -q "is private to its file" "$d/err"; then
    echo "  FAIL: public_marker_scoped_to_its_item — enum_helper_shared: a second private file's enum codec was refused (rc=$rc): $(grep -m1 'private\|error' "$d/err")"; fail=1
fi

[ "$fail" = 0 ] && echo "  PASS: public_marker_scoped_to_its_item — $n rows: public struct/union/enum/impl/use consume the marker, fn/var/array still do, pass-2-only definitions are sealed, destructure covers every name, derive codecs inherit public"
exit $fail
