#!/bin/sh
# v6.5.24 — `assigning non-pointer to typed pointer` must test the RIGHT SIGN.
#
# The local-variable arm of this warning gated on `lt > 0`, but in the local SLTYPE scheme
# a positive type is a narrow WIDTH (1/2/4) or a FLOAT TAG (F64_TYID 0x40000001 /
# F32_TYID 0x40000002); the pointer-like case is stored NEGATIVE as `0 - sid`
# (src/frontend/parse_decl.cyr:2490). The test was therefore inverted, with a failure mode
# in BOTH directions at once — it fired on every width- or float-annotated local, and
# never on a real typed-pointer local, so the check was unreachable for its own purpose.
# The GLOBAL arm of the same warning (`vt < 0`, src/frontend/parse.cyr:~1550) had always
# used the correct convention, so the two arms silently disagreed.
#
# ⛔ WHY A GATE. This is a WARNING, so no .tcyr can catch it: warnings don't change exit
# codes, and the false positives were visible only as noise in consumer builds. That is
# how it survived — and it was not harmless. The f64/f32 half BLOCKED a consumer feature:
# `acc = f32_op(acc, ...)` is the canonical ranga/ganita loop body, so shipping the f32
# math tier while this warned would have put a bogus warning in every consumer's f32 loop.
#
# ⭐ AXIS 4 IS THE ANTI-VACUOUS ONE. Axes 1-3 all assert an ABSENCE, so deleting the
# warning outright would make them all pass. Axis 4 requires the warning to still fire on
# a genuine typed pointer, which is also the case that never worked before this fix.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 77; }
cd "$ROOT"
T=$(mktemp --suffix=.cyr) && [ -f "$T" ] || { echo "FAIL: typed_pointer_warn_sign: mktemp --suffix=.cyr failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
E=$(mktemp) && [ -f "$E" ] || { echo "FAIL: typed_pointer_warn_sign: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
O=$(mktemp) && [ -f "$O" ] || { echo "FAIL: typed_pointer_warn_sign: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -f "$T" "$E" "$O"' EXIT

# Compile $T and put stderr in $E. NEVER merge stderr into the binary stream.
build() { "$CC" < "$T" > "$O" 2>"$E" || true; }
warns() { grep -c "assigning non-pointer to typed pointer" "$E" || true; }

fail=0

# --- axis 1: narrow-width annotated local must not warn on ordinary reassignment ---
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var w: i32 = 5;
    w = 6;
    return w;
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -ne 0 ]; then echo "  FAIL axis 1: 'var w: i32; w = 6;' emitted $n typed-pointer warning(s)"; fail=1
else echo "  ok axis 1: narrow-width local (i32) does not warn"; fi

# --- axis 2: f64-annotated local must not warn (the half that gated the ganita f32 tier) ---
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var acc: f64 = f64_from(1);
    acc = f64_add(acc, f64_from(2));
    return f64_to(acc);
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -ne 0 ]; then echo "  FAIL axis 2: 'var acc: f64; acc = f64_add(..)' emitted $n typed-pointer warning(s)"; fail=1
else echo "  ok axis 2: f64 accumulator does not warn"; fi

# --- axis 3: f32-annotated local must not warn (same tag class, distinct TYID) ---
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var s: f32 = f32_from(f64_from(1));
    s = f32_from(f64_from(2));
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -ne 0 ]; then echo "  FAIL axis 3: 'var s: f32; s = ..' emitted $n typed-pointer warning(s)"; fail=1
else echo "  ok axis 3: f32 local does not warn"; fi

# --- axis 4 (ANTI-VACUOUS): a real typed pointer assigned a non-pointer MUST warn ---
# Before this fix this case produced NO warning at all — the check could not reach it.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
struct Pt { x: i64; y: i64; }
fn main(): i64 {
    var p: Pt = 0;
    p = 7;
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -lt 1 ]; then echo "  FAIL axis 4 (anti-vacuous): struct-typed local assigned a non-pointer did NOT warn — the check is unreachable again, or was deleted"; fail=1
else echo "  ok axis 4: struct-typed local assigned a non-pointer warns (check is reachable)"; fi

# --- axis 5 (v6.5.28): the assignment path must consult the callee's DECLARED return type ---
# v6.5.27's sign fix made this check reach real typed-pointer locals for the FIRST time, and
# exposed the gap behind it: the DECLARATION path resolves the callee's return sid
# (parse_decl.cyr: peek `IDENT (`, FINDFN, GFRS) but the ASSIGNMENT path did not. So
# `var t: Str = mk();` was accepted while `t = mk();` — the same call, the same binding —
# warned. Two paths disagreeing about one expression. Filed from abaco.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
struct Str { p: i64; n: i64; }
fn mk(): Str { var s: Str = 0; return s; }
fn main(): i64 {
    var t: Str = mk();
    t = mk();
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -ne 0 ]; then echo "  FAIL axis 5: 't = mk()' warned $n time(s) — the assignment path still ignores the callee's declared return type"; fail=1
else echo "  ok axis 5: assigning a call whose declared return is a struct does not warn"; fi

# --- axis 6 (ANTI-VACUOUS for axis 5): a genuine non-pointer assignment MUST still warn ---
# Axis 5 asserts an absence; without this, suppressing the warning entirely would pass it.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
struct Str { p: i64; n: i64; }
fn main(): i64 {
    var p: Str = 0;
    p = 7;
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -lt 1 ]; then echo "  FAIL axis 6 (anti-vacuous): 'p = 7' on a struct-typed local did NOT warn — the check was suppressed, not fixed"; fail=1
else echo "  ok axis 6: a genuine non-pointer assignment still warns"; fi

# --- axis 7 (v6.5.29): `&x` IS a pointer — the one expression that cannot be a non-pointer ---
# The address-of branch of parse_expr never called SPSC, so `var p: *i64 = &nodes;` — the
# canonical idiom — warned. Found by MEASURING the warning's blast radius across programs/
# after the .28 fix, not by a filing: 9 warnings, of which these were the only ones with no
# defensible reading (the rest assign an `i64`-DECLARED value to a pointer, where the warning
# is type-accurate whatever one thinks of the ergonomics).
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
var nodes[80];
fn main(): i64 {
    var p: *i64 = &nodes;
    var q: *i64 = &nodes + 16;
    var loc = 7;
    var r: *i64 = &loc;
    store64(p, 1);
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -ne 0 ]; then echo "  FAIL axis 7: '&x' assigned to a *i64 warned $n time(s) — address-of still reports no pointer scale"; fail=1
else echo "  ok axis 7: &global, &global+n and &local are all recognised as pointers"; fi

# --- axis 8 (ANTI-VACUOUS for axis 7): scale 1, not 8 — the arithmetic must not re-scale ---
# EPTR_SCALE multiplies the addend by the scale, so any value above 1 silently re-scales every
# existing `&x + n` site. This asserts the ARITHMETIC, not the warning: bytes, not slots.
# ⚠ Must exercise the ADDRESS-OF expression itself, not a `*i64`-declared local: a local
# declared `*i64` carries its own DECLARED scale of 8, so `p + 3` is slot arithmetic by
# design and says nothing about what `&buf` reports. (First draft of this axis made exactly
# that conflation and failed against correct code.)
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
var buf[64];
fn main(): i64 {
    store8(&buf + 3, 42);
    var v = load8(&buf + 3);
    return v;
}
var ec = main();
syscall(60, ec);
EOF
build
chmod +x "$O" 2>/dev/null || true
# ⚠ `set -e` is on: a bare `"$O"; rc=$?` ABORTS the gate the moment the fixture exits 42 —
# which is the PASSING case here. The `|| rc=$?` form is the only one that survives it.
rc=0
"$O" >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 42 ]; then echo "  FAIL axis 8 (anti-vacuous): '&buf + 3' addressed byte $rc, not byte 3 — the pointer scale is re-scaling byte arithmetic"; fail=1
else echo "  ok axis 8: &x + n stays BYTE arithmetic (scale 1)"; fi

# --- axis 9 (6.6.17): a `name: *T` field and a `fn f(): *T` result ARE pointers ---
# Both positions were parse errors before 6.6.17. Their value carries T's step as its pointer
# scale, so binding it to a `*T` local must not warn; axes 4 and 6 keep the warning reachable.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct H { p: *Pt; n; }
var arr[4];
fn first(h: *H): *Pt { return h.p; }
fn main(): i64 {
    var h: H;
    h.p = &arr; h.n = 0;
    var a: *Pt = h.p;
    var b: *Pt = first(&h);
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
crc=0
"$CC" < "$T" > "$O" 2>"$E" || crc=$?
n=$(warns)
if [ "$crc" -ne 0 ]; then echo "  FAIL axis 9: a *T field / a *T return did not compile (rc $crc)"; fail=1
elif [ "$n" -ne 0 ]; then echo "  FAIL axis 9: a *T field / a *T return bound to a *T local warned $n time(s)"; fail=1
else echo "  ok axis 9: a *T field and a *T return are pointers"; fi

# --- axis 10 (6.6.17): a `*T` PARAMETER, a CAPTURED `*T` local and `G += n` on a `*T` global are
# pointers — each loaded (or left) with scale 0 before 6.6.17, so these copies warned falsely.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
var arr[8];
var G: *i32 = 0;
fn f(p: *i32): i64 {
    var q: *i32 = p;
    var c: *i16 = &arr;
    var k = || { var r: *i16 = c; return r; };
    G = &arr;
    G += 1;
    return callptr(k) + q;
}
var ec = 0;
syscall(60, ec);
EOF
crc=0
"$CC" < "$T" > "$O" 2>"$E" || crc=$?
n=$(warns)
if [ "$crc" -ne 0 ]; then echo "  FAIL axis 10: the fixture did not compile (rc $crc)"; fail=1
elif [ "$n" -ne 0 ]; then echo "  FAIL axis 10: a *T param / a captured *T / G += n warned $n time(s)"; fail=1
else echo "  ok axis 10: a *T param, a captured *T and G += n are pointers"; fi

# --- axis 11 (6.6.17): a difference of pointers with different element sizes is refused by name.
# It used to scale the right pointer by the left one's step and compile a meaningless number.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
var arr[8];
fn f(p: *i64, b: *u8): i64 { return p - b; }
var ec = 0;
syscall(60, ec);
EOF
crc=0
"$CC" < "$T" > "$O" 2>"$E" || crc=$?
if [ "$crc" -ne 0 ] && grep -q "pointer difference of pointers with different element sizes" "$E"; then
    echo "  ok axis 11: *i64 - *u8 is refused by name"
else echo "  FAIL axis 11: *i64 - *u8 was not refused by name (rc $crc)"; fail=1; fi

# --- axis 12 (6.7.13, the user's decision D18 (a), 2026-10-15; issues/archived/2026-10-12-typed-pointer-non-pointer-warning-gaps.md) ---
# The warning at EVERY `*T` site, the literal 0 exempt. It was missing for a declaration-zone `*T` global (replayed
# by EMIT_GVAR_INITS, or baked when it folds) and for an assignment to a `*T` local or `p: *T` parameter of a scalar T;
# and `= 0` / `p = 0` (a null pointer) warned where the warning fired at all. P1-P3: the filed commands verbatim
# (0 / 0 / 1 before, 1 / 1 / 1 now); the issue's whole table, each row its warning count.
# MUTATION LEDGER (2026-10-16, a scratch copy of src/ with the one edit, this gate run as CYCC=<mutant>):
#   the fix reverted (the lane's previous tip, 98801809)  -> RED 21: P1 P2, z_i64 z_u8 z_pt z_add z_3 z_re3 z_neg,
#       z_after0 t_asg0 f_decl0 f_asg f_asg8 f_asg32 f_asg3 f_par f_pt0 f_g0 f_ld z_8b
#   M-TP1 `_tp_null` answering 0 (no null exemption)      -> RED 12: axis 10 (`var G: *i32 = 0;`), z_0 z_re0 z_re3 (its
#       superseded `= 0` replayed) z_after0 t_asg0 f_decl0 f_asg0 f_par0 f_pt0 f_g f_g0 (the zone `= 0`)
#   M-TP2 the local arm without the typed-pointer bit     -> RED 7: P2, f_asg f_asg8 f_asg32 f_asg3 f_par f_ld
#   M-TP3 `_tp_warn_gv` answering 0 (the zone replay)     -> RED 6: P1, z_i64 z_u8 z_pt z_add z_8b
#   M-TP4 PARSE_GVAR_REG without `_tp_warn_baked`         -> RED 3: z_3 z_re3 z_neg
#   M-TP5 `_tp_warn_gv` without its refused-line tests     -> RED 2: z_ref z_ref3
tprow() {   # <name> <want> <what> <source, printf %b>
    printf '%b' "$4" > "$T"
    build
    n=$(warns)
    if [ "$n" -ne "$2" ]; then echo "  FAIL axis 12 $1: $3 — $n warning(s), want $2"; fail=1
    else echo "  ok axis 12 $1: $3 — $n"; fi
}
tprow P1 1 "the filed command 1, verbatim: zone var p: *i64 = x; (0 before)" 'var x = 3;\nvar p: *i64 = x;\nsyscall(60, 0);\n'
tprow P2 1 "the filed command 2, verbatim: fn p = x; into a *i64 local (0 before)" 'fn f(): i64 {\n    var x = 3;\n    var p: *i64 = &x;\n    p = x;\n    return 0;\n}\nsyscall(60, f());\n'
tprow P3 1 "the filed command 3, verbatim: fn var q: *i64 = x; (the control)" 'fn f(): i64 {\n    var x = 3;\n    var q: *i64 = x;\n    return 0;\n}\nsyscall(60, f());\n'
tprow z_i64 1 "zone: var x = 3; var p: *i64 = x; (0 before)" "var x = 3;\nvar p: *i64 = x;\nsyscall(60, 0);\n"
tprow z_u8 1 "zone: var p: *u8 = x; (0 before)" "var x = 3;\nvar p: *u8 = x;\nsyscall(60, 0);\n"
tprow z_pt 1 "zone: var p: *Pt = x; (0 before)" "struct Pt { a; b; }\nvar x = 3;\nvar p: *Pt = x;\nsyscall(60, 0);\n"
tprow z_add 1 "zone: var p: *i64 = x + 1; (0 before)" "var x = 3;\nvar p: *i64 = x + 1;\nsyscall(60, 0);\n"
tprow z_3 1 "zone: var p: *i64 = 3; baked into the image (0 before)" "var p: *i64 = 3;\nsyscall(60, 0);\n"
tprow z_0 0 "zone: var p: *i64 = 0; the null literal (D18)" "var p: *i64 = 0;\nsyscall(60, 0);\n"
tprow z_amp 0 "zone: var p: *i64 = &x; a pointer" "var x = 3;\nvar p: *i64 = &x;\nsyscall(60, 0);\n"
tprow z_gp 0 "zone: var p: *i64 = gp(); a : *i64 call" "var Y = 4;\nfn gp(): *i64 { return &Y; }\nvar p: *i64 = gp();\nsyscall(60, 0);\n"
tprow z_re0 0 "zone: a redeclaration = 0 (baked) is the null literal" "var p: *i64 = 0;\nvar p: *i64 = 0;\nsyscall(60, 0);\n"
tprow z_re3 1 "zone: a redeclaration = 3 (baked) warns" "var p: *i64 = 0;\nvar p: *i64 = 3;\nsyscall(60, 0);\n"
tprow z_neg 1 "zone: var p: *i64 = 0 - 1; folds, not the literal 0" "var p: *i64 = 0 - 1;\nsyscall(60, 0);\n"
tprow z_after 1 "top level after a statement: var p: *i64 = x; (the control)" "var x = 3;\nsyscall(39);\nvar p: *i64 = x;\nsyscall(60, 0);\n"
tprow z_after0 0 "top level after a statement: var p: *i64 = 0; (D18: 1 before)" "syscall(39);\nvar p: *i64 = 0;\nsyscall(60, 0);\n"
tprow t_asg 1 "top level: p = x; (the control)" "var x = 3;\nvar p: *i64 = &x;\np = x;\nsyscall(60, 0);\n"
tprow t_asg0 0 "top level: p = 0; (D18: 1 before)" "var x = 3;\nvar p: *i64 = &x;\np = 0;\nsyscall(60, 0);\n"
tprow f_decl 1 "fn: var q: *i64 = x; (the control)" "fn f(): i64 {\n    var x = 3;\n    var q: *i64 = x;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_decl1 2 "fn: var q: *i64 = x + 1; var r: *i64 = 3; (2)" "fn f(): i64 {\n    var x = 3;\n    var q: *i64 = x + 1;\n    var r: *i64 = 3;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_decl0 0 "fn: var q: *i64 = 0; (D18: 1 before)" "fn f(): i64 {\n    var q: *i64 = 0;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_asg 1 "fn: p = x; into a *i64 local (0 before)" "fn f(): i64 {\n    var x = 3;\n    var p: *i64 = &x;\n    p = x;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_asg8 1 "fn: p = x; into a *u8 local (0 before)" "fn f(): i64 {\n    var x = 3;\n    var p: *u8 = &x;\n    p = x;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_asg32 1 "fn: p = x; into a *i32 local (0 before)" "fn f(): i64 {\n    var x = 3;\n    var p: *i32 = &x;\n    p = x;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_asg3 1 "fn: p = 3; into a *i64 local (0 before)" "fn f(): i64 {\n    var x = 3;\n    var p: *i64 = &x;\n    p = 3;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_asg0 0 "fn: p = 0; into a *i64 local (D18)" "fn f(): i64 {\n    var x = 3;\n    var p: *i64 = &x;\n    p = 0;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_par 1 "fn: p = x; into a p: *i64 parameter (0 before)" "fn f(p: *i64): i64 {\n    var x = 3;\n    p = x;\n    return 0;\n}\nsyscall(60, f(0));\n"
tprow f_par0 0 "fn: p = 0; into a p: *i64 parameter (D18)" "fn f(p: *i64): i64 {\n    p = 0;\n    return 0;\n}\nsyscall(60, f(0));\n"
tprow f_pt 1 "fn: p = x; into a *Pt local (the control)" "struct Pt { a; b; }\nfn f(): i64 {\n    var x = 3;\n    var q: Pt = Pt { 1, 2 };\n    var p: *Pt = &q;\n    p = x;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_pt0 0 "fn: p = 0; into a *Pt local (D18: 1 before)" "struct Pt { a; b; }\nfn f(): i64 {\n    var q: Pt = Pt { 1, 2 };\n    var p: *Pt = &q;\n    p = 0;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_g 1 "fn: G = x; into a *i64 global (the control)" "var G: *i64 = 0;\nfn f(): i64 {\n    var x = 3;\n    G = x;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_g0 0 "fn: G = 0; into a *i64 global (D18: 1 before)" "var Y = 1;\nvar G: *i64 = &Y;\nfn f(): i64 {\n    G = 0;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_amp 0 "fn: p = &y; a pointer" "fn f(): i64 {\n    var x = 3;\n    var y = 4;\n    var p: *i64 = &x;\n    p = &y;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_gp 0 "fn: p = gp(); a : *i64 call" "var Y = 4;\nfn gp(): *i64 { return &Y; }\nfn f(): i64 {\n    var x = 3;\n    var p: *i64 = &x;\n    p = gp();\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_cmp 0 "fn: p += 1; p = p + 1; p -= 1; on a *i64 local" "fn f(): i64 {\n    var x = 3;\n    var p: *i64 = &x;\n    p += 1;\n    p = p + 1;\n    p -= 1;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_cmp8 0 "fn: p += 1; p = p + 2; var q: *u8 = p + 1; on a *u8 local" "fn f(): i64 {\n    var b = 3;\n    var p: *u8 = &b;\n    p += 1;\n    p = p + 2;\n    var q: *u8 = p + 1;\n    return 0;\n}\nsyscall(60, f());\n"
tprow f_cmpp 0 "fn: p += 1; p = p + 2; on a p: *u8 parameter" "fn f(p: *u8): i64 {\n    p += 1;\n    p = p + 2;\n    return 0;\n}\nsyscall(60, f(0));\n"
tprow f_ld 1 "fn: p = load64(&x); a word into a *i64 local (0 before)" "fn f(): i64 {\n    var x = 3;\n    var p: *i64 = &x;\n    p = load64(&x);\n    return 0;\n}\nsyscall(60, f());\n"
tprow z_ref 0 "zone: var X: *P2 = mkp(); refused by D24, no warning beside the refusal" 'struct P2 { a; b; }\nfn mkp(): P2 { var r: P2 = P2 { 1, 2 }; return r; }\nvar X: *P2 = mkp();\nsyscall(60, 0);\n'
tprow z_ref3 0 "zone: var X: *P3 = mk3(); refused (no frame), no warning beside the refusal" 'struct P3 { a; b; c; }\nfn mk3(): P3 { var r: P3 = P3 { 1, 2, 3 }; return r; }\nvar X: *P3 = mk3();\nsyscall(60, 0);\n'
tprow z_8b 1 "zone: var X: *P1 = mk1(); an 8 B struct's word warns, as in a fn (D14)" 'struct P1 { a; }\nfn mk1(): P1 { var r: P1 = P1 { 1 }; return r; }\nvar X: *P1 = mk1();\nsyscall(60, 0);\n'

# --- axis 13 (6.7.14, the user's decision D26 (a), 2026-10-16; issues/archived/2026-10-16-known-callee-pointer-or-f64-result-untyped.md) ---
# A known `&f` callee's `: *T` result carries the pointer type, as the direct call `gp()` does: `var w: *P2 = fncall0(&gp);`
# warned "assigning non-pointer to typed pointer" (the result was an untyped word) where `var x: *P2 = gp();` is quiet.
# A callee held in a variable stays a word and still warns (K4). The step half (`fncall0(&gp) + 1` steps one P2) is
# tests/tcyr/crossos/fncall_scalar_result.tcyr's.
#   the fix reverted (the lane's D27 commit)              -> RED 5: K0 K1 K2 K3 K5 (1 warning each)
#   `_call_scale_fix` without its `_icall_ps_beg` line     -> RED 5: K0 K1 K2 K3 K5 (the factor's fix reset the step)
KP='struct P2 { a; b; }\nvar G: P2 = P2 { 11, 22 };\nvar GI = 5;\nfn gp(): *P2 { return &G; }\nfn gi(): *i64 { return &GI; }\n'
tprow K0 0 "the filed repro 1, verbatim: var w: *P2 = fncall0(&gp); (1 before)" "$(cat docs/development/issues/repros/2026-10-16-known-callee-pointer-or-f64-result-untyped.cyr)"
tprow K1 0 "fn: var w: *P2 = callptr(&gp); (1 before)" "include \"lib/fnptr.cyr\"\n${KP}fn f(): i64 {\n    var w: *P2 = callptr(&gp);\n    return w.b;\n}\nsyscall(60, f());\n"
tprow K2 0 "fn: w = fncall0(&gp); into a *P2 local (1 before)" "include \"lib/fnptr.cyr\"\n${KP}fn f(): i64 {\n    var w: *P2 = &G;\n    w = fncall0(&gp);\n    return w.b;\n}\nsyscall(60, f());\n"
tprow K3 0 "zone: var W: *P2 = fncall0(&gp); (1 before)" "include \"lib/fnptr.cyr\"\n${KP}var W: *P2 = fncall0(&gp);\nsyscall(60, W.b);\n"
tprow K4 1 "fn: a callee held in a variable is a word (the control, D31)" "include \"lib/fnptr.cyr\"\n${KP}fn f(): i64 {\n    var fp = &gp;\n    var w: *P2 = fncall0(fp);\n    return w.b;\n}\nsyscall(60, f());\n"
tprow K5 0 "fn: var q: *i64 = fncall0(&gi); (1 before)" "include \"lib/fnptr.cyr\"\n${KP}fn f(): i64 {\n    var q: *i64 = fncall0(&gi);\n    return *q;\n}\nsyscall(60, f());\n"

# --- axis 14 (6.7.14; issues/archived/2026-10-16-typed-pointer-warning-string-literal-and-address-of-subscript.md) ---
# A STRING LITERAL alone into a BYTE pointer (`*u8` / `*i8`) is a pointer: `var s: *u8 = "abc";`, `t = "xyz";` and the
# zone's `var p: *u8 = "abc";` warned (D18 (a) carried the warning to the assignment and the zone), on valid code that
# runs right (the C-string idiom). And a `*T` destination whose value was refused as `&a[i]` warned beside the refusal.
# `_tp_exempt` (the null literal and the byte pointer's string) and `_tp_refd_at` (the `&a[i]` refusal's token; the value
# spanning it is not warned about). 6.7.14 left any other `*T` from a string literal warning (SK1-SK3).
#   the bite reverted (the D28 commit, b646484c)          -> RED 9: S0 S0z S1 S2 (warned) S0a A2 A3 A4 A5 (a warning beside)
#   `_tp_exempt` without its string arm                   -> RED 4: S0 S0z S1 S2
#   `_sub_post` without the `_tp_refd_at` mark            -> RED 5: S0a A2 A3 A4 A5
#   `_tp_warn_l` passing no element kind                  -> RED 2: S0 (`t = "xyz";`) S1 (`p = "xy";`, a parameter)
#     (retired by 6.7.15's D59: no element kind is read, `_tp_warn_l` is gone)
# (A1 A6 A7, a declaration, were quieted by the D28 commit's `_tp_warn_decl` / the zone's `_scv_err`.)
# 6.7.15 (6.7.14's D53 applied as worded — the user's decision D59, 2026-10-18;
# issues/2026-10-17-6714-behaviour-changes-beyond-the-decisions-text.md item 18): NO string literal warns into ANY `*T`,
# as the literal 0 never does — SK1-SK3 (`*i64`, the zone's `*i64`, a one-byte struct's `*B1`) and SK4 (`*f64`, `*i32`,
# a `*P2`) are quiet; a value that is no literal (SK5) still warns. Warning text only: the binaries are unchanged.
#   `_tp_exempt` with 6.7.14's `_ek_w(ed) != 1` test (the lane before D59) -> RED 4: SK1 (2) SK2 (1) SK3 (2) SK4 (3)
tpx() {   # <name> <want warnings> <want errors> <want exit or -> <what> <source, printf %b>
    printf '%b' "$6" > "$T"
    build
    n=$(warns)
    ne=$(grep -c '^error' "$E" || true)
    x=-
    if [ "$4" != - ] && [ -s "$O" ]; then chmod +x "$O"; x=0; "$O" > /dev/null 2>&1 || x=$?; fi
    if [ "$n" -ne "$2" ] || [ "$ne" -ne "$3" ] || [ "$x" != "$4" ]; then
        echo "  FAIL axis 14 $1: $5 — $n warning(s) / $ne error(s) / exit $x, want $2 / $3 / $4"; fail=1
    else echo "  ok axis 14 $1: $5 — $n / $ne / exit $x"; fi
}
RS=docs/development/issues/repros/2026-10-16-typed-pointer-warning-string-literal-and-address-of-subscript
[ -f "$RS.cyr" ] && [ -f "$RS-zone.cyr" ] && [ -f "$RS-address-of-subscript.cyr" ] || { echo "FAIL: typed_pointer_warn_sign: $RS*.cyr missing"; exit 1; }
tpx S0 0 0 218 "the filed repro 1 verbatim: var s: *u8 = \"abc\"; t = \"xyz\"; (2 warnings before)" "$(cat "$RS.cyr")"
tpx S0z 0 0 98 "the filed zone repro verbatim: var p: *u8 = \"abc\"; (1 warning before)" "$(cat "$RS-zone.cyr")"
tpx S0a 0 1 - "the filed &a[i] repro verbatim: p = &a[1]; refused once (a warning beside it before)" "$(cat "$RS-address-of-subscript.cyr")"
tpx S1 0 0 30 "fn: var s: *i8 = \"abc\"; p = \"xy\"; into a p: *u8 parameter; G = \"q\"; into a *u8 global" 'fn f(p: *u8): i64 {\n    var s: *i8 = "abc";\n    p = "xy";\n    return load8(s) + load8(p);\n}\nvar G: *u8 = 0;\nfn g(): i64 { G = "q"; return load8(G); }\nsyscall(60, f(0) + g() - 300);\n'
tpx S2 0 0 241 "top level after a statement: var q: *u8 = \"x\"; r = \"yz\";" 'syscall(39);\nvar q: *u8 = "x";\nvar r: *u8 = 0;\nr = "yz";\nsyscall(60, load8(q) + load8(r));\n'
tpx SK1 0 0 0 "D59: a *i64 from a string literal is quiet (a declaration, an assignment; 2 warnings through 6.7.14)" 'fn main(): i64 {\n    var s: *i64 = "abc";\n    var t: *i64 = 0;\n    t = "xyz";\n    return 0;\n}\nsyscall(60, main());\n'
tpx SK2 0 0 0 "D59: the zone's var p: *i64 = \"abc\"; is quiet (1 through 6.7.14)" 'var p: *i64 = "abc";\nsyscall(60, 0);\n'
tpx SK3 0 0 0 "D59: a *B1 (a 1-byte struct, step 1) from a string literal is quiet (zone, fn; 2 through 6.7.14)" 'struct B1 { a: u8; }\nvar p: *B1 = "abc";\nfn f(): i64 { var q: *B1 = "abc"; return 0; }\nsyscall(60, f());\n'
tpx SK4 0 0 90 "D59: *f64, *i32 and a *P2 from a string literal are quiet, and read the literal's bytes (3 through 6.7.14)" 'struct P2 { a; b; }\nvar G: *P2 = 0;\nfn main(): i64 {\n    var f: *f64 = "abcdefgh";\n    var i: *i32 = "abcd";\n    G = "hijklmnopqrstuvw";\n    return load8(f) + load8(i) - load8(G);\n}\nsyscall(60, main());\n'
tpx SK5 2 0 0 "control: a value that is no literal still warns into a *i64 (a declaration, an assignment)" 'fn main(): i64 {\n    var n = 5;\n    var s: *i64 = n;\n    s = 7;\n    return 0;\n}\nsyscall(60, main());\n'
tpx A1 0 1 - "fn: var q: *i64 = &a[0]; refused once" 'fn main(): i64 {\n    var a: i64[4];\n    var q: *i64 = &a[0];\n    return 0;\n}\nsyscall(60, main());\n'
tpx A2 0 1 - "fn: G = &a[1]; into a *i64 global, refused once" 'var G: *i64 = 0;\nfn main(): i64 {\n    var a: i64[4];\n    G = &a[1];\n    return 0;\n}\nsyscall(60, main());\n'
tpx A3 0 1 - "top level: P = &A[1]; into a *i64 global, refused once" 'var A: i64[4];\nvar P: *i64 = 0;\nsyscall(39);\nP = &A[1];\nsyscall(60, 0);\n'
tpx A4 0 1 - "fn: pp = &ps[1]; into a *Pt local, refused once" 'struct Pt { a; b; }\nfn main(): i64 {\n    var ps: Pt[4];\n    var pp: *Pt = &ps;\n    pp = &ps[1];\n    return 0;\n}\nsyscall(60, main());\n'
tpx A5 0 1 - "fn: p = &b[1]; with b a *i64, refused once" 'fn main(): i64 {\n    var a: i64[4];\n    var b: *i64 = &a;\n    var p: *i64 = &a;\n    p = &b[1];\n    return 0;\n}\nsyscall(60, main());\n'
tpx A6 0 1 - "zone: var P: *i64 = &A[1]; refused once" 'var A: i64[4];\nvar P: *i64 = &A[1];\nsyscall(60, 0);\n'
tpx A7 0 1 - "top level after a statement: var P: *i64 = &A[1]; refused once" 'var A: i64[4];\nsyscall(39);\nvar P: *i64 = &A[1];\nsyscall(60, 0);\n'

# --- axis 15 (6.7.15; issues/2026-10-17-string-literal-expression-into-byte-pointer-still-warns.md) ---
# A string literal's address plus or minus ONE integer operand (an integer / char literal or a single name), and the
# literal under parentheses that wrap it whole, are its address too: `var s: *u8 = "abc" + 1;` and `var t: *u8 =
# ("xyz");` warned (6.7.14 exempted the literal only alone before the `;`). `_tp_str_exempt` (parse_decl.cyr), at every
# site `_tp_exempt` serves: a declaration in a fn, after the first statement and in the zone, an assignment. Any other
# expression is judged as before (SLK1, SLK2). Warning text only: no binary changes (each row's exit is the one before).
#   `_tp_exempt` without `_tp_str_exempt` (the literal alone, the lane before the bite) -> RED 6: SL0 (2) SL1 (6)
#                                                                 SL2 (4) SL3 (3) SL4 (1) SL5 (1)
tpx SL0 0 0 218 "the filed repro verbatim: \"abc\" + 1 and (\"xyz\") into a *u8 (2 warnings before)" 'include "lib/syscalls.cyr"\nfn main(): i64 {\n    var s: *u8 = "abc" + 1;\n    var t: *u8 = ("xyz");\n    return load8(s) + load8(t);\n}\nsyscall(60, main());\n'
tpx SL1 0 0 111 "fn: \"abc\" + 1, (\"xyz\"), ((\"x\")), \"abc\" - 0, (\"abc\" + 1), (\"abc\") + n are quiet" 'fn main(): i64 {\n    var n = 1;\n    var a: *u8 = "abc" + 1;\n    var b: *u8 = ("xyz");\n    var c: *u8 = (("x"));\n    var d: *u8 = "abc" - 0;\n    var e: *u8 = ("abc" + 1);\n    var f: *u8 = ("abc") + n;\n    return load8(a) + load8(b) + load8(c) + load8(d) + load8(e) + load8(f) - 520;\n}\nsyscall(60, main());\n'
tpx SL2 0 0 135 "assignments: t = (\"xyz\"); t = \"abc\" + n; into a *u8 local, a parameter, a *u8 global" 'var G: *u8 = 0;\nfn f(p: *u8): i64 {\n    var n = 2;\n    var t: *u8 = 0;\n    t = ("xyz");\n    var r = load8(t);\n    t = "abc" + n;\n    p = (("pq")) + 1;\n    G = ("g") - 0;\n    return r + load8(t) + load8(p) + load8(G) - 300;\n}\nsyscall(60, f(0));\n'
tpx SL3 0 0 192 "zone: var P: *u8 = (\"abc\"); var P2: *u8 = \"abc\" + 1; var Q: *i64 = ((\"abcdefgh\")) - 0;" 'var P: *u8 = ("abc");\nvar P2: *u8 = "abc" + 1;\nvar Q: *i64 = (("abcdefgh")) - 0;\nsyscall(60, load8(P) + load8(P2) + load8(Q) - 100);\n'
tpx SL4 0 0 120 "after a first statement: var q: *u8 = (\"x\") + 0;" 'syscall(39);\nvar q: *u8 = ("x") + 0;\nsyscall(60, load8(q));\n'
tpx SL5 0 0 98 "a *i64 from (\"abc\") + 1 (D59 and the shape together)" 'fn main(): i64 {\n    var s: *i64 = ("abc") + 1;\n    return load8(s);\n}\nsyscall(60, main());\n'
tpx SLK1 1 0 - "control: var p: *u8 = \"abc\" + x * 2; still warns (not one operand)" 'fn main(): i64 {\n    var x = 1;\n    var p: *u8 = "abc" + x * 2;\n    return 0;\n}\nsyscall(60, main());\n'
tpx SLK2 1 0 - "control: a char literal plus 0 is no string: var p: *u8 = 'a' + 0; still warns" 'fn main(): i64 {\n    var p: *u8 = '"'"'a'"'"' + 0;\n    return 0;\n}\nsyscall(60, main());\n'

[ "$fail" -eq 0 ] || { echo "FAIL: typed-pointer-warn-sign"; exit 1; }
echo "PASS: typed-pointer-warn-sign — warns on typed pointers only, not on width/float-annotated locals; at every *T site (the declaration zone, a *T local / parameter of a scalar T), the literal 0 exempt (D18), a string literal into a byte pointer exempt and a refused &a[i] not warned beside (6.7.14); a string literal into any *T exempt (D59, 6.7.15), plus or minus one integer operand and under parentheses (6.7.15)"
