#!/bin/sh
# tests/gates/frontend/dead_fn_body_syntax_checked.sh — v6.5.17
#
# EVERY fn body is parsed, whether or not anything calls it.
#
# THE FILED DEFECT (hisab, 2026-08-09). A function that nothing called, AND whose
# name contained no underscore, had its body SKIPPED: pass 2 emitted a 3-byte
# `xor eax,eax; ret` stub and brace-skipped the tokens, so arbitrary garbage inside
# it compiled green and `build` / `lint` / `vet` / `check` all agreed. Both
# conditions were required, and the second is the one that makes this a bug rather
# than a policy: whether your function was syntax-checked depended on a CHARACTER IN
# ITS IDENTIFIER. (The underscore guard was there because `mod_fn` name mangling
# makes the offset-keyed reference bitmap unreliable — a real problem, guarded by a
# proxy that happens to cover snake_case and expose camelCase.)
#
# It was also FORK-DIVERGENT: the skip lived in main.cyr / main_win.cyr /
# main_x86_macho.cyr / main_cx.cyr and never in the three aarch64 drivers, so the
# same source was accepted on x86/PE/Mach-O and REJECTED on aarch64.
#
# WHAT THIS GATE ASSERTS — on the COMPILER'S EXIT CODE, not on stdout text:
#   1. a syntax error in an uncalled underscore-free fn FAILS the build,
#   2. across a spread of name shapes, because the old behaviour was keyed on the
#      name (one name proves nothing — `n` and `len` were already checked by
#      accident, since some stdlib file uses them as locals),
#   3. the underscore and called variants still fail (no regression),
#   4. a CLEAN file with an uncalled underscore-free fn still compiles, so the gate
#      cannot pass by rejecting everything,
#   5. the diagnostic names a line — a bare non-zero exit is not a diagnostic.
#
# MUTATION PROOF: restore the `dce_has_us == 0` + bitmap skip in src/main.cyr and
# case 1 goes RED for gg / victim / abcdefghij / a while the underscore case stays
# green — which is exactly the filed truth table.

set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
CC="${CC:-$ROOT/build/cycc}"

if [ ! -x "$CC" ]; then
    printf "  SKIP: dead-fn-body-syntax-checked — %s not built\n" "$CC"
    exit 77
fi

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: dead_fn_body_syntax_checked: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
fail=0

# The body is the filing's verbatim garbage. `$1` is the fn name, `$2` is either
# "call" (main calls it) or "dead" (nothing does).
emit_broken() {
    if [ "$2" = "call" ]; then
        printf 'fn %s() { var x = ; this is not cyrius at all ]] ((\n    return 0; }\nfn main() { return %s(); }\nvar r = main();\n' "$1" "$1" > "$T/p.cyr"
    else
        printf 'fn %s() { var x = ; this is not cyrius at all ]] ((\n    return 0; }\nfn main() { return 0; }\nvar r = main();\n' "$1" > "$T/p.cyr"
    fi
}

compile() {
    # Never merge stderr into the output stream — that produces a "binary" that
    # looks runnable. Separate files, and the exit code is what we judge.
    "$CC" < "$T/p.cyr" > "$T/out.bin" 2> "$T/err.txt" && echo 0 || echo 1
}

echo "axis 1 — a syntax error in an UNCALLED fn fails the build, whatever the name:"
for n in gg victim abcdefghij a broken_fn victim_x; do
    emit_broken "$n" dead
    rc=$(compile)
    if [ "$rc" = 1 ]; then
        echo "  ok: uncalled '$n' rejected (1)"
    else
        echo "  FAIL: uncalled '$n' COMPILED — a body with a syntax error was never parsed"
        fail=$((fail + 1))
    fi
done

echo "axis 2 — the same fn, called, still fails (no regression on the path that always worked):"
for n in gg broken_fn; do
    emit_broken "$n" call
    rc=$(compile)
    if [ "$rc" = 1 ]; then
        echo "  ok: called '$n' rejected (1)"
    else
        echo "  FAIL: called '$n' compiled"
        fail=$((fail + 1))
    fi
done

echo "axis 3 — the diagnostic NAMES the offending line (a bare exit 1 is not a diagnostic):"
emit_broken gg dead
compile > /dev/null
if grep -q "unexpected ';'" "$T/err.txt" 2>/dev/null; then
    echo "  ok: error text present (1)"
else
    echo "  FAIL: no 'unexpected' diagnostic for the uncalled fn"
    head -3 "$T/err.txt" 2>/dev/null || true
    fail=$((fail + 1))
fi
if grep -qE '<source>:[0-9]+:[0-9]+' "$T/err.txt" 2>/dev/null; then
    echo "  ok: line:column cited (1)"
else
    echo "  FAIL: diagnostic carries no line:column"
    head -3 "$T/err.txt" 2>/dev/null || true
    fail=$((fail + 1))
fi

echo "axis 4 — ⭐ ANTI-VACUOUS: a CLEAN file with an uncalled underscore-free fn still builds:"
printf 'fn gg() { var x = 1;\n    return x; }\nfn main() { return 0; }\nvar r = main();\n' > "$T/p.cyr"
rc=$(compile)
if [ "$rc" = 0 ]; then
    echo "  ok: clean dead fn compiles (0)"
else
    echo "  FAIL: a CLEAN uncalled fn was rejected — this gate would pass by rejecting everything"
    head -3 "$T/err.txt" 2>/dev/null || true
    fail=$((fail + 1))
fi

# ── AXIS 5 (6.7.17, the D33 review's finding) — A BODY PASS 2 NEVER PARSES IS READ FOR ITS SYNTAX. A trait default no
# impl inherits (or every impl overrides) and a generic base pass 2 steps — a stub (`p.x` on a T) or a bounded generic
# i64 does not satisfy — that no instance re-parses were never parsed, so `trait T { fn d(self): i64 { return 1 +; } }`
# compiled (rc 0, exit 3). Now each is parsed once after the image is built (`_unp_run`, parse_fn_def.cyr), MUTED
# through `_ew` (diagnostic_writer_census.sh): only a syntax error is said, at its token, in the words a plain dead fn's
# gets; one refuses the build and no image is written. Five legs: the x86_64, PE and Mach-O compilers and the aarch64
# and cx compilers built from this tree. NP1 the filed repro verbatim; NP2 a bounded generic fn, NP3 a bounded generic
# method, NP4 a stub generic, never instantiated; NP5 a default every impl overrides; NP6 axis 1's garbage in a
# default (one line, as in a plain dead fn); NP7 two bodies, each its own line; NP8 / NP9 controls — an instantiated
# generic's and an inherited default's error said ONCE (their parse said it; the read is not run); NP10 --syntax-only;
# NP11 beside another error (said after it). NPV ⭐ ANTI-VACUOUS: never-parsed bodies full of what only an instance can
# judge — `x.show()`, `p.x`, `return &n` from a struct-returning generic, a forward of T into a stub, `Box<T>`,
# `sizeof(T)`, a capturing closure, `for y in x.a..10`, an untyped `self.k` — compile clean and run (exit 3).
# MUTATIONS (2026-10-22, measured): the merged tree's compiler before this (no read) -> RED 27, NP1-NP7, NP10, NP11 on
# the x86_64 / PE / Mach-O legs (rc 0 / the line missing; the a64 / cx compilers are built from this tree); `_unp_run`
# without its mute (`_ew_mute` never set) -> RED 5, NPV on every leg ("a capturing closure needs include .." and the
# other instance-only refusals printed).
LEGS="x86 pe macho"
if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> /dev/null && [ -s "$T/cc_a64" ]; then chmod +x "$T/cc_a64"; LEGS="$LEGS a64"
else echo "  FAIL: src/main_aarch64.cyr did not build"; fail=$((fail + 1)); fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2> /dev/null && [ -s "$T/cc_cx" ]; then chmod +x "$T/cc_cx"; LEGS="$LEGS cx"
else echo "  FAIL: src/main_cx.cyr did not build"; fail=$((fail + 1)); fi
NPN=0
npc() {   # <leg> <src> <out> [cc-arg]: rc in NRC
    NRC=0
    case "$1" in
        x86)   timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || NRC=$? ;;
        pe)    CYRIUS_TARGET_WIN=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || NRC=$? ;;
        macho) CYRIUS_MACHO=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || NRC=$? ;;
        a64)   timeout 60 "$T/cc_a64" ${4:-} < "$2" > "$3" 2> "$3.err" || NRC=$? ;;
        cx)    timeout 60 "$T/cc_cx" ${4:-} < "$2" > "$3" 2> "$3.err" || NRC=$? ;;
    esac
}
np5() {   # <id> <what> <source> <want-lines> [cc-arg]: refused, exactly <want> as its error / warning lines, no image
    printf '%s' "$3" > "$T/$1.cyr"
    printf '%s\n' "$4" > "$T/$1.want"
    for leg in $LEGS; do
        o="$T/$1_$leg"
        npc "$leg" "$T/$1.cyr" "$o" "${5:-}"
        NPN=$((NPN + 1))
        grep -E '^(error|warning)' "$o.err" > "$o.got" || true
        if [ "$NRC" -eq 0 ]; then echo "  FAIL: $1 $leg: $2: rc 0"; fail=$((fail + 1))
        elif ! cmp -s "$o.got" "$T/$1.want"; then echo "  FAIL: $1 $leg: $2: got $(tr '\n' '|' < "$o.got")"; fail=$((fail + 1))
        elif [ -s "$o" ] && [ -z "${5:-}" ]; then echo "  FAIL: $1 $leg: $2: refused, but an image was written"; fail=$((fail + 1))
        else echo "  ok: $1 $leg: $2"; fi
    done
}
npok() {   # <id> <what> <source> <exit>: compiles clean on every leg, runs <exit> on x86_64
    printf '%s' "$3" > "$T/$1.cyr"
    for leg in $LEGS; do
        o="$T/$1_$leg"
        npc "$leg" "$T/$1.cyr" "$o"
        NPN=$((NPN + 1))
        if [ "$NRC" -ne 0 ] || [ ! -s "$o" ] || grep -qE '^(error|warning)' "$o.err"; then
            echo "  FAIL: $1 $leg: $2: rc $NRC: $(grep -E '^(error|warning)' "$o.err" | head -3 | tr '\n' '|')"; fail=$((fail + 1))
        elif [ "$leg" = x86 ]; then
            chmod +x "$o"; x=0; ( ulimit -c 0; timeout 30 "$o" ) > /dev/null 2>&1 || x=$?
            if [ "$x" = "$4" ]; then echo "  ok: $1 $leg: $2 (exit $x)"; else echo "  FAIL: $1 $leg: $2: exit $x, want $4"; fail=$((fail + 1)); fi
        else echo "  ok: $1 $leg: $2"; fi
    done
}
echo "axis 5 — a body pass 2 never parses (an un-inherited trait default, an uninstantiated generic) is read for its syntax:"
MN='fn main(): i64 { return 3; }
var r = main();
syscall(60, r);
'
SH='trait Show { fn s(self): i64; }
'
np5 NP1 "filed: a trait default no impl inherits" "trait T { fn d(self): i64 { return 1 +; } }
$MN" "error:<source>:1:39: unexpected ';'"
np5 NP2 "an uninstantiated bounded generic fn" "${SH}fn gg<T: Show>(x: T): i64 { return 1 +; }
$MN" "error:<source>:2:39: unexpected ';'"
np5 NP3 "an uninstantiated bounded generic method" "${SH}struct Q { k; }
impl Q { fn m<T: Show>(self, v: T): i64 { return 1 +; } }
$MN" "error:<source>:3:53: unexpected ';'"
np5 NP4 "an uncalled stub generic (p.x on a T)" "fn wrap<T>(p: T): i64 { var a = p.x; return 1 +; }
$MN" "error:<source>:1:48: unexpected ';'"
np5 NP5 "a default every impl overrides" "trait T { fn d(self): i64 { return 1 +; } }
struct P { k; }
impl T for P { fn d(self): i64 { return 5; } }
$MN" "error:<source>:1:39: unexpected ';'"
np5 NP6 "axis 1's garbage in a default: one line, as a plain dead fn's" "trait T { fn d(self) { var x = ; this is not cyrius at all ]] ((
    return 0; } }
fn main() { return 0; }
var r = main();
" "error:<source>:1:32: unexpected ';'"
np5 NP7 "two never-parsed bodies: each its own line" "trait T { fn d(self): i64 { return 1 +; } }
${SH}fn gg<T: Show>(x: T): i64 { return 2 *; }
$MN" "error:<source>:1:39: unexpected ';'
error:<source>:3:39: unexpected ';'"
np5 NP8 "control: an instantiated generic's error, once" "${SH}struct P { k; }
impl Show for P { fn s(self): i64 { return self.k; } }
fn gg<T: Show>(x: T): i64 { return x.s() +; }
fn main(): i64 { var p = P { 3 }; return gg(p); }
var r = main();
syscall(60, r);
" "error:<source>:4:43: unexpected ';'"
np5 NP9 "control: an inherited default's error, once" "trait T { fn d(self): i64 { return 1 +; } }
struct P { k; }
impl T for P { }
fn main(): i64 { var p = P { 3 }; return p.d(); }
var r = main();
syscall(60, r);
" "error:<source>:1:39: unexpected ';'"
np5 NP10 "--syntax-only: the filed repro" "trait T { fn d(self): i64 { return 1 +; } }
$MN" "error:<source>:1:39: unexpected ';'" --syntax-only
np5 NP11 "beside another error: said after it" "trait T { fn d(self): i64 { return 1 +; } }
fn main(): i64 { return zz; }
var r = main();
syscall(60, r);
" "error:<source>:2:27: undefined variable 'zz' (missing include or enum?)
error:<source>:1:39: unexpected ';'"
npok NPV "ANTI-VACUOUS: never-parsed bodies only an instance can judge compile clean" 'trait Show { fn show(self): i64; }
struct S8 { a; }
struct Box<T> { v: T; n; }
fn gx<U>(b: U): i64 { return b.x; }
fn g1<T: Show>(x: T): i64 { var c = |k| { return x.show() + k; }; return fncall1(c, 1) + sizeof(T); }
fn g2<T>(x: T): S8 { var n: T = x; return &n; }
fn g3<T>(x: T): i64 { var q: Box<T>; q.n = 1; return gx(x) + q.n; }
fn g4<T>(x: T): i64 { var s = 0; for y in x.a..10 { s = s + y; } return s; }
struct Q { k; }
impl Q { fn m<T: Show>(self, v: T): i64 { return v.show() + self.k; } }
trait Tr { fn d(self): i64 { return self.k + self.other(); } fn e(self): i64 { var p: S8 = self; return p.a; } }
fn main(): i64 { return 3; }
var r = main();
syscall(60, r);
' 3
[ "$NPN" -ge 60 ] || { echo "  FAIL: axis 5 ran $NPN row-legs (floor 60)"; fail=$((fail + 1)); }

# ── AXIS 6 (6.7.17, D110 — an agent default the user reviews at the release) — AN UNDEFINED NAME IN A BODY PASS 2 NEVER
# PARSES IS REFUSED, as a never-called plain fn's is. `fn gg<T: Show>(x: T): i64 { return zz; }` never instantiated
# compiled (rc 0, exit 3); a name undefined there is undefined in every instance (it does not depend on T), so axis 5's
# read says it too — "undefined variable 'zz'", where a plain dead fn says it — not under --syntax-only (lint's names
# are a sibling file's). NU1 the review's repro verbatim; NU2 every undefined-name site (a read, an assignment, a for
# step, `&v`, a `.field` base) — exactly a plain dead fn's lines (NU2p; each column 13 on, the header's length); NU3 an un-inherited trait default, NU4 a bounded
# generic method, NU5 a stub generic, all never parsed; NU6 --syntax-only: no line, rc 0; NU7 ANTI-VACUOUS: every name
# a body declares or reaches (parameters, locals, a closure's, a loop's, a destructure's, a local const, globals,
# consts, enum members) resolves — clean, exit 3.
# MUTATIONS (2026-10-22, measured, every leg built from the mutated tree): the bite before (axis 5's read, names as
# under --syntax-only) -> RED 25, NU1-NU5 on every leg (rc 0); `_unp_names` never set -> RED 25, the same rows.
echo "axis 6 — an undefined name in a body pass 2 never parses is refused, as a never-called plain fn's (D110):"
NUN0=$NPN
np5 NU1 "the review's repro: an uninstantiated bounded generic's zz" "${SH}fn gg<T: Show>(x: T): i64 { return zz; }
$MN" "error:<source>:2:38: undefined variable 'zz' (missing include or enum?)"
NUF='{ var a = zz; yy = 2; for (var i = 0; i < 2; ww = 1) { } var q = &vv; return uu.f + a; }'
np5 NU2p "control: every undefined-name site in a plain dead fn" "fn h(): i64 $NUF
$MN" "error:<source>:1:25: undefined variable 'zz' (missing include or enum?)
error:<source>:1:33: undefined variable 'yy'
error:<source>:1:64: undefined variable 'ww'
error:<source>:1:81: undefined variable 'vv'
error:<source>:1:95: undefined variable 'uu'"
np5 NU2 "... the same sites in an uninstantiated bounded generic: the same lines" "fn h<T: Show>(x: T): i64 $NUF
${SH}$MN" "error:<source>:1:38: undefined variable 'zz' (missing include or enum?)
error:<source>:1:46: undefined variable 'yy'
error:<source>:1:77: undefined variable 'ww'
error:<source>:1:94: undefined variable 'vv'
error:<source>:1:108: undefined variable 'uu'"
np5 NU3 "an un-inherited trait default's zz" "trait T { fn d(self): i64 { return zz; } }
$MN" "error:<source>:1:38: undefined variable 'zz' (missing include or enum?)"
np5 NU4 "an uninstantiated bounded generic method's zz" "${SH}struct Q { k; }
impl Q { fn m<T: Show>(self, v: T): i64 { return zz + self.k; } }
$MN" "error:<source>:3:53: undefined variable 'zz' (missing include or enum?)"
np5 NU5 "an uncalled stub generic's zz" "fn wrap<T>(p: T): i64 { return p.x + zz; }
$MN" "error:<source>:1:40: undefined variable 'zz' (missing include or enum?)"
printf '%s' "${SH}fn gg<T: Show>(x: T): i64 { return zz; }
$MN" > "$T/NU6.cyr"
for leg in $LEGS; do
    npc "$leg" "$T/NU6.cyr" "$T/NU6_$leg" --syntax-only
    NPN=$((NPN + 1))
    if [ "$NRC" -ne 0 ] || grep -qE '^(error|warning)' "$T/NU6_$leg.err"; then
        echo "  FAIL: NU6 $leg: --syntax-only: rc $NRC: $(grep -E '^(error|warning)' "$T/NU6_$leg.err" | tr '\n' '|')"; fail=$((fail + 1))
    else echo "  ok: NU6 $leg: --syntax-only says no name (rc 0)"; fi
done
npok NU7 "ANTI-VACUOUS: every name a never-parsed body reaches resolves" 'trait Show { fn s(self): i64; }
enum E { A, B }
const K = 4;
var gl = 5;
fn two(): (i64, i64) { return (1, 2); }
fn gg<T: Show>(x: T, n): i64 {
    var a = n + gl + K + E.B + B;
    var c = |y| { return y + a; };
    for i in 0..n { a = a + i; }
    var p, q = two();
    const L = 2;
    return x.s() + fncall1(c, 1) + p + q + L;
}
trait Tr { fn d(self, k): i64 { var z = k + gl; return self.k + z; } }
fn main(): i64 { return 3; }
var r = main();
syscall(60, r);
' 3
[ "$((NPN - NUN0))" -ge 40 ] || { echo "  FAIL: axis 6 ran $((NPN - NUN0)) row-legs (floor 40)"; fail=$((fail + 1)); }

if [ "$fail" != 0 ]; then
    echo "FAIL: dead-fn-body-syntax-checked — $fail assertion(s) failed"
    exit 1
fi
echo "PASS: dead-fn-body-syntax-checked — every fn body is parsed, name-independent"
exit 0
