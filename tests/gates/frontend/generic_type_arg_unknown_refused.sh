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
#
# Mutations: drop the `_tp_resolve` consult in _type_arg_leaf -> C, D RED (refused as unknown
# `T`). Drop the refusal -> A, B RED (rc 0). Let _call_forwarded_base inline -> D RED.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: generic_type_arg_unknown_refused: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: generic_type_arg_unknown_refused: mktemp -d failed"; exit 1; }
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

if [ "$fails" -ne 0 ]; then echo "FAIL: generic_type_arg_unknown_refused — $fails axis(es) red"; exit 1; fi
echo "PASS: generic_type_arg_unknown_refused — a type-arg naming no type is refused by name (A-B); a forwarded type parameter resolves to its binding (C-D); scalar and struct type-args unchanged (E)"
