#!/bin/sh
# tests/gates/frontend/type_args_on_nongeneric_refused.sh — 6.7.16
#
# A TYPE-ARGUMENT LIST ON A CALLEE THAT TAKES NONE IS REFUSED ONCE, AT ITS NAME. With `fn nf(a)` and `impl Pt { fn
# m(self, k) }` (neither generic), `nf<i64>(6)` and `p.m<i64>(1)` read the `<` as less-than: "undefined variable 'nf'"
# + "undefined variable 'i64'" + "expected ';', got '>'", or "unknown field 'm' on struct 'Pt'" + "undefined variable
# 'i64'" — two or three errors, none naming the list; a bounded T's non-generic member (`v.show<i64>()` under `T:
# Show`) was "no struct type in scope for 'v'" at a scalar T and "expected ';', got '.'" on a carrier's field. The
# list is now refused with D6 / D7's words for `Pt<i64>` — "'nf' is not a generic fn: it takes no type arguments",
# "'Pt.m' is not a generic method: it takes no type arguments" (`_eta_gen`, `_meth_ngt`) — stepped, and the call parsed
# as `nf(6)` / `p.m(1)`, so nothing cascades; a `.m<types>(` with no method m, or on a receiver of no known struct, is
# stepped too and reports what `p.m(1)` reports. Only a list whose every name is a type (`_tylist_at`): a comparison
# `p.y < a, b > (1)` keeps its reading. `--syntax-only` (cyrius lint) is silent, as D6's refusals are. Found by 6.7.16's
# genbind lane (unit GB2) beside the user's D4 (a bound's member called with an explicit list).
#
#   R   a fn: returned, a statement, a `var` initializer, an argument, two arguments, a nested instance in the list,
#       a method called by its fn name (`Pt_m<i64>(&p, 1)`)
#   M   a method: returned, a statement, an inline struct field `w.v.m<i64>(1)`, a `*Pt` field, a `*Pt` receiver
#   B   a bounded T's non-generic member at a scalar T (once for two instances) and on a carrier's field
#   U   no method m (`p.zz<i64>(1)`: as `p.zz(1)`, the undefined-fn refusal), an untyped receiver (as `q.m(1)`)
#   X   --syntax-only silent (rc 0)
#   K   controls, unchanged: comparisons `p.y < a, b > (1)` / `w.n < a, b > (1)`, a generic fn and method with their
#       lists — build and exit 26
#   A   R1 and M1 refused with the same line by the aarch64, cx and PE compilers
#
# MUTATION (2026-10-20, a one-edit scratch copy of src/ each, CYCC= its cycc): the lane's previous compiler (b6ccc7a50)
# -> RED 19: R1-R7, M1-M5, B1, B2, U1, U2, X1 and A [pe] x2 (the cascades; X2 / X3 were silent since b6ccc7a50, and
# A [a64] / [cx] build their cross compilers from the tree's src); `_eta_gen` without its refusal -> RED 9: R1-R7, X1,
# A [pe] R1; `_meth_ngt` answering 0 -> RED 10: M1-M5, B1, B2, U1, U2, A [pe] M1; `_mtargs_ng` as `_mtargs_at` (the
# field walks not stopping at the list) -> RED 2: M3, B2.
#
#   TP  (6.7.17, the user's D6, 2026-10-22: "Refuse it once, in every position") A TYPE PARAMETER WRITTEN WITH TYPE
#       ARGUMENTS IN AN ANNOTATION: `fn g<U>(u: U<Nope>)`, `var l: U<i8> = 0;`, `u: *U<i8>`, `sizeof(U<i8>)` and a
#       `: *U<i64>` return compiled with the list stepped unread (the filed repro exited 3); a `: U<i64>` return was
#       "expected '{', got '<'" + "undefined variable 'i64'", a field `a: T<i64>` "expected identifier, got '<'", a
#       slice element `[U<i8>]` "expected ']', got '<'". Each position now refuses it once at the name with 6.7.14's
#       words for `h<T<u8>>` — "a type parameter takes no type arguments: 'U'" (`_tp_targs_refuse`, from `_ngt_refuse`
#       and the readers that answer a type parameter before it) — the list stepped, nothing cascading; in a trait
#       member's signature (its walk ends there) and under CYRIUS_MONOMORPH=0 too (`_gen_ann_sid`'s flag arm, a
#       return's). TP1-TP3 the filed repros verbatim (the fn and its local: two lines; the member; the return);
#       TP4 every position, plain and under the flag — a parameter, `*U<..>`, `**U<..>`, `*fn(U<..>)` and its return,
#       a return `*U<..>` / `(U<..>, i64)`, a local, `*U<..>`, `**U<..>`, `[U<..>]`, `[*U<..>]`, `slice<U<..>>`,
#       `Vec<U<..>>`, `U<..>[4]`, sizeof, a struct field `a: T<..>` (an instance re-reads it silently) and `*T<..>`,
#       a member's return / `*U<..>` / `*fn(U<..>)` / multi-value element, an impl method's parameter and return, a
#       trait default's local, a generic body called at three types (once); TPX --syntax-only silent (as 6.7.15's
#       D6); TP5 the impl check beside it: a member's `: U<i64>` against an impl's `: U`, and an impl's `: U<i64>`
#       against a member's `: U` — the refusal alone, no "'P.m' returns U, trait 'T' declares U<i64>" (`_ty_rd_shape`
#       counts the shape as its reader's refusal, as 6.7.16 does for `Pt<i64>`; the impl's own return was otherwise
#       swallowed behind that line); TPK controls — `U`, `*U`, `[U]`, sizeof(U), `Box<U>`, `Vec<U>` in a generic,
#       unchanged (exit 36; 43 under the flag, every T its i64 base). A
#       type argument's own (`h<T<u8>>`) is 6.7.14's, unchanged. Issue row 4:
#       issues/2026-10-21-generic-parameter-and-type-argument-lists-judged-by-position.md. Mutant (2026-10-22): the
#       compiler before (4de25d178) -> RED 63: TP1-TP3 and TP4 on both legs (built, or the parse errors and their
#       cascades), TPX on tp3 / tp_sf (lint's own parse errors there) and A [pe] (both) / [macho] TP1. TP5: the D6 commit
#       without `_ty_rd_shape`'s arm (3e9a46cff) -> RED TP5a (the impl's line beside the member's), TP5b (the impl's line
#       in place of the method's own refusal), both legs.
#
#   AD  (6.7.17, met in genb's GB1, no decision: the shape was refused already, as a cascade) `&` OF A FN WRITTEN WITH A
#       TYPE-ARGUMENT LIST: `&nf<i64>` / `&gg<i32>` were "undefined variable 'i64'" + "expected ';', got '>'" (the `&`
#       factor took the name and left the list to the expression as comparisons). `_amp_targs` (parse_expr.cyr): a fn
#       that is not generic gets 6.7.16's line, the list stepped and its address taken; a generic fn's instance one line
#       by name, "cannot take the address of a generic instance: 'gg' - ...", the list and a call's `( .. )` stepped.
#       AD1-AD5 plain and under the flag (a local, a global's initializer, a callptr argument, `&gg<i32>(3)`); ADK the
#       controls (`&gg < a` a comparison, `&gg` / `&nf` taken and called: exit 10). Mutant (2026-10-22): the compiler
#       before (dd2ac95fc) -> RED 12: AD1-AD5 on both legs, A [pe] / [macho] AD2 (A [a64] / [cx] build from the tree).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=type_args_on_nongeneric_refused
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
trap 'rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null
unset CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE CYRIUS_BOUNDS CYRIUS_MONOMORPH
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

# one <name> <expected text> <what> [compiler-cmd]: refused with EXACTLY one error line, which carries <text>.
one() {
    rc=0
    if [ $# -ge 4 ]; then sh -c "$4" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?
    else "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?; fi
    n=$(grep -c '^error' "$D/$1.err" || true)   # 0 lines: grep exits 1 (bash -eo pipefail)
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines, want 1: $(grep '^error' "$D/$1.err" | tr '\n' '|')"
    elif ! grep -qF -- "$2" "$D/$1.err"; then bad "$3: refused, but not with \"$2\": $(grep '^error' "$D/$1.err")"
    else ok "$3: $2"; fi
}
H='include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
impl Show for i64 { fn show(self): i64 { return self + 1; } }
impl Pt { fn m(self, k): i64 { return self.y + k; } }
struct W { v: Pt; p: *Pt; n; }
struct Box<T> { v: T; n; }
fn nf(a): i64 { return a; }
fn id(a): i64 { return a; }'
mk() { printf '%s\n%s\nsyscall(60, go());\n' "$H" "$2" > "$D/$1.cyr"; }
FN="'nf' is not a generic fn: it takes no type arguments"
MT="'Pt.m' is not a generic method: it takes no type arguments"

# ── R: a fn that is not generic ──────────────────────────────────────────────────────────────────────────────
mk r1 'fn go(): i64 { return nf<i64>(6); }'
one r1 "11:23: $FN" "R1: return nf<i64>(6)"
mk r2 'fn go(): i64 { nf<i64>(6); return 1; }'
one r2 "11:16: $FN" "R2: nf<i64>(6); — a statement (it was \"expected '=', got '<'\")"
mk r3 'fn go(): i64 { var r = nf<i64>(6); return r; }'
one r3 "11:24: $FN" "R3: var r = nf<i64>(6);"
mk r4 'fn go(): i64 { return id(nf<i64>(6)); }'
one r4 "11:26: $FN" "R4: an argument, id(nf<i64>(6))"
mk r5 'fn go(): i64 { return nf<i64, Pt>(6); }'
one r5 "11:23: $FN" "R5: two type arguments"
mk r6 'fn go(): i64 { return nf<Box<i64>>(6); }'
one r6 "11:23: $FN" "R6: a nested instance in the list (its \`>>\` close)"
mk r7 'fn go(): i64 { var p: Pt; p.y = 6; return Pt_m<i64>(&p, 1); }'
one r7 "11:43: 'Pt_m' is not a generic fn: it takes no type arguments" "R7: a method by its fn name, Pt_m<i64>(&p, 1)"

# ── M: a method that is not generic ──────────────────────────────────────────────────────────────────────────
mk m1 'fn go(): i64 { var p: Pt; p.y = 6; return p.m<i64>(1); }'
one m1 "11:45: $MT" "M1: return p.m<i64>(1) (it was \"unknown field 'm' on struct 'Pt'\" + \"undefined variable 'i64'\")"
mk m2 'fn go(): i64 { var p: Pt; p.y = 6; p.m<i64>(1); return 1; }'
one m2 "11:38: $MT" "M2: p.m<i64>(1); — a statement"
mk m3 'fn go(): i64 { var w: W; w.v.y = 6; return w.v.m<i64>(1); }'
one m3 "11:48: $MT" "M3: an inline struct field, w.v.m<i64>(1)"
mk m4 'fn go(): i64 { var w: W; var p: Pt; p.y = 6; w.p = &p; return w.p.m<i64>(1); }'
one m4 "11:67: $MT" "M4: a *Pt field, w.p.m<i64>(1)"
mk m5 'fn gq(q: *Pt): i64 { return q.m<i64>(1); }
fn go(): i64 { var p: Pt; p.y = 6; return gq(&p); }'
one m5 "11:31: $MT" "M5: a *Pt receiver"

# ── B: a bounded T's member that is not generic ──────────────────────────────────────────────────────────────
mk b1 'fn gn<T: Show>(v: T): i64 { return v.show<i64>(); }
fn go(): i64 { var p: Pt; p.y = 6; return gn(p) + gn(5); }'
one b1 "11:38: 'i64.show' is not a generic method: it takes no type arguments" "B1: v.show<i64>() at a scalar and a struct T — once (it was \"no struct type in scope for 'v'\" + 2)"
mk b2 'fn gs<T: Show>(b: Box<T>): i64 { return b.v.show<i64>(); }
fn go(): i64 { var b: Box<i64>; b.v = 5; var c: Box<Pt>; c.v.y = 6; return gs(b) + gs(c); }'
one b2 "11:45: 'i64.show' is not a generic method: it takes no type arguments" "B2: b.v.show<i64>() on a carrier's field (it was \"expected ';', got '.'\" + 2)"

# ── U: no such method; a receiver of no known struct ────────────────────────────────────────────────────────
mk u1 'fn go(): i64 { var p: Pt; p.y = 6; return p.zz<i64>(1); }'
mk u1b 'fn go(): i64 { var p: Pt; p.y = 6; return p.zz(1); }'
"$CC" < "$D/u1.cyr" > /dev/null 2> "$D/u1.err" || true; a=$(grep '^error' "$D/u1.err" || true)
"$CC" < "$D/u1b.cyr" > /dev/null 2> "$D/u1b.err" || true; b=$(grep '^error' "$D/u1b.err" || true)
if [ -n "$a" ] && [ "$a" = "$b" ]; then ok "U1: p.zz<i64>(1) reports what p.zz(1) reports: $a"
else bad "U1: p.zz<i64>(1) [$a] differs from p.zz(1) [$b]"; fi
mk u2 'fn go(): i64 { var p: Pt; p.y = 6; var q = &p; var r = q.m<i64>(1); return r; }'
one u2 "no struct type in scope for 'q'; a method call needs its struct declaration" "U2: an untyped receiver, as q.m(1) (it was the '.field' message + \"undefined variable 'i64'\")"

# ── X: --syntax-only says nothing ────────────────────────────────────────────────────────────────────────────
for x in r1:X1 m1:X2 b1:X3; do
    f=${x%%:*}; w=${x##*:}
    rc=0; "$CC" --syntax-only < "$D/$f.cyr" > /dev/null 2> "$D/$f.so" || rc=$?
    n=$(grep -c '^error' "$D/$f.so" || true)
    if [ "$rc" -eq 0 ] && [ "$n" -eq 0 ]; then ok "$w: --syntax-only on $f is silent (rc 0)"
    else bad "$w: --syntax-only on $f: rc $rc, $n error line(s): $(grep '^error' "$D/$f.so" | tr '\n' '|')"; fi
done

# ── K: controls ──────────────────────────────────────────────────────────────────────────────────────────────
mk k1 'fn id2(a, b): i64 { return a * 10 + b; }
fn gid<T>(x: T): i64 { return sizeof(T); }
impl Pt { fn gm<V>(self, k: V): i64 { return self.y + sizeof(V); } }
fn go(): i64 { var p: Pt; p.y = 6; var w: W; w.n = 3; var a = 9; var b = 3; return id2(p.y < a, b > (1)) + id2(w.n < a, b > (1)) + gid<i32>(4) + p.gm<i16>(1) + gid(7) - 16; }'
rc=0; "$CC" < "$D/k1.cyr" > "$D/k1.bin" 2> "$D/k1.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "K1: rc $rc: $(grep '^error' "$D/k1.err" | head -2 | tr '\n' '|')"
else chmod +x "$D/k1.bin"; got=0; "$D/k1.bin" || got=$?
    if [ "$got" -eq 26 ]; then ok "K1: comparisons keep their reading; a generic fn and method take their lists (exit 26)"
    else bad "K1: exit $got, want 26"; fi
fi

# ── TP: a type parameter written with type arguments (6.7.17, the user's D6) ─────────────────────────────────────
TPW="a type parameter takes no type arguments:"
# tpl <name> <want '|'-joined "L:C: text" lines> <what> [compiler-cmd]: refused with exactly these error lines
tpl() {
    rc=0
    if [ $# -ge 4 ]; then sh -c "$4" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?
    else "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?; fi
    got=$( (grep '^error' "$D/$1.err" || true) | sed 's/^error:<source>://' | tr '\n' '|' | sed 's/|$//')
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$got" != "$2" ]; then bad "$3: got [$got], want [$2]"
    else ok "$3: $2"; fi
}
printf 'fn g<U>(u: U<Nope>): i64 { var l: U<i8> = 0; return 0; }\nfn main(): i64 { return g(1) + 3; }\nsyscall(60, main());\n' > "$D/tp1.cyr"
printf 'trait T { fn m<U>(self, u: U<Nope>): U<i64>; }\nstruct P { x; }\nfn main(): i64 { return 3; }\nsyscall(60, main());\n' > "$D/tp2.cyr"
printf 'fn g<U>(u: U): U<i64> { return u; }\nsyscall(60, 3);\n' > "$D/tp3.cyr"
for leg in plain mono0; do
    cc="$CC"; [ "$leg" = mono0 ] && cc="CYRIUS_MONOMORPH=0 $CC"
    tpl tp1 "1:12: $TPW 'U'|1:35: $TPW 'U'" "TP1 [$leg]: the filed repro verbatim — the parameter and the local (it built: exit 3)" "$cc"
    tpl tp2 "1:28: $TPW 'U'" "TP2 [$leg]: the filed trait member — one line (its walk ends there)" "$cc"
    tpl tp3 "1:16: $TPW 'U'" "TP3 [$leg]: the filed return, one line (it was \"expected '{', got '<'\" + \"undefined variable 'i64'\")" "$cc"
done
TPH='struct Pt { x; y; }'
TPM='fn main(): i64 { return g(1) + 3; }
syscall(60, main());'
tpm() { printf '%s\n%s\n%s\n' "$TPH" "$2" "$TPM" > "$D/$1.cyr"; }
tpm tp_pa 'fn g<U>(u: U<Nope>): i64 { return 0; }'
tpm tp_pp 'fn g<U>(u: *U<i8>): i64 { return 0; }'
tpm tp_ppp 'fn g<U>(u: **U<i8>): i64 { return 0; }'
tpm tp_pfp 'fn g<U>(c: *fn(U<i8>): i64): i64 { return 0; }'
tpm tp_pfr 'fn g<U>(c: *fn(i64): U<i8>): i64 { return 0; }'
tpm tp_rp 'fn g<U>(u: U): *U<i64> { return 0; }'
tpm tp_rm 'fn g<U>(u: U): (U<i64>, i64) { return (u, 1); }'
tpm tp_l 'fn g<U>(u: U): i64 { var l: U<i8> = 0; return 0; }'
tpm tp_lp 'fn g<U>(u: U): i64 { var l: *U<i8> = 0; return 0; }'
tpm tp_lpp 'fn g<U>(u: U): i64 { var l: **U<i8> = 0; return 0; }'
tpm tp_ls 'fn g<U>(u: U): i64 { var l: [U<i8>] = 0; return 0; }'
tpm tp_lsp 'fn g<U>(u: U): i64 { var l: [*U<i8>] = 0; return 0; }'
tpm tp_lsl 'fn g<U>(u: U): i64 { var l: slice<U<i8>> = 0; return 0; }'
tpm tp_lv 'include "lib/vec.cyr"
fn g<U>(u: U): i64 { var l: Vec<U<i8>> = 0; return 0; }'
tpm tp_la 'fn g<U>(u: U): i64 { var l: U<i8>[4]; return 0; }'
tpm tp_so 'fn g<U>(u: U): i64 { return sizeof(U<i8>); }'
tpm tp_sf 'struct S<T> { a: T<i64>; b; }
fn g(u): i64 { var s: S<i8>; return 0; }'
tpm tp_sfp 'struct S<T> { a: *T<i64>; b; }
fn g(u): i64 { var s: S<i8>; return 0; }'
tpm tp_tmr 'trait Tr { fn m<U>(self, u: U): U<i64>; }
fn g(u): i64 { return 0; }'
tpm tp_tmp 'trait Tr { fn m<U>(self, u: *U<i8>): *U<i64>; }
fn g(u): i64 { return 0; }'
tpm tp_tmf 'trait Tr { fn m<U>(self, c: *fn(U<i8>): i64): i64; }
fn g(u): i64 { return 0; }'
tpm tp_tmm 'trait Tr { fn m<U>(self): (U<i8>, i64); }
fn g(u): i64 { return 0; }'
tpm tp_im 'impl Pt { fn m<V>(self, v: V<i8>): i64 { return 1; } }
fn g(u): i64 { return 0; }'
tpm tp_imr 'impl Pt { fn m<V>(self, v: V): V<i8> { return v; } }
fn g(u): i64 { return 0; }'
tpm tp_td 'trait Tr { fn m<U>(self, u: U): i64 { var l: U<i8> = 0; return 1; } }
impl Tr for Pt { }
fn g(u): i64 { var p: Pt; return p.m(1); }'
tpm tp_gb 'fn g<U>(u: U): i64 { var l: U<i8> = 0; return 0; }
fn w(): i64 { return g(1) + g(2.0) + g(3) + g(4); }'
for leg in plain mono0; do
    cc="$CC"; [ "$leg" = mono0 ] && cc="CYRIUS_MONOMORPH=0 $CC"
    tpl tp_pa "2:12: $TPW 'U'" "TP4 [$leg]: a parameter" "$cc"
    tpl tp_pp "2:13: $TPW 'U'" "TP4 [$leg]: a *U<..> parameter" "$cc"
    tpl tp_ppp "2:14: $TPW 'U'" "TP4 [$leg]: a **U<..> parameter" "$cc"
    tpl tp_pfp "2:16: $TPW 'U'" "TP4 [$leg]: a *fn(U<..>) parameter" "$cc"
    tpl tp_pfr "2:22: $TPW 'U'" "TP4 [$leg]: a *fn( .. ): U<..> parameter" "$cc"
    tpl tp_rp "2:17: $TPW 'U'" "TP4 [$leg]: a *U<..> return" "$cc"
    tpl tp_rm "2:17: $TPW 'U'" "TP4 [$leg]: a multi-value element" "$cc"
    tpl tp_l "2:29: $TPW 'U'" "TP4 [$leg]: a local" "$cc"
    tpl tp_lp "2:30: $TPW 'U'" "TP4 [$leg]: a *U<..> local" "$cc"
    tpl tp_lpp "2:31: $TPW 'U'" "TP4 [$leg]: a **U<..> local" "$cc"
    tpl tp_ls "2:30: $TPW 'U'" "TP4 [$leg]: a slice element [U<..>]" "$cc"
    tpl tp_lsp "2:31: $TPW 'U'" "TP4 [$leg]: a slice element [*U<..>]" "$cc"
    tpl tp_lsl "2:35: $TPW 'U'" "TP4 [$leg]: slice<U<..>>" "$cc"
    tpl tp_lv "3:33: $TPW 'U'" "TP4 [$leg]: Vec<U<..>>" "$cc"
    tpl tp_la "2:29: $TPW 'U'" "TP4 [$leg]: an array local U<..>[4]" "$cc"
    tpl tp_so "2:36: $TPW 'U'" "TP4 [$leg]: sizeof(U<..>)" "$cc"
    tpl tp_sf "2:18: $TPW 'T'" "TP4 [$leg]: a struct field a: T<..>, and its instance" "$cc"
    tpl tp_sfp "2:19: $TPW 'T'" "TP4 [$leg]: a struct field a: *T<..>" "$cc"
    tpl tp_tmr "2:33: $TPW 'U'" "TP4 [$leg]: a trait member's return" "$cc"
    tpl tp_tmp "2:30: $TPW 'U'" "TP4 [$leg]: a trait member's *U<..> (its walk ends there)" "$cc"
    tpl tp_tmf "2:33: $TPW 'U'" "TP4 [$leg]: a trait member's *fn(U<..>)" "$cc"
    tpl tp_tmm "2:28: $TPW 'U'" "TP4 [$leg]: a trait member's multi-value element" "$cc"
    tpl tp_im "2:28: $TPW 'V'" "TP4 [$leg]: an impl method's parameter" "$cc"
    tpl tp_imr "2:32: $TPW 'V'" "TP4 [$leg]: an impl method's return" "$cc"
    tpl tp_td "2:46: $TPW 'U'" "TP4 [$leg]: a trait default's local (inherited)" "$cc"
    tpl tp_gb "2:29: $TPW 'U'" "TP4 [$leg]: a generic body called at two types (once)" "$cc"
done
for x in tp1 tp3 tp_l tp_sf; do
    rc=0; "$CC" --syntax-only < "$D/$x.cyr" > /dev/null 2> "$D/$x.so" || rc=$?
    if [ "$rc" -eq 0 ] && [ "$(grep -c '^error' "$D/$x.so")" -eq 0 ]; then ok "TPX: --syntax-only on $x is silent"
    else bad "TPX: --syntax-only on $x: rc $rc: $(grep '^error' "$D/$x.so" | tr '\n' '|')"; fi
done
printf 'trait T { fn m<U>(self, u: U): U<i64>; fn n<V>(self, v: V<i8>): i64; }\nstruct P { x; }\nimpl T for P { fn m<U>(self, u: U): U { return u; } fn n<V>(self, v: V): i64 { return 1; } }\nfn main(): i64 { var p: P; return 3; }\nsyscall(60, main());\n' > "$D/tp5a.cyr"
printf 'trait T { fn m<U>(self, u: U): U; fn n<V>(self, v: V): i64; }\nstruct P { x; }\nimpl T for P { fn m<U>(self, u: U): U<i64> { return u; } fn n<V>(self, v: V<i8>): i64 { return 1; } }\nfn main(): i64 { var p: P; return 3; }\nsyscall(60, main());\n' > "$D/tp5b.cyr"
tpl tp5a "1:32: $TPW 'U'|1:57: $TPW 'V'" "TP5a [plain]: a member's U<i64> against an impl's U — no impl line beside it"
tpl tp5b "3:37: $TPW 'U'|3:75: $TPW 'V'" "TP5b [plain]: an impl's U<i64> against a member's U — its own refusal, no impl line"
# under the flag a `: U` return is the flag's own refusal (unchanged); the impl's U<i64> still D6's line alone
tpl tp5b "3:37: $TPW 'U'|3:75: $TPW 'V'" "TP5b [mono0]" "CYRIUS_MONOMORPH=0 $CC"
cat > "$D/tpk.cyr" <<'EOF'
include "lib/vec.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn g<U>(u: U): i64 { var l: U = u; var p: *U = &l; var b: Box<U>; b.n = 1; var v: Vec<U> = 0; var s: [U] = 0; return l + sizeof(U) + b.n + 0 * load64(p); }
fn h<T>(b: Box<T>, q: *T): i64 { return sizeof(T) + b.n; }
fn main(): i64 { var b: Box<i8>; b.n = 2; var x: i8 = 1; return g(3) + g(4) + h(b, &x) + 8; }
syscall(60, main());
EOF
for leg in plain mono0; do
    rc=0
    if [ "$leg" = mono0 ]; then CYRIUS_MONOMORPH=0 "$CC" < "$D/tpk.cyr" > "$D/tpk_$leg" 2> "$D/tpk_$leg.err" || rc=$?
    else "$CC" < "$D/tpk.cyr" > "$D/tpk_$leg" 2> "$D/tpk_$leg.err" || rc=$?; fi
    if [ "$rc" -ne 0 ]; then bad "TPK [$leg]: controls: rc $rc: $(grep '^error' "$D/tpk_$leg.err" | head -2 | tr '\n' '|')"; continue; fi
    chmod +x "$D/tpk_$leg"; got=0; "$D/tpk_$leg" || got=$?
    # plain: g(3) 12 + g(4) 13 + h 3 + 8 = 36; under the flag every T is the i64 base, h's sizeof(T) 8: 43
    want=36; [ "$leg" = mono0 ] && want=43
    if [ "$got" -eq "$want" ]; then ok "TPK [$leg]: U, *U, [U], sizeof(U), Box<U>, Vec<U> in a generic, unchanged: exit $got"; else bad "TPK [$leg]: exit $got, want $want"; fi
done

# ── AD: `&` of a fn written with a type-argument list (6.7.17, met in genb's GB1) ────────────────────────────
# `&nf<i64>` / `&gg<i32>` were "undefined variable 'i64'" + "expected ';', got '>'" (the `&` factor took the name and
# left the list to the expression as comparisons). A fn that is not generic: 6.7.16's line, the list stepped, nf's
# address taken; a generic one's instance: one line by name, the list (and a call's `( .. )`) stepped.
AW="cannot take the address of a generic instance: 'gg'"
mk ad1 'fn go(): i64 { var f = &nf<i64>; return callptr(f, 6); }'
mk ad2 'fn gg<T>(x: T): i64 { return 1; }
fn go(): i64 { var f = &gg<i32>; return 3; }'
mk ad3 'fn gg<T>(x: T): i64 { return 1; }
var GF = &gg<i32>;
fn go(): i64 { return 3; }'
mk ad4 'fn gg<T>(x: T): i64 { return 1; }
fn go(): i64 { return callptr(&gg<Pt>, 3); }'
mk ad5 'fn gg<T>(x: T): i64 { return 1; }
fn go(): i64 { var f = &gg<i32>(3); return 3; }'
for leg in plain mono0; do
    C="$CC"; [ "$leg" = mono0 ] && C="CYRIUS_MONOMORPH=0 $CC"
    one ad1 "11:25: $FN" "AD1 [$leg]: &nf<i64> — the list stepped, nf's address taken" "$C"
    one ad2 "12:25: $AW" "AD2 [$leg]: var f = &gg<i32>;" "$C"
    one ad3 "12:11: $AW" "AD3 [$leg]: a global's initializer" "$C"
    one ad4 "12:32: $AW" "AD4 [$leg]: a callptr argument, &gg<Pt>" "$C"
    one ad5 "12:25: $AW" "AD5 [$leg]: &gg<i32>(3) — the call's ( .. ) stepped too" "$C"
done
# controls: `&gg < a` stays a comparison; `&gg` (the base) and `&nf` are taken and called
mk adk 'fn gg<T>(x: T): i64 { return x + 1; }
fn go(): i64 { var a = 1; var c = &gg < a; var f = &gg; var h = &nf; return callptr(f, 6) + callptr(h, 3) + c; }'
for leg in plain mono0; do
    rc=0
    if [ "$leg" = mono0 ]; then CYRIUS_MONOMORPH=0 "$CC" < "$D/adk.cyr" > "$D/adk_$leg" 2> "$D/adk_$leg.err" || rc=$?
    else "$CC" < "$D/adk.cyr" > "$D/adk_$leg" 2> "$D/adk_$leg.err" || rc=$?; fi
    if [ "$rc" -ne 0 ]; then bad "ADK [$leg]: rc $rc: $(grep '^error' "$D/adk_$leg.err" | head -2 | tr '\n' '|')"; continue; fi
    chmod +x "$D/adk_$leg"; got=0; "$D/adk_$leg" || got=$?
    if [ "$got" -eq 10 ]; then ok "ADK [$leg]: &gg < a a comparison, &gg and &nf taken and called: exit 10"; else bad "ADK [$leg]: exit $got, want 10"; fi
done

# ── A: the refusal from every cross compiler ─────────────────────────────────────────────────────────────────
A64="$D/cc_a64"; CXCC="$D/cc_cx"
if "$CC" < src/main_aarch64.cyr > "$A64" 2> /dev/null && [ -s "$A64" ]; then chmod +x "$A64"
    one r1 "11:23: $FN" "A [a64]: R1" "$A64"; one m1 "11:45: $MT" "A [a64]: M1" "$A64"
    tpl tp1 "1:12: $TPW 'U'|1:35: $TPW 'U'" "A [a64]: TP1" "$A64"
    one ad2 "12:25: $AW" "A [a64]: AD2" "$A64"
else bad "aarch64: src/main_aarch64.cyr did not build"; fi
if "$CC" < src/main_cx.cyr > "$CXCC" 2> /dev/null && [ -s "$CXCC" ]; then chmod +x "$CXCC"
    one r1 "11:23: $FN" "A [cx]: R1" "$CXCC"; one m1 "11:45: $MT" "A [cx]: M1" "$CXCC"
    tpl tp1 "1:12: $TPW 'U'|1:35: $TPW 'U'" "A [cx]: TP1" "$CXCC"
    one ad2 "12:25: $AW" "A [cx]: AD2" "$CXCC"
else bad "cx: src/main_cx.cyr did not build"; fi
one r1 "11:23: $FN" "A [pe]: R1" "CYRIUS_TARGET_WIN=1 $CC"
one m1 "11:45: $MT" "A [pe]: M1" "CYRIUS_TARGET_WIN=1 $CC"
tpl tp1 "1:12: $TPW 'U'|1:35: $TPW 'U'" "A [pe]: TP1" "CYRIUS_TARGET_WIN=1 $CC"
tpl tp1 "1:12: $TPW 'U'|1:35: $TPW 'U'" "A [pe]: TP1 under the flag" "CYRIUS_MONOMORPH=0 CYRIUS_TARGET_WIN=1 $CC"
tpl tp1 "1:12: $TPW 'U'|1:35: $TPW 'U'" "A [macho]: TP1" "CYRIUS_MACHO=1 $CC"
one ad2 "12:25: $AW" "A [pe]: AD2" "CYRIUS_TARGET_WIN=1 $CC"
one ad2 "12:25: $AW" "A [macho]: AD2" "CYRIUS_MACHO=1 $CC"

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
echo "PASS: $G — a type-argument list on a fn or method that is not generic is refused once, at its name, and the call parsed as its plain spelling: a fn (R), a method (M), a bounded T's member (B), no such method / an untyped receiver as the plain spelling (U), silent under --syntax-only (X), comparisons and generic callees unchanged (K), a type parameter written with arguments refused in every position (TP, 6.7.17's D6), &-of a fn written with a type-argument list (AD, 6.7.17), every cross compiler (A)"
exit 0
