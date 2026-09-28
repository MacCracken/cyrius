#!/bin/sh
# derive_directive_refused.sh — 6.6.8 bite 1b: a preprocessor directive INSIDE a `#derive`d
# declaration (or between the `#derive(...)` line and it) is refused by name.
#
# ⛔ WHY. The derive's body walk reads a `#` line as a comment. So in
#     #derive(Serialize)
#     struct P { a: i64;
#     #ifdef NOPE
#     b: i64;
#     #endif
#     c: i64; }
# the derive counted `b` whatever NOPE was, while the parser — after PP_IFDEF_PASS evaluated the
# copied lines — compiled one branch. Before 6.6.7 that built with rc 0 and a codec emitting
# `"#ifdef"` / `"#endif"` keys; 6.6.7's layout backstop made it rc 1 with a message about
# non-derived nested structs, which is not the cause. A directive between the `#derive` line and
# the declaration was consumed as a comment line too: `#ifdef NOPE` there was DROPPED and the
# struct compiled anyway.
# The directive cannot be evaluated in the walk instead: the walk runs in PP_PASS, before the
# `#define`s of an earlier include are registered, so it could pick the other branch from the one
# the parser compiles — silently. A conditional around the whole `#derive` + declaration works
# (axis F).
#
#   A  #ifdef / b / #endif in a struct body           -> refused, names `#ifdef` and `P`
#   B  an INDENTED #ifndef, and #else in an enum body  -> refused by name
#   C  #ifdef between #derive(...) and the struct      -> refused by name
#   D  `# ifdef` (a comment) and a mid-line `#ifdef`   -> build and serialize {"a":1,"c":3}
#   E  a stacked #derive + a comment line before it    -> build (the lines SKIPDIRS must keep)
#   F  #ifdef around the WHOLE #derive + declaration    -> build; the selected branch is used
#
# Mutations: drop the PP_DDIRCHK call in PP_DTRIV -> A, B RED (A builds rc 1 via the backstop,
# with no directive named). Drop the PP_DISDIR test in PP_DERIVE_SKIPDIRS -> C RED (rc 0: the
# `#ifdef` was swallowed). Make PP_DISDIR ignore the line-start test -> D RED.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: derive_directive_refused: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: derive_directive_refused: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
HDR='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/hashmap.cyr"
include "lib/result.cyr"
include "lib/fnptr.cyr"
include "lib/io.cyr"
include "lib/bayan.cyr"'
MAIN='fn main(): i64 { alloc_init(); var p: P; p.a = 1; p.c = 3; var sb = str_builder_new(); P_to_json(&p, sb); str_println(str_builder_build(sb)); return 0; }
var r = main(); syscall(SYS_EXIT, r);'
build() {   # <name> -> rc in $rc, stderr in $T/<name>.err
    rc=0
    "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
}
refused() { # <name> <directive> <decl> <what>
    build "$1"
    if [ "$rc" -eq 0 ]; then bad "$4: BUILT (rc 0)"
    elif ! grep -q "error: #derive: a preprocessor directive ($2)" "$T/$1.err"; then
        bad "$4: refused, but not by name: $(grep -v '^ ' "$T/$1.err" | grep -v '^note' | head -1)"
    elif [ -n "$3" ] && ! grep -q "declaration of $3;" "$T/$1.err"; then bad "$4: the message does not name $3"
    else ok "$4: refused, naming $2${3:+ and $3}"; fi
}
runs() {    # <name> <want stdout> <what>
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep -v '^ ' "$T/$1.err" | grep -v '^note' | head -1)"; return; fi
    chmod +x "$T/$1.bin"; out=$("$T/$1.bin")
    if [ "$out" = "$2" ]; then ok "$3: $out"; else bad "$3: printed '$out', want '$2'"; fi
}

printf '%s\n#derive(Serialize)\nstruct P { a: i64;\n#ifdef NOPE\nb: i64;\n#endif\nc: i64; }\n%s\n' "$HDR" "$MAIN" > "$T/a.cyr"
refused a '#ifdef' P "A: #ifdef in a derived struct body"

printf '%s\n#derive(accessors)\nstruct P {\n    a: i64;\n    #ifndef NOPE\n    b: i64;\n    #endif\n    c: i64;\n}\nfn main(): i64 { return 0; }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/b1.cyr"
refused b1 '#ifndef' P "B: an indented #ifndef in a derived struct body"
printf '%s\n#derive(Serialize)\nenum E {\n    E_A = 1;\n#else\n    E_B = 2;\n}\nfn main(): i64 { return 0; }\nvar r = main(); syscall(SYS_EXIT, r);\n' "$HDR" > "$T/b2.cyr"
refused b2 '#else' E "B: #else in a derived enum body"

printf '%s\n#derive(Serialize)\n#ifdef NOPE\nstruct P { a: i64; c: i64; }\n#endif\n%s\n' "$HDR" "$MAIN" > "$T/c.cyr"
build c
if [ "$rc" -eq 0 ]; then bad "C: #ifdef between #derive and the struct BUILT (rc 0) — the conditional was swallowed"
elif ! grep -q 'error: #derive: a preprocessor directive (#ifdef) between #derive' "$T/c.err"; then
    bad "C: refused, but not by name: $(grep -v '^ ' "$T/c.err" | grep -v '^note' | head -1)"
else ok "C: #ifdef between #derive(...) and the declaration is refused by name"; fi

printf '%s\n#derive(Serialize)\nstruct P {\n    a: i64;   #ifdef mid-line is a comment\n    # ifdef with a space is a comment\n    #ifdefined-looking comment\n    c: i64;\n}\n%s\n' "$HDR" "$MAIN" > "$T/d.cyr"
runs d '{"a":1,"c":3}' "D: comments that look like directives still build"

printf '%s\n#derive(Serialize)\n# a comment line\n#derive(accessors)\nstruct P { a: i64; c: i64; }\n%s\n' "$HDR" "$MAIN" > "$T/e.cyr"
runs e '{"a":1,"c":3}' "E: stacked #derive and a comment before the declaration"

printf '%s\n#define WIDE\n#ifdef WIDE\n#derive(Serialize)\nstruct P { a: i64; b: i64; c: i64; }\n#else\n#derive(Serialize)\nstruct P { a: i64; c: i64; }\n#endif\n%s\n' "$HDR" "$MAIN" > "$T/f1.cyr"
runs f1 '{"a":1,"b":0,"c":3}' "F: a conditional around the whole declaration (defined branch)"
printf '%s\n#ifdef WIDE\n#derive(Serialize)\nstruct P { a: i64; b: i64; c: i64; }\n#else\n#derive(Serialize)\nstruct P { a: i64; c: i64; }\n#endif\n%s\n' "$HDR" "$MAIN" > "$T/f2.cyr"
runs f2 '{"a":1,"c":3}' "F: a conditional around the whole declaration (#else branch)"

if [ "$fails" -ne 0 ]; then echo "FAIL: derive_directive_refused — $fails axis(es) red"; exit 1; fi
echo "PASS: derive_directive_refused — a directive inside a derived declaration (A-B) or between #derive and it (C) is refused by name; comments that look like directives (D) and stacked derives (E) still build; a conditional around the whole declaration works (F)"
