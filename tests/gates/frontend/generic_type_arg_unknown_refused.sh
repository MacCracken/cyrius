#!/bin/sh
# generic_type_arg_unknown_refused.sh — 6.6.8 bite 1b: an explicit type argument that names no
# type (`id<Nope>(4)`) is refused by name, and a forwarded type parameter (`inner<T>(p)` inside a
# generic) resolves to its binding.
#
# ⛔ WHY. `_parse_one_type_arg` classified a type-arg as a TYPE NAME only. A name that was none
# came back 0 — which the instantiation machinery reads as "unbound", i.e. the BASE emission — so
#   * `id<Nope>(4)` compiled clean and ran the i64 base (measured: exit 5), and
#   * `inner<T>(p)` inside `fn outer<T>` hit the same 0: a callee that uses T as a struct became
#     the `rax = 0` dead stub (`outer<Pt>(p)` returned 2, want 16), or — for a body small enough
#     to inline — a compile error raised from outer's own base emission, which nothing calls.
# A bound type parameter now resolves to its binding, and 0 is never a type. The runtime values
# are pinned cross-host by tests/tcyr/crossos/generic_forward_tparam.tcyr; this gate pins the
# compile-time halves the .tcyr runner cannot (a refusal, and exit codes of tiny programs).
#
#   A  id<Nope>(4)                                 -> refused, message names 'Nope'
#   B  a type-arg that is a VARIABLE, not a type    -> refused, message names it
#   C  outer<Pt>(p) forwarding to a looping inner<T> -> 16 (was 2)
#   D  the same with an inlinable inner<T>           -> 16 (was a compile error)
#   E  control: id<i64>(4) / id<i32>(4) / id<Pt>     -> build and run
#   F  id<Color>(4), Color a declared enum            -> refused, message says it is an enum
#   G  id<u64> / <u8> / <bool> / <ptr> / <f32>        -> refused by name (not in the type-arg
#      vocabulary, which is the return-type vocabulary: a struct, i8/i16/i32/i64, f64, or a bound
#      type parameter — an alias would silently pick a width; these all used to run the i64 base)
#
# ⛔ 6.6.10 (bite 7) — A GENERIC THAT USES T AS A STRUCT HAS NO SCALAR INSTANCE. Its base is the
# `rax = 0` dead stub, and whether it was one was known only while that base was being emitted —
# so every row below BUILT on 6.6.9 and returned 0 (or failed with a misleading "no struct type in
# scope for 'p'"). Each is now refused by name, 'g' (or the forwarding 'outer'):
#   H  g<i64>(5), g(5), `return g<i64>(5)`, `return g(5)`, g<i32>(5), and an inlinable body
#   I  TRANSITIVE: outer<T> forwarding `g<T>(p)` / `g(p)`, called outer<i64>(5) / outer(5) —
#      and with the three fns defined in REVERSE order (the facts are recorded in pass 1)
#   J  `&g` (the address is the stub's)
#   K  two struct type args inferred, or a struct beside a scalar: refused by name 6.6.10 → 6.7.0
#      (it was 0 silently before). ⭐ 6.7.1 (C3) LIFTED the refusal — these build and RUN now,
#      with the right value; the full matrix is tests/tcyr/crossos/generic_two_param_struct.tcyr
#   L  a stub generic returning a struct, received as `var r: Box<i64> = mkb(5)` (its own call path)
#   N  a bad type argument in a `var x = f<..>(..)` receive is reported ONCE (the receive now
#      resolves the instance ahead of the call's own parse, and must not report it a second time)
#   K  (review) the same on every path that emits its OWN call — `var r = mk3(p, q)`,
#      `var r = mk2(p, 1)`, a struct argument, `r = mk2(p, 6)`, and the explicit `mk2<Pt, i64>(p, ..)`
#      receive and assignment: `_gen_resolve_call` swallowed the failed instantiation and the BASE
#      ran with T = i64, silently (6.6.10 refused them once each). Since 6.7.1 each RUNS with the
#      right value; receiving the `Box<Pt>` result into a plain `Box` is refused as a type mismatch,
#      once, as the one-parameter `mk1(p)` is.
#   O  (review) a `pp: *Pt` parameter binds T to i64 (it is a pointer), not to the pointee:
#      `g(pp)` is refused like `g(5)`, `f(pp) - pp` runs the base (exit 1)
#   P  (review) at top level, `w1s(mkw(gp))` — a register-pair INSTANCE result as a struct
#      argument — is refused by name (the class was read from the 8 B base: SIGSEGV)
#   M  CONTROLS that must still build and run: a 20,000,001-deep scalar generic TAIL recursion
#      (exit 1; the prototype that diverted every generic off the tail path made it rc 139), a
#      stub generic nobody calls with a scalar (exit 3), a vector local as an inferred argument
#      (exit 10; its descriptor read as "struct 2093"), and the struct call of every H/I shape
#      (exit 12 / 14)
#
# Mutations: drop the `_tp_resolve` consult in _type_arg_leaf -> C, D RED (refused as unknown
# `T`). Drop the refusal -> A, B, F, G RED (rc 0). Drop the `_is_enum_name` arm -> F RED
# (refused, but as an "unknown type"). (6.6.8's third mutation, "let _call_forwarded_base inline
# -> D RED", went GREEN at 6.6.10 and that fn was retired: outer's base is now a transitive stub
# whose body is skipped, so no replay of the inlinable inner<T> is left for it to suppress.)
# 6.6.10 (src/frontend/parse_fn.cyr; each run on a scratch tree, never the repo):
#   `_gen_call_head` never calls _refuse_gen_stub     -> H, I RED (rc 0, the stub's 0)
#   drop `_tc_generic_divert` from _tc_must_divert     -> H's `return g(5)` RED (rc 0)
#   _tc_generic_divert returns 1 for EVERY generic      -> M's tail recursion RED (rc 139)
#   `_gen_close` returns at once (no transitive half)   -> I RED (rc 0)
#   drop the `_gen_addr_check` call (parse_expr.cyr)    -> J RED (rc 0)
#   6.7.1: `_instantiate_generic_fn` refusing a struct beside a second type argument again (the
#   pre-6.7.1 `-3`) -> K RED (refused, rc 1)
#   drop the `_gen_own_call_check` in the asv_pair receive (parse_decl.cyr) -> L RED (rc 0)
#   drop the vector guard in _infer_conc_at_cursor      -> M's vector row RED
#   drop the `_targs_resolvable` early-out in _gen_resolve_call -> N RED (reported twice)
#   (review) `_is_ptr_param` / `_mark_ptr_param` inert -> O RED;
#   `_refuse_toplevel_pair_arg` on FINDFN -> P RED (BUILT)
# The runtime halves (inference on every path, signature types) are mutation-proven by
# tests/tcyr/crossos/generic_struct_inference.tcyr — its header lists them.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: generic_type_arg_unknown_refused: no compiler at $CC"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "SKIP: generic_type_arg_unknown_refused: mktemp -d failed"; exit 77; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
refused() { # <name> <ident> <what>
    build "$1"
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif ! grep -q "unknown type '$2' as a type argument" "$T/$1.err"; then
        bad "$3: refused, but not by name: $(grep '^error' "$T/$1.err" | head -1)"
    else ok "$3: refused, naming '$2'"; fi
}
exits() {   # <name> <want> <what>
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}

printf 'fn id<T>(v: T): i64 { return v + 1; }\nfn main(): i64 { return id<Nope>(4); }\nsyscall(60, main());\n' > "$T/a.cyr"
refused a Nope "A: an unknown type name as a type argument"
printf 'fn id<T>(v: T): i64 { return v + 1; }\nfn main(): i64 { var k = 3; return id<k>(4); }\nsyscall(60, main());\n' > "$T/b.cyr"
refused b k "B: a variable as a type argument"

printf 'struct Pt { x; y; }\nfn inner<T>(p: T): i64 { var s = 0; var i = 0; while (i < 4) { s = s + p.y; i = i + 1; } return s + p.x; }\nfn outer<T>(p: T): i64 { var r = inner<T>(p); return r + 2; }\nfn top(a): i64 { var p: Pt; p.x = a; p.y = 3; var r = outer<Pt>(p); return r; }\nsyscall(60, top(2));\n' > "$T/c.cyr"
exits c 16 "C: a forwarded T reaches the looping struct instance"
printf 'struct Pt { x; y; }\nfn inner<T>(p: T): i64 { return p.y * 4 + p.x; }\nfn outer<T>(p: T): i64 { var r = inner<T>(p); return r + 2; }\nfn top(a): i64 { var p: Pt; p.x = a; p.y = 3; return outer<Pt>(p); }\nsyscall(60, top(2));\n' > "$T/d.cyr"
exits d 16 "D: a forwarded T reaches the inlinable struct instance"

printf 'struct Pt { x; y; }\nfn id<T>(v: T): i64 { return v + 1; }\nfn gx<T>(p: T): i64 { return p.x; }\nfn main(): i64 { var p: Pt; p.x = 30; p.y = 1; return id<i64>(4) + id<i32>(4) + gx<Pt>(p); }\nsyscall(60, main());\n' > "$T/e.cyr"
exits e 40 "E: control: i64 / i32 / struct type arguments"

printf 'enum Color { RED; GREEN; }\nfn id<T>(v: T): i64 { return v + 1; }\nfn main(): i64 { return id<Color>(4); }\nsyscall(60, main());\n' > "$T/f.cyr"
build f
if [ "$rc" -eq 0 ]; then bad "F: an enum name as a type argument: BUILT (rc 0)"
elif ! grep -q "'Color' is an enum, not a type argument" "$T/f.err"; then
    bad "F: an enum name as a type argument: refused, but not as an enum: $(grep '^error' "$T/f.err" | head -1)"
else ok "F: an enum name as a type argument: refused as an enum"; fi

for w in u64 u8 bool ptr f32; do
    printf 'fn id<T>(v: T): i64 { return v + 1; }\nfn main(): i64 { return id<%s>(4); }\nsyscall(60, main());\n' "$w" > "$T/g_$w.cyr"
    refused "g_$w" "$w" "G: '$w' as a type argument"
done

# ── 6.6.10 (bite 7): a generic that uses T as a struct has no scalar instance ──────────────────
stubref() {   # <name> <fn-named> <what> — refused, naming <fn-named>, as having no i64 instance
    build "$1"
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif ! grep -q "generic '$2' has no i64 (or other scalar) instance" "$T/$1.err"; then
        bad "$3: refused, but not by name: $(grep '^error' "$T/$1.err" | head -1)"
    elif grep -q "no struct type in scope" "$T/$1.err"; then
        bad "$3: refused, but ALSO with the misleading 'no struct type in scope'"
    else ok "$3: refused, naming '$2'"; fi
}
GL='fn g<T>(p: T): i64 { var s = 0; var i = 0; while (i < 2) { s = s + p.y; i = i + 1; } return s + p.x; }'
GF='fn g<T>(p: T): i64 { return p.y * 2 + p.x; }'
PT='struct Pt { x; y; }'
MKP='var p: Pt; p.x = 2; p.y = 5;'
n=0
for call in 'g<i64>(5) + 7' 'g(5) + 7' 'g<i32>(5)'; do
    n=$((n + 1))
    printf '%s\n%s\nfn main(): i64 { return %s; }\nsyscall(60, main());\n' "$PT" "$GL" "$call" > "$T/h$n.cyr"
    stubref "h$n" g "H: $call"
done
for call in 'g<i64>(5)' 'g(5)'; do
    n=$((n + 1))
    printf '%s\n%s\nfn main(): i64 { return %s; }\nsyscall(60, main());\n' "$PT" "$GL" "$call" > "$T/h$n.cyr"
    stubref "h$n" g "H: return $call (tail position)"
done
for call in 'g<i64>(5) + 7' 'g(5) + 7'; do
    n=$((n + 1))
    printf '%s\n%s\nfn main(): i64 { return %s; }\nsyscall(60, main());\n' "$PT" "$GF" "$call" > "$T/h$n.cyr"
    stubref "h$n" g "H: $call, an inlinable body"
done

OE='fn outer<T>(p: T): i64 { var r = g<T>(p); return r + 2; }'
OI='fn outer<T>(p: T): i64 { var r = g(p); return r + 2; }'
printf '%s\n%s\n%s\nfn main(): i64 { return outer<i64>(5) + 7; }\nsyscall(60, main());\n' "$PT" "$GL" "$OE" > "$T/i1.cyr"
stubref i1 outer "I: outer<i64>(5), outer forwarding g<T>(p)"
printf '%s\n%s\n%s\nfn main(): i64 { return outer(5) + 7; }\nsyscall(60, main());\n' "$PT" "$GL" "$OI" > "$T/i2.cyr"
stubref i2 outer "I: outer(5), outer forwarding g(p) by inference"
printf '%s\nfn main(): i64 { return outer(5) + 7; }\n%s\n%s\nsyscall(60, main());\n' "$PT" "$OI" "$GL" > "$T/i3.cyr"
stubref i3 outer "I: the same, main -> outer -> g defined in REVERSE order"
printf '%s\nfn outer2<T>(p: T): i64 { return outer(p) + 1; }\n%s\n%s\nfn main(): i64 { return outer2(5); }\nsyscall(60, main());\n' "$PT" "$OI" "$GL" > "$T/i4.cyr"
stubref i4 outer2 "I: two levels of forwarding"

printf 'include "lib/fnptr.cyr"\n%s\n%s\nfn main(): i64 { %s var f = &g; return fncall1(f, &p) + 7; }\nsyscall(60, main());\n' "$PT" "$GL" "$MKP" > "$T/j.cyr"
stubref j g "J: &g"

build_refused_by() {   # <name> <grep> <what>
    build "$1"
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif ! grep -q "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    else ok "$3: refused"; fi
}
# K (6.7.1, C3) — a struct beside a second type argument RUNS (refused 6.6.10 → 6.7.0).
printf '%s\nstruct Q { a; b; c; }\nfn g2<T, U>(p: T, q: U): i64 { var s = 0; var i = 0; while (i < 1) { s = s + p.y + q.c; i = i + 1; } return s; }\nfn main(): i64 { %s var q: Q; q.a = 1; q.b = 1; q.c = 9; return g2(p, q); }\nsyscall(60, main());\n' "$PT" "$MKP" > "$T/k1.cyr"
exits k1 14 "K: g2(p, q), two struct type args inferred"
printf '%s\nfn g2<T, U>(p: T, n: U): i64 { var s = 0; var i = 0; while (i < n) { s = s + p.y; i = i + 1; } return s; }\nfn main(): i64 { %s return g2(p, 2); }\nsyscall(60, main());\n' "$PT" "$MKP" > "$T/k2.cyr"
exits k2 10 "K: g2(p, 2), a struct beside a scalar"

# ...and on every path that emits its OWN call. Receiving the `Box<Pt>` result into a plain `Box`
# (the base, a different layout) is a type mismatch, refused ONCE as `mk1(p)`'s is.
mismatch_once() {   # <name> <what>
    build "$1"
    k=$(grep -c "cannot copy 'mk[123]' into a variable of a different struct" "$T/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$2: BUILT (rc 0)"
    elif [ "$k" -ne 1 ]; then bad "$2: refused $k times as a mismatch, want 1: $(grep '^error' "$T/$1.err" | head -1)"
    else ok "$2: refused once, as a type mismatch"; fi
}
BX='struct Box<T> { v: T; n; }
struct Q { a; b; c; }
fn mk1<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 8; return b; }
fn mk2<T, U>(x: T, n: U): Box<T> { var b: Box<T>; b.v = x; b.n = n; return b; }
fn mk3<T, U>(x: T, y: U): Box<T> { var b: Box<T>; b.v = x; b.n = 7; return b; }
fn bsp(b: Box<Pt>): i64 { return b.n + b.v.y; }'
n=0
for row in '7|var q: Q; q.c = 1; var r = mk3(p, q); return r.n;' '1|var r = mk2(p, 1); return r.n;' \
        '9|return bsp(mk2(p, 4));' '8|var r: Box<Pt>; r = mk2(p, 6); return r.n + r.v.x;' \
        '1|var r: Box<Pt> = mk2<Pt, i64>(p, 1); return r.n;' '8|var r: Box<Pt>; r = mk2<Pt, i64>(p, 6); return r.n + r.v.x;' \
        'X|var r: Box; r = mk2(p, 6); return r.n;' 'X|var r: Box; r = mk2<Pt, i64>(p, 6); return r.n;' \
        'X|var r: Box; r = mk1(p); return r.n;'; do
    n=$((n + 1))
    want=${row%%|*}
    body=${row#*|}
    printf '%s\n%s\nfn main(): i64 { %s %s }\nsyscall(60, main());\n' "$PT" "$BX" "$MKP" "$body" > "$T/ko$n.cyr"
    if [ "$want" = X ]; then mismatch_once "ko$n" "K: $body"
    else exits "ko$n" "$want" "K: $body"; fi
done

printf '%s\nstruct Box<T> { v: T; n; }\nfn mkb<T>(p: T): Box<T> { var b: Box<T>; b.n = p.x; return b; }\nfn main(): i64 { var r: Box<i64> = mkb(5); return r.n; }\nsyscall(60, main());\n' "$PT" > "$T/l.cyr"
stubref l mkb "L: var r: Box<i64> = mkb(5), a stub generic on the struct-receive path"

# O (review) — a `pp: *Pt` parameter is a POINTER: it binds T to i64, like a `var q: *Pt` local,
# not to the pointee (the parameter loop skips the `*`, so its slot is typed `Pt`). A struct-using
# generic is then refused by name; an arithmetic one runs the base.
printf '%s\n%s\nfn h(pp: *Pt): i64 { return g(pp); }\nfn main(): i64 { %s return h(&p); }\nsyscall(60, main());\n' "$PT" "$GL" "$MKP" > "$T/o1.cyr"
stubref o1 g "O: g(pp) for a \`pp: *Pt\` parameter binds i64"
printf '%s\nfn f<T>(v: T): i64 { return v + 1; }\nfn h(pp: *Pt): i64 { return f(pp) - pp; }\nfn main(): i64 { %s return h(&p); }\nsyscall(60, main());\n' "$PT" "$MKP" > "$T/o2.cyr"
exits o2 1 "O: f(pp) - pp for a \`pp: *Pt\` parameter runs the i64 base"

# P (review) — at top level a register-pair INSTANCE result as a struct argument has no frame to
# land in: refused by name like a plain fn's (the class was read from the 8 B base: SIGSEGV).
printf '%s\nstruct W1<T> { v: T; }\nfn mkw<T>(x: T): W1<T> { var w: W1<T>; w.v = x; return w; }\nfn w1s(w: W1<Pt>): i64 { return w.v.x + w.v.y * 10; }\nvar gp: Pt = Pt { 2, 5 };\nsyscall(60, w1s(mkw(gp)));\n' "$PT" > "$T/p1.cyr"
build_refused_by p1 "'mkw' returns a struct by value, and a struct result needs storage in a fn's frame" "P: w1s(mkw(gp)) at top level, a W1<Pt> pair instance"

# Q (6.6.11, L9) — A GLOBAL TYPED WITH A GENERIC STRUCT INSTANCE. A declaration-zone global
# (before the first top-level statement) is registered by PARSE_GVAR_REG, which took `W1<Pt>` as
# the 8 B BASE: `G.v.x` did not parse and `w1s(G)` read the wrong storage (204, want 52). Its
# initialiser is replayed by EMIT_GVAR_INITS, which never reached the rax:rdx refusal, so even a
# NON-generic `var G: Pt = mkp(2);` there built and SIGSEGV'd on `G.x`; after a statement the
# refusal resolved the callee with FINDFN (the 8 B base's class 0), so the generic form built too.
MKW='struct W1<T> { v: T; }
fn mkw<T>(x: T): W1<T> { var w: W1<T>; w.v = x; return w; }
fn w1s(w: W1<Pt>): i64 { return w.v.x + w.v.y * 10; }
var gp: Pt = Pt { 2, 5 };'
MKPP='fn mkp(a): Pt { var w: Pt; w.x = a; w.y = 5; return w; }'
PAIR="returns a struct by value, and a struct result needs storage in a fn's frame"
printf '%s\n%s\nvar G: W1<Pt> = mkw(gp);\nsyscall(60, w1s(G));\n' "$PT" "$MKW" > "$T/q1.cyr"
build_refused_by q1 "'mkw' $PAIR" "Q: var G: W1<Pt> = mkw(gp) before the first statement (was 204)"
printf '%s\n%s\nvar k = 0;\nk = 1;\nvar G: W1<Pt> = mkw(gp);\nsyscall(60, w1s(G));\n' "$PT" "$MKW" > "$T/q2.cyr"
build_refused_by q2 "'mkw' $PAIR" "Q: the same after a statement (was rc 139)"
printf '%s\n%s\nvar G: W1<Pt> = mkw<Pt>(gp);\nsyscall(60, w1s(G));\n' "$PT" "$MKW" > "$T/q3.cyr"
build_refused_by q3 "'mkw' $PAIR" "Q: the explicit mkw<Pt>(gp) before the first statement"
printf '%s\n%s\nvar G: Pt = mkp(2);\nsyscall(60, G.x + G.y * 10);\n' "$PT" "$MKPP" > "$T/q4.cyr"
build_refused_by q4 "'mkp' $PAIR" "Q: a NON-generic var G: Pt = mkp(2) before the first statement (was SIGSEGV)"
printf '%s\n%s\nvar gr: W1<Pt>;\nfn f(): i64 { gr.v.x = 2; return gr.v.x; }\nsyscall(60, f());\n' "$PT" "$MKW" > "$T/q5.cyr"
build_refused_by q5 "uninitialized variable not allowed" "Q: a bare var gr: W1<Pt>; is the uninitialised refusal"
grep -q "expected '=', got '.'" "$T/q5.err" && bad "Q: gr.v.x on a bare var gr: W1<Pt>; did not parse (the global was the 8 B base)"
printf 'include "lib/alloc.cyr"\n%s\n%s\nvar G: W1<Pt> = alloc(16);\nfn f(): i64 { G.v.x = 2; G.v.y = 5; return w1s(G); }\nvar r = f();\nsyscall(60, r + G.v.x);\n' "$PT" "$MKW" > "$T/q6.cyr"
exits q6 54 "Q: a W1<Pt> global holding an address: G.v.x written in a fn, read at top level, w1s(G)"
printf 'include "lib/alloc.cyr"\n%s\n%s\nvar k = 0;\nk = 1;\nvar G: W1<Pt> = alloc(16);\nG.v.x = 3; G.v.y = 4;\nsyscall(60, w1s(G) + G.v.y);\n' "$PT" "$MKW" > "$T/q7.cyr"
exits q7 47 "Q: control: the same after a statement (PARSE_VAR already instantiated)"
printf 'struct B1<T> { v: T; }\nfn mkb<T>(x: T): B1<T> { var b: B1<T>; b.v = x; return b; }\nvar B: B1<i32> = mkb<i32>(7);\nsyscall(60, B.v);\n' > "$T/q8.cyr"
exits q8 7 "Q: control: an 8 B instance global from its call (rax, no pair)"

printf 'fn cnt<T>(n: T, acc: T): T { if (n == 0) { return acc; } return cnt(n - 1, acc + 1); }\nfn main(): i64 { return cnt(20000001, 0) & 127; }\nsyscall(60, main());\n' > "$T/m1.cyr"
exits m1 1 "M: a 20,000,001-deep scalar generic tail recursion"
printf '%s\n%s\nfn main(): i64 { return 3; }\nsyscall(60, main());\n' "$PT" "$GL" > "$T/m2.cyr"
exits m2 3 "M: a stub generic nobody calls with a scalar"
printf 'include "lib/simd.cyr"\nfn tw<T>(v: T): i64 { return 5; }\nfn tl<T>(v: T): i64 { var s = 0; var i = 0; while (i < 2) { s = s + 1; i = i + 1; } return s + 3; }\nfn main(): i64 { var a: f64v2; return tw(a) + tl(a); }\nsyscall(60, main());\n' > "$T/m3.cyr"
exits m3 10 "M: a vector local as an inferred argument"
# ...and it is the BASE call: byte-identical to the explicit `<i64>` spelling. Read as "struct
# 2093" the inference minted an instance named from out-of-table memory — invisible in the exit
# code, visible here as a different binary.
sed 's/tw(a) + tl(a)/tw<i64>(a) + tl<i64>(a)/' "$T/m3.cyr" > "$T/m3x.cyr"
build m3x
if [ "$rc" -ne 0 ]; then bad "M: the explicit vector control: rc $rc"
elif cmp -s "$T/m3.bin" "$T/m3x.bin"; then ok "M: a vector argument infers the base, byte-identical to tw<i64>(a)"
else bad "M: a vector argument minted an instance (differs from tw<i64>(a))"; fi
printf '%s\n%s\nfn tail(a): i64 { var p: Pt; p.x = a; p.y = 5; return g(p); }\nfn main(): i64 { %s var r = g(p); return r * 0 + tail(2); }\nsyscall(60, main());\n' "$PT" "$GL" "$MKP" > "$T/m4.cyr"
exits m4 12 "M: the struct call of the H shapes (var r = g(p); return g(p))"
printf '%s\n%s\nfn main(): i64 { %s return outer(p); }\n%s\nsyscall(60, main());\n' "$PT" "$OI" "$MKP" "$GL" > "$T/m5.cyr"
exits m5 14 "M: the struct call of the I shape, reverse order (outer(p) -> g(p))"

printf 'fn idv<T>(a: T): T { return a; }\nfn main(): i64 { var v: f64v2; var a = idv<f64v2>(v); return 42; }\nsyscall(60, main());\n' > "$T/n.cyr"
build n
nerr=$(grep -c "generic type-args must be a scalar" "$T/n.err" || true)
if [ "$rc" -eq 0 ]; then bad "N: var a = idv<f64v2>(v): BUILT (rc 0)"
elif [ "$nerr" -ne 1 ]; then bad "N: var a = idv<f64v2>(v): the refusal printed $nerr times, want 1"
else ok "N: var a = idv<f64v2>(v): refused once"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL: generic_type_arg_unknown_refused — $fails axis(es) red"; exit 1; fi
echo "PASS: generic_type_arg_unknown_refused — a type-arg naming no type is refused by name (A-B); a forwarded type parameter resolves to its binding (C-D); scalar and struct type-args unchanged (E); an enum or an unlisted scalar name is refused by name (F-G); a generic using T as a struct is refused at every scalar call, tail call, forwarding generic and &g (H-J, L), a struct beside a second type argument runs on every path and a mismatched receive is refused once (K, 6.7.1), a \`*Pt\` parameter binds i64 (O), a top-level pair instance argument is refused (P), a global typed with a generic instance is the instance and a top-level pair initialiser is refused in either zone (Q), scalar tail recursion and the struct calls still run (M), and a bad type argument in a receive is reported once (N)"
